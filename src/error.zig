//! Error types for OAuth operations
//!
//! This module defines all error types used throughout the Schlussel OAuth library.
//! Errors are categorized by their source and provide detailed information for debugging.

const std = @import("std");

/// Errors that can occur during OAuth operations
pub const OAuthError = error{
    /// Invalid parameter provided to a function
    InvalidParameter,
    /// Storage operation failed
    StorageError,
    /// HTTP request failed
    HttpError,
    /// User denied authorization
    AuthorizationDenied,
    /// Access token has expired
    TokenExpired,
    /// No refresh token available for refresh operation
    NoRefreshToken,
    /// Invalid state parameter (CSRF protection failure)
    InvalidState,
    /// Device code has expired before user completed authorization
    DeviceCodeExpired,
    /// Device authorization is still pending user action
    AuthorizationPending,
    /// Rate limit exceeded, slow down polling
    SlowDown,
    /// JSON parsing or serialization failed
    JsonError,
    /// I/O operation failed
    IoError,
    /// Server returned an unexpected response
    ServerError,
    /// Callback server failed to start
    CallbackServerError,
    /// Configuration error
    ConfigurationError,
    /// Lock acquisition failed
    LockError,
    /// Unsupported operation for this provider
    UnsupportedOperation,
    /// Memory allocation failed
    OutOfMemory,
    /// Connection refused or network unreachable
    ConnectionFailed,
    /// Request timed out
    Timeout,
};

/// Extended error information for debugging
pub const ErrorInfo = struct {
    /// The error that occurred
    err: OAuthError,
    /// Human-readable error message
    message: []const u8,
    /// Optional error code from the server
    server_code: ?[]const u8 = null,
    /// Optional server error description
    server_description: ?[]const u8 = null,

    pub fn format(
        self: ErrorInfo,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("OAuthError: {s}", .{self.message});
        if (self.server_code) |code| {
            try writer.print(" (code: {s})", .{code});
        }
        if (self.server_description) |desc| {
            try writer.print(" - {s}", .{desc});
        }
    }
};

/// Convert an OAuth error to an FFI error code
pub fn toErrorCode(err: OAuthError) i32 {
    return switch (err) {
        error.InvalidParameter => 1,
        error.StorageError => 2,
        error.HttpError => 3,
        error.AuthorizationDenied => 4,
        error.TokenExpired => 5,
        error.NoRefreshToken => 6,
        error.InvalidState => 7,
        error.DeviceCodeExpired => 8,
        error.JsonError => 9,
        error.IoError => 10,
        error.ServerError => 11,
        error.CallbackServerError => 12,
        error.ConfigurationError => 13,
        error.LockError => 14,
        error.UnsupportedOperation => 15,
        error.OutOfMemory => 16,
        error.ConnectionFailed => 17,
        error.Timeout => 18,
        error.AuthorizationPending => 19,
        error.SlowDown => 20,
    };
}

/// Convert an FFI error code back to an OAuth error
pub fn fromErrorCode(code: i32) ?OAuthError {
    return switch (code) {
        0 => null, // Success
        1 => error.InvalidParameter,
        2 => error.StorageError,
        3 => error.HttpError,
        4 => error.AuthorizationDenied,
        5 => error.TokenExpired,
        6 => error.NoRefreshToken,
        7 => error.InvalidState,
        8 => error.DeviceCodeExpired,
        9 => error.JsonError,
        10 => error.IoError,
        11 => error.ServerError,
        12 => error.CallbackServerError,
        13 => error.ConfigurationError,
        14 => error.LockError,
        15 => error.UnsupportedOperation,
        16 => error.OutOfMemory,
        17 => error.ConnectionFailed,
        18 => error.Timeout,
        19 => error.AuthorizationPending,
        20 => error.SlowDown,
        else => error.IoError, // Unknown error
    };
}

test "error code conversion roundtrip" {
    const errors = [_]OAuthError{
        error.InvalidParameter,
        error.StorageError,
        error.HttpError,
        error.AuthorizationDenied,
        error.TokenExpired,
        error.NoRefreshToken,
        error.InvalidState,
        error.DeviceCodeExpired,
        error.JsonError,
        error.IoError,
    };

    for (errors) |err| {
        const code = toErrorCode(err);
        const recovered = fromErrorCode(code);
        try std.testing.expectEqual(err, recovered.?);
    }
}

test "error code zero is success" {
    try std.testing.expectEqual(@as(?OAuthError, null), fromErrorCode(0));
}
