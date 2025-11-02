/// Example: Cross-Process Token Refresh
///
/// This example demonstrates how to safely refresh tokens across multiple processes
/// using file-based locking. This prevents race conditions where multiple processes
/// try to refresh the same token simultaneously.
///
/// Run multiple instances simultaneously to see the locking in action:
/// ```bash
/// cargo run --example cross_process_refresh &
/// cargo run --example cross_process_refresh &
/// cargo run --example cross_process_refresh &
/// wait
/// ```
use schlussel::prelude::*;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

fn main() {
    println!("=== Cross-Process Token Refresh Example ===");
    println!("Process ID: {}\n", std::process::id());

    // Create file storage (shared across processes)
    let storage = Arc::new(
        FileStorage::new("schlussel-multiprocess-example").expect("Failed to create file storage"),
    );

    // Configure OAuth
    let config = OAuthConfig {
        client_id: "test-client".to_string(),
        authorization_endpoint: "https://example.com/oauth/authorize".to_string(),
        token_endpoint: "https://example.com/oauth/token".to_string(),
        redirect_uri: "http://localhost:8080/callback".to_string(),
        scope: Some("read write".to_string()),
        device_authorization_endpoint: None,
    };

    let client = Arc::new(OAuthClient::new(config, storage.clone()));

    // Create or load an expiring token
    let token_key = "example.com:multiprocess-test";

    let token = match client.get_token(token_key) {
        Ok(Some(existing)) => {
            println!("Found existing token");
            existing
        }
        _ => {
            println!("Creating new token that will expire soon");
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs();

            let token = Token {
                access_token: "old_access_token".to_string(),
                refresh_token: Some("refresh_token_12345".to_string()),
                token_type: "Bearer".to_string(),
                expires_in: Some(5),
                expires_at: Some(now + 5), // Expires in 5 seconds
                scope: Some("read write".to_string()),
            };

            client.save_token(token_key, token.clone()).unwrap();
            token
        }
    };

    println!("Token expires at: {}", token.expires_at.unwrap());
    println!("Token is expired: {}\n", token.is_expired());

    // Wait a moment to let token expire
    if !token.is_expired() {
        println!("Waiting for token to expire...");
        std::thread::sleep(std::time::Duration::from_secs(6));
    }

    // Create token refresher WITH cross-process locking
    println!("Creating TokenRefresher with file locking...");
    let refresher =
        TokenRefresher::with_file_locking(client.clone(), "schlussel-multiprocess-example")
            .expect("Failed to create refresher with file locking");

    println!(
        "Attempting to refresh token (Process {})...",
        std::process::id()
    );
    println!("If multiple processes are running, only one will actually refresh.\n");

    // This will:
    // 1. Acquire a cross-process lock
    // 2. Re-read the token (in case another process already refreshed it)
    // 3. Check if still expired
    // 4. Refresh only if needed
    // 5. Release the lock
    match refresher.refresh_token_for_key(token_key) {
        Ok(new_token) => {
            println!(
                "✓ Token refresh successful (Process {})",
                std::process::id()
            );
            println!("  Access token: {}...", &new_token.access_token[..20]);

            if new_token.access_token == "old_access_token" {
                println!("  ℹ Token was already refreshed by another process");
            } else {
                println!("  ℹ This process performed the actual refresh");
            }
        }
        Err(e) => {
            // In a real application, the HTTP refresh would happen here
            // For this example, we'll just simulate success
            println!("Note: This is a demo. In production, the token would be");
            println!("refreshed via HTTP request to the OAuth server.");
            println!("Error (expected in demo): {}", e);
        }
    }

    println!("\n=== Summary ===");
    println!("With cross-process locking:");
    println!("✓ Multiple processes can safely refresh tokens");
    println!("✓ No race conditions or duplicate refresh requests");
    println!("✓ Efficient: only one process does the actual HTTP refresh");
    println!("✓ All processes get the refreshed token");
}
