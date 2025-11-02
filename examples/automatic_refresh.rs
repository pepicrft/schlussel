/// Example: Automatic Token Refresh
///
/// This example demonstrates the automatic token refresh feature, which
/// automatically checks expiration and refreshes tokens when needed.
///
/// Run:
/// cargo run --example automatic_refresh
use schlussel::prelude::*;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

fn main() {
    println!("=== Automatic Token Refresh Example ===\n");

    // Create file storage
    let storage = Arc::new(
        FileStorage::new("schlussel-auto-refresh-example").expect("Failed to create file storage"),
    );

    // Configure OAuth
    let config = OAuthConfig {
        client_id: "example-client".to_string(),
        authorization_endpoint: "https://example.com/oauth/authorize".to_string(),
        token_endpoint: "https://example.com/oauth/token".to_string(),
        redirect_uri: "http://localhost:8080/callback".to_string(),
        scope: Some("read write".to_string()),
        device_authorization_endpoint: None,
    };

    let client = Arc::new(OAuthClient::new(config, storage.clone()));
    let refresher = TokenRefresher::new(client.clone());

    // Simulate different token scenarios
    demonstrate_valid_token(&client, &refresher);
    println!();
    demonstrate_nearly_expired_token(&client, &refresher);
    println!();
    demonstrate_expired_token(&client, &refresher);
}

fn demonstrate_valid_token(
    client: &Arc<OAuthClient<FileStorage>>,
    refresher: &TokenRefresher<FileStorage>,
) {
    println!("=== Scenario 1: Valid Token ===");

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    // Create a fresh token with 1 hour validity
    let token = Token {
        access_token: "fresh_access_token_12345".to_string(),
        refresh_token: Some("refresh_token_67890".to_string()),
        token_type: "Bearer".to_string(),
        expires_in: Some(3600),
        expires_at: Some(now + 3600),
        scope: Some("read write".to_string()),
    };

    client.save_token("example.com:scenario1", token).unwrap();

    println!("Token info:");
    println!("  Expires in: 3600 seconds (1 hour)");
    println!("  Is expired: false");
    println!();

    // Use get_valid_token - should return existing token without refresh
    println!("Calling refresher.get_valid_token()...");
    match refresher.get_valid_token("example.com:scenario1") {
        Ok(token) => {
            println!("✓ Token is still valid");
            println!("  Access token: {}...", &token.access_token[..20]);
            println!("  No refresh needed!");
        }
        Err(e) => {
            println!("✗ Error: {}", e);
        }
    }
}

fn demonstrate_nearly_expired_token(
    client: &Arc<OAuthClient<FileStorage>>,
    _refresher: &TokenRefresher<FileStorage>,
) {
    println!("=== Scenario 2: Nearly Expired Token (Proactive Refresh) ===");

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    // Create a token that's 90% through its lifetime
    let token = Token {
        access_token: "nearly_expired_token".to_string(),
        refresh_token: Some("refresh_token_abc".to_string()),
        token_type: "Bearer".to_string(),
        expires_in: Some(3600),      // Originally 1 hour
        expires_at: Some(now + 360), // Only 360 seconds (6 minutes) remaining
        scope: Some("read write".to_string()),
    };

    client.save_token("example.com:scenario2", token).unwrap();

    println!("Token info:");
    println!("  Total lifetime: 3600 seconds (1 hour)");
    println!("  Time remaining: 360 seconds (6 minutes)");
    println!("  Percentage elapsed: 90%");
    println!("  Is expired: false (but close!)");
    println!();

    // Use get_valid_token_with_threshold with 0.8 (80%) threshold
    println!("Calling refresher.get_valid_token_with_threshold(key, 0.8)...");
    println!("Threshold: 0.8 (refresh when 80% of lifetime elapsed)");
    println!();

    println!("⚠ Token is 90% through its lifetime (> 80% threshold)");
    println!("ℹ Would trigger proactive refresh in production");
    println!("  (Actual HTTP refresh not demonstrated in this example)");
    println!();

    // In production with a real OAuth server, this would:
    // 1. Detect that 90% > 80% threshold
    // 2. Automatically call the refresh endpoint
    // 3. Return a fresh token

    println!("Benefits of proactive refresh:");
    println!("  ✓ Avoid using expired tokens in requests");
    println!("  ✓ Better reliability (refresh before expiration)");
    println!("  ✓ Reduced risk of authentication errors");
}

fn demonstrate_expired_token(
    client: &Arc<OAuthClient<FileStorage>>,
    _refresher: &TokenRefresher<FileStorage>,
) {
    println!("=== Scenario 3: Expired Token ===");

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    // Create an expired token
    let token = Token {
        access_token: "expired_token_xyz".to_string(),
        refresh_token: Some("refresh_token_def".to_string()),
        token_type: "Bearer".to_string(),
        expires_in: Some(3600),
        expires_at: Some(now - 100), // Expired 100 seconds ago
        scope: Some("read write".to_string()),
    };

    client.save_token("example.com:scenario3", token).unwrap();

    println!("Token info:");
    println!("  Expired: 100 seconds ago");
    println!("  Is expired: true");
    println!();

    println!("Calling refresher.get_valid_token()...");
    println!("⚠ Token is expired");
    println!("ℹ Would automatically refresh in production");
    println!("  (Actual HTTP refresh not demonstrated in this example)");
    println!();

    // In production with a real OAuth server, this would:
    // 1. Detect that token is expired
    // 2. Automatically call the refresh endpoint
    // 3. Save the new token
    // 4. Return the fresh token

    println!("Without automatic refresh, you'd have to write:");
    println!("  let token = client.get_token(key)?;");
    println!("  if token.is_expired() {{");
    println!("      token = refresher.refresh_token_for_key(key)?;");
    println!("  }}");
    println!();
    println!("With automatic refresh, just:");
    println!("  let token = refresher.get_valid_token(key)?;");
    println!();
    println!("✓ Much simpler and less error-prone!");
}

#[allow(dead_code)]
fn print_summary() {
    println!("\n=== Summary ===");
    println!();
    println!("Two convenient methods for automatic refresh:");
    println!();
    println!("1. get_valid_token(key)");
    println!("   - Refreshes only if token is expired");
    println!("   - Simple and straightforward");
    println!();
    println!("2. get_valid_token_with_threshold(key, 0.8)");
    println!("   - Proactive refresh before expiration");
    println!("   - Recommended threshold: 0.8 (refresh at 80% lifetime)");
    println!("   - Better reliability, fewer auth errors");
    println!();
    println!("Both methods:");
    println!("  ✓ Handle expiration checking automatically");
    println!("  ✓ Refresh tokens transparently");
    println!("  ✓ Work with cross-process locking");
    println!("  ✓ Return valid, ready-to-use tokens");
}
