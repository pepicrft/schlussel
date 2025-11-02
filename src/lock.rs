/// Cross-process locking for token refresh coordination
use crate::error::Result;
use fs2::FileExt;
use std::fs::{self, File, OpenOptions};
use std::path::{Path, PathBuf};

/// Manager for cross-process refresh locks
///
/// Uses file-based locks to coordinate token refreshes across multiple processes.
/// This prevents race conditions where multiple processes try to refresh the same
/// token simultaneously.
#[derive(Debug, Clone)]
pub struct RefreshLockManager {
    lock_dir: PathBuf,
}

impl RefreshLockManager {
    /// Create a new lock manager with a custom lock directory
    pub fn new(lock_dir: PathBuf) -> Result<Self> {
        fs::create_dir_all(&lock_dir)?;
        Ok(Self { lock_dir })
    }

    /// Create a lock manager using the default directory
    ///
    /// Uses XDG_RUNTIME_DIR on Unix or temp directory on other platforms
    pub fn with_default_dir() -> Result<Self> {
        let lock_dir = Self::default_lock_dir()?;
        Self::new(lock_dir)
    }

    /// Create a lock manager for a specific application
    pub fn for_app(app_name: &str) -> Result<Self> {
        let mut lock_dir = Self::default_lock_dir()?;
        lock_dir.push(app_name);
        Self::new(lock_dir)
    }

    fn default_lock_dir() -> Result<PathBuf> {
        // Try XDG_RUNTIME_DIR first (Linux/Unix)
        if let Ok(runtime_dir) = std::env::var("XDG_RUNTIME_DIR") {
            let mut path = PathBuf::from(runtime_dir);
            path.push("schlussel-locks");
            return Ok(path);
        }

        // Fall back to temp directory with user-specific subdirectory
        let mut path = std::env::temp_dir();
        path.push(format!("schlussel-locks-{}", Self::get_user_id()));
        Ok(path)
    }

    #[cfg(unix)]
    fn get_user_id() -> String {
        use std::os::unix::fs::MetadataExt;
        std::env::current_exe()
            .and_then(|p| p.metadata())
            .map(|m| m.uid().to_string())
            .unwrap_or_else(|_| "unknown".to_string())
    }

    #[cfg(not(unix))]
    fn get_user_id() -> String {
        std::env::var("USERNAME")
            .or_else(|_| std::env::var("USER"))
            .unwrap_or_else(|_| "unknown".to_string())
    }

    /// Acquire an exclusive lock for a token key
    ///
    /// This will block until the lock is acquired. The lock is automatically
    /// released when the returned `RefreshLock` is dropped.
    ///
    /// # Example
    ///
    /// ```no_run
    /// use schlussel::lock::RefreshLockManager;
    ///
    /// let manager = RefreshLockManager::default().unwrap();
    /// let lock = manager.acquire_lock("github.com:user").unwrap();
    /// // Do token refresh here
    /// // Lock automatically released when `lock` goes out of scope
    /// ```
    pub fn acquire_lock(&self, key: &str) -> Result<RefreshLock> {
        let lock_path = self.lock_path(key);

        // Ensure parent directory exists
        if let Some(parent) = lock_path.parent() {
            fs::create_dir_all(parent)?;
        }

        // Open or create the lock file
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&lock_path)?;

        // Acquire exclusive lock (blocks until available)
        file.lock_exclusive()?;

        Ok(RefreshLock {
            file: Some(file),
            path: lock_path,
        })
    }

    /// Try to acquire an exclusive lock without blocking
    ///
    /// Returns `None` if the lock is already held by another process.
    pub fn try_acquire_lock(&self, key: &str) -> Result<Option<RefreshLock>> {
        let lock_path = self.lock_path(key);

        if let Some(parent) = lock_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&lock_path)?;

        match file.try_lock_exclusive() {
            Ok(()) => Ok(Some(RefreshLock {
                file: Some(file),
                path: lock_path,
            })),
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    fn lock_path(&self, key: &str) -> PathBuf {
        // Sanitize the key for use in filename
        let safe_key = key.replace(['/', '\\', ':', '*', '?', '"', '<', '>', '|'], "_");
        self.lock_dir.join(format!("{}.lock", safe_key))
    }
}

/// RAII guard for a refresh lock
///
/// The lock is automatically released when this guard is dropped.
pub struct RefreshLock {
    file: Option<File>,
    path: PathBuf,
}

impl RefreshLock {
    /// Get the path to the lock file
    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for RefreshLock {
    fn drop(&mut self) {
        if let Some(file) = self.file.take() {
            // Unlock the file
            let _ = file.unlock();
        }

        // Optionally remove the lock file (best effort)
        // Note: On some systems, this might fail if another process is waiting
        let _ = fs::remove_file(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn test_lock_manager_creation() {
        let temp_dir = std::env::temp_dir().join(format!("test_locks_{}", rand::random::<u32>()));
        let _manager = RefreshLockManager::new(temp_dir.clone()).unwrap();

        assert!(temp_dir.exists());

        // Cleanup
        fs::remove_dir_all(temp_dir).ok();
    }

    #[test]
    fn test_acquire_and_release_lock() {
        let temp_dir = std::env::temp_dir().join(format!("test_locks_{}", rand::random::<u32>()));
        let manager = RefreshLockManager::new(temp_dir.clone()).unwrap();

        // Acquire lock
        let lock = manager.acquire_lock("test-key").unwrap();
        assert!(lock.path().exists());

        // Release lock
        drop(lock);

        // Should be able to acquire again
        let lock2 = manager.acquire_lock("test-key").unwrap();
        drop(lock2);

        // Cleanup
        fs::remove_dir_all(temp_dir).ok();
    }

    #[test]
    fn test_concurrent_lock_attempts() {
        let temp_dir = std::env::temp_dir().join(format!("test_locks_{}", rand::random::<u32>()));
        let manager = Arc::new(RefreshLockManager::new(temp_dir.clone()).unwrap());

        let manager1 = manager.clone();
        let manager2 = manager.clone();

        let handle1 = thread::spawn(move || {
            let _lock = manager1.acquire_lock("concurrent-test").unwrap();
            thread::sleep(Duration::from_millis(200));
            "thread1"
        });

        // Give thread1 time to acquire the lock
        thread::sleep(Duration::from_millis(50));

        let handle2 = thread::spawn(move || {
            // This should block until thread1 releases the lock
            let _lock = manager2.acquire_lock("concurrent-test").unwrap();
            "thread2"
        });

        let result1 = handle1.join().unwrap();
        let result2 = handle2.join().unwrap();

        assert_eq!(result1, "thread1");
        assert_eq!(result2, "thread2");

        // Cleanup
        fs::remove_dir_all(temp_dir).ok();
    }

    #[test]
    fn test_try_acquire_lock() {
        let temp_dir = std::env::temp_dir().join(format!("test_locks_{}", rand::random::<u32>()));
        let manager = RefreshLockManager::new(temp_dir.clone()).unwrap();

        // First acquisition should succeed
        let lock1 = manager.try_acquire_lock("try-test").unwrap();
        assert!(lock1.is_some());

        // Second acquisition should fail (already locked)
        let lock2 = manager.try_acquire_lock("try-test").unwrap();
        assert!(lock2.is_none());

        // Release first lock
        drop(lock1);

        // Third acquisition should succeed
        let lock3 = manager.try_acquire_lock("try-test").unwrap();
        assert!(lock3.is_some());

        // Cleanup
        fs::remove_dir_all(temp_dir).ok();
    }

    #[test]
    fn test_key_sanitization() {
        let temp_dir = std::env::temp_dir().join(format!("test_locks_{}", rand::random::<u32>()));
        let manager = RefreshLockManager::new(temp_dir.clone()).unwrap();

        // Keys with special characters should be sanitized
        let lock = manager.acquire_lock("domain.com:user/name").unwrap();
        assert!(lock
            .path()
            .to_str()
            .unwrap()
            .contains("domain.com_user_name.lock"));

        // Cleanup
        fs::remove_dir_all(temp_dir).ok();
    }
}
