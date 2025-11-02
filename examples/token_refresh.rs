/// Example: Token Refresh
///
/// This example demonstrates how to check token expiration and refresh tokens.
///
/// Run:
/// cargo run --example token_refresh
use schlussel::prelude::*;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

fn main() {
    println!("=== Token Refresh Example ===\n");

    // Create in-memory storage for this example
    let storage = Arc::new(MemoryStorage::new());

    // Create a mock OAuth config (not used for refresh in this example)
    let config = OAuthConfig {
        client_id: "example-client".to_string(),
        authorization_endpoint: "https://example.com/oauth/authorize".to_string(),
        token_endpoint: "https://example.com/oauth/token".to_string(),
        redirect_uri: "http://127.0.0.1:8080/callback".to_string(),
        scope: Some("read write".to_string()),
        device_authorization_endpoint: None,
    };

    let client = Arc::new(OAuthClient::new(config, storage.clone()));

    // Create a token that's about to expire
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let expiring_token = Token {
        access_token: "old_access_token_12345".to_string(),
        refresh_token: Some("refresh_token_67890".to_string()),
        token_type: "Bearer".to_string(),
        expires_in: Some(3600),
        expires_at: Some(now + 10), // Expires in 10 seconds
        scope: Some("read write".to_string()),
    };

    // Save the token
    client
        .save_token("example.com:user", expiring_token.clone())
        .expect("Failed to save token");

    println!("Saved token that expires in 10 seconds");
    println!("  Access token: {}...", &expiring_token.access_token[..20]);
    println!("  Expires at: {}", expiring_token.expires_at.unwrap());
    println!("  Is expired: {}\n", expiring_token.is_expired());

    // Check if token is expired
    let token = client
        .get_token("example.com:user")
        .expect("Failed to get token")
        .expect("Token not found");

    if token.is_expired() {
        println!("⚠ Token is expired, refreshing...");

        if let Some(refresh_token) = &token.refresh_token {
            // In a real application, this would make an HTTP request
            // For this example, we'll just demonstrate the pattern
            println!(
                "Would refresh using refresh token: {}...",
                &refresh_token[..20]
            );

            // Uncomment this in a real application:
            // match client.refresh_token(refresh_token) {
            //     Ok(new_token) => {
            //         client.save_token("example.com:user", new_token).unwrap();
            //         println!("✓ Token refreshed successfully");
            //     }
            //     Err(e) => {
            //         eprintln!("✗ Failed to refresh token: {}", e);
            //     }
            // }
        } else {
            println!("✗ No refresh token available");
        }
    } else {
        println!("✓ Token is still valid");

        let time_until_expiry = token.expires_at.unwrap() - now;
        println!("  Time until expiry: {} seconds", time_until_expiry);
    }

    // Demonstrate thread-safe refresh
    println!("\n=== Thread-Safe Token Refresh ===");

    let refresher = TokenRefresher::new(client.clone());

    println!("TokenRefresher ensures only one refresh happens at a time");
    println!("Even if multiple threads request a refresh simultaneously.\n");

    // In a real multi-threaded application:
    // let token = refresher.refresh_token_for_key("example.com:user").unwrap();

    println!("Before application exit, wait for pending refreshes:");
    refresher.wait_for_refresh("example.com:user");
    println!("✓ All refreshes complete");
}
