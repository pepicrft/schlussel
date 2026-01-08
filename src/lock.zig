//! Cross-process file locking for token refresh coordination
//!
//! This module provides file-based locks to coordinate token refresh
//! across multiple processes. It uses advisory locking (flock on Unix,
//! LockFileEx on Windows) for cross-process synchronization.
//!
//! ## Example
//!
//! ```zig
//! var lock_manager = try RefreshLockManager.init(allocator, "my-app");
//! defer lock_manager.deinit();
//!
//! // Acquire lock for a specific token
//! var lock = try lock_manager.acquire("github_token");
//! defer lock.release();
//!
//! // Perform token refresh...
//! ```

const std = @import("std");
const fs = std.fs;
const posix = std.posix;
const Allocator = std.mem.Allocator;

/// Manager for refresh locks
pub const RefreshLockManager = struct {
    allocator: Allocator,
    lock_dir: []const u8,

    /// Initialize the lock manager with an application name
    ///
    /// Creates locks in a platform-appropriate directory
    pub fn init(allocator: Allocator, app_name: []const u8) !RefreshLockManager {
        const lock_dir = try getLockDirectory(allocator, app_name);
        errdefer allocator.free(lock_dir);

        // Ensure lock directory exists
        fs.cwd().makePath(lock_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        return .{
            .allocator = allocator,
            .lock_dir = lock_dir,
        };
    }

    /// Initialize with a custom lock directory
    pub fn initWithPath(allocator: Allocator, path: []const u8) !RefreshLockManager {
        const lock_dir = try allocator.dupe(u8, path);
        errdefer allocator.free(lock_dir);

        fs.cwd().makePath(lock_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        return .{
            .allocator = allocator,
            .lock_dir = lock_dir,
        };
    }

    pub fn deinit(self: *RefreshLockManager) void {
        self.allocator.free(self.lock_dir);
    }

    /// Acquire an exclusive lock for a token key
    ///
    /// The lock is held until the returned RefreshLock is released.
    /// This is a blocking operation.
    pub fn acquire(self: *RefreshLockManager, key: []const u8) !RefreshLock {
        return RefreshLock.acquire(self.allocator, self.lock_dir, key);
    }

    /// Try to acquire a lock without blocking
    ///
    /// Returns null if the lock is held by another process
    pub fn tryAcquire(self: *RefreshLockManager, key: []const u8) !?RefreshLock {
        return RefreshLock.tryAcquire(self.allocator, self.lock_dir, key);
    }

    fn getLockDirectory(allocator: Allocator, app_name: []const u8) ![]const u8 {
        const builtin = @import("builtin");

        if (builtin.os.tag == .linux) {
            // XDG Runtime directory or temp
            if (std.posix.getenv("XDG_RUNTIME_DIR")) |runtime_dir| {
                return std.fmt.allocPrint(allocator, "{s}/{s}/locks", .{ runtime_dir, app_name });
            }
            return std.fmt.allocPrint(allocator, "/tmp/{s}/locks", .{app_name});
        } else if (builtin.os.tag == .macos) {
            if (std.posix.getenv("HOME")) |home| {
                return std.fmt.allocPrint(allocator, "{s}/Library/Caches/{s}/locks", .{ home, app_name });
            }
            return std.fmt.allocPrint(allocator, "/tmp/{s}/locks", .{app_name});
        } else if (builtin.os.tag == .windows) {
            if (std.posix.getenv("LOCALAPPDATA")) |local_app_data| {
                return std.fmt.allocPrint(allocator, "{s}\\{s}\\locks", .{ local_app_data, app_name });
            }
            return std.fmt.allocPrint(allocator, "C:\\Temp\\{s}\\locks", .{app_name});
        }

        return std.fmt.allocPrint(allocator, "/tmp/{s}/locks", .{app_name});
    }
};

/// An exclusive lock for token refresh operations
pub const RefreshLock = struct {
    allocator: Allocator,
    file: ?fs.File,
    lock_path: []const u8,

    /// Acquire a blocking exclusive lock
    pub fn acquire(allocator: Allocator, lock_dir: []const u8, key: []const u8) !RefreshLock {
        const lock_path = try std.fmt.allocPrint(allocator, "{s}/{s}.lock", .{ lock_dir, key });
        errdefer allocator.free(lock_path);

        const file = try fs.cwd().createFile(lock_path, .{ .lock = .exclusive });

        return .{
            .allocator = allocator,
            .file = file,
            .lock_path = lock_path,
        };
    }

    /// Try to acquire a non-blocking exclusive lock
    ///
    /// Returns null if the lock cannot be acquired immediately
    pub fn tryAcquire(allocator: Allocator, lock_dir: []const u8, key: []const u8) !?RefreshLock {
        const lock_path = try std.fmt.allocPrint(allocator, "{s}/{s}.lock", .{ lock_dir, key });
        errdefer allocator.free(lock_path);

        const file = fs.cwd().createFile(lock_path, .{ .lock = .exclusive, .lock_nonblocking = true }) catch |err| {
            if (err == error.WouldBlock) {
                allocator.free(lock_path);
                return null;
            }
            return err;
        };

        return .{
            .allocator = allocator,
            .file = file,
            .lock_path = lock_path,
        };
    }

    /// Release the lock
    pub fn release(self: *RefreshLock) void {
        if (self.file) |file| {
            file.close();
            self.file = null;
        }
        self.allocator.free(self.lock_path);
    }

    /// Check if this lock is currently held
    pub fn isHeld(self: *const RefreshLock) bool {
        return self.file != null;
    }

    /// Get the path to the lock file
    pub fn getPath(self: *const RefreshLock) []const u8 {
        return self.lock_path;
    }
};

/// RAII wrapper for automatic lock release
pub const ScopedLock = struct {
    lock: RefreshLock,

    pub fn init(lock: RefreshLock) ScopedLock {
        return .{ .lock = lock };
    }

    pub fn deinit(self: *ScopedLock) void {
        self.lock.release();
    }

    pub fn isHeld(self: *const ScopedLock) bool {
        return self.lock.isHeld();
    }
};

/// Check-then-refresh pattern implementation
///
/// Acquires a lock, checks if refresh is still needed (another process
/// might have refreshed while waiting for the lock), then performs refresh.
pub const CheckThenRefresh = struct {
    lock_manager: *RefreshLockManager,
    check_fn: *const fn (*anyopaque) bool,
    refresh_fn: *const fn (*anyopaque) anyerror!void,
    context: *anyopaque,

    /// Execute the check-then-refresh pattern
    ///
    /// 1. Acquire exclusive lock
    /// 2. Check if refresh is still needed
    /// 3. If needed, perform refresh
    /// 4. Release lock
    pub fn execute(self: *CheckThenRefresh, key: []const u8) !void {
        var lock = try self.lock_manager.acquire(key);
        defer lock.release();

        // Check if refresh is still needed after acquiring lock
        if (!self.check_fn(self.context)) {
            // Another process already refreshed
            return;
        }

        // Perform the refresh
        try self.refresh_fn(self.context);
    }

    /// Try to execute without blocking
    ///
    /// Returns false if lock could not be acquired
    pub fn tryExecute(self: *CheckThenRefresh, key: []const u8) !bool {
        var lock = (try self.lock_manager.tryAcquire(key)) orelse return false;
        defer lock.release();

        if (!self.check_fn(self.context)) {
            return true; // Already refreshed
        }

        try self.refresh_fn(self.context);
        return true;
    }
};

test "RefreshLockManager initialization" {
    const allocator = std.testing.allocator;

    var manager = try RefreshLockManager.initWithPath(allocator, "/tmp/schlussel-test-locks");
    defer manager.deinit();

    try std.testing.expectEqualStrings("/tmp/schlussel-test-locks", manager.lock_dir);
}

test "RefreshLock acquire and release" {
    const allocator = std.testing.allocator;

    var manager = try RefreshLockManager.initWithPath(allocator, "/tmp/schlussel-test-locks");
    defer manager.deinit();

    var lock = try manager.acquire("test_token");
    try std.testing.expect(lock.isHeld());

    lock.release();
    try std.testing.expect(!lock.isHeld());
}

test "RefreshLock tryAcquire when lock is held" {
    const allocator = std.testing.allocator;

    var manager = try RefreshLockManager.initWithPath(allocator, "/tmp/schlussel-test-locks");
    defer manager.deinit();

    // Acquire first lock
    var lock1 = try manager.acquire("exclusive_test");
    defer lock1.release();

    // Try to acquire second lock (should fail)
    const lock2 = try manager.tryAcquire("exclusive_test");
    try std.testing.expect(lock2 == null);
}

test "ScopedLock automatic release" {
    const allocator = std.testing.allocator;

    var manager = try RefreshLockManager.initWithPath(allocator, "/tmp/schlussel-test-locks");
    defer manager.deinit();

    {
        var scoped = ScopedLock.init(try manager.acquire("scoped_test"));
        defer scoped.deinit();

        try std.testing.expect(scoped.isHeld());
    }

    // Lock should be released, so we can acquire it again
    var lock = try manager.acquire("scoped_test");
    defer lock.release();
    try std.testing.expect(lock.isHeld());
}
