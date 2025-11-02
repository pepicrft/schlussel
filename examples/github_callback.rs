/// Example: GitHub OAuth using Authorization Code Flow with Callback Server
///
/// This example demonstrates how to authenticate with GitHub using the traditional
/// authorization code flow with an automatic local callback server.
///
/// Setup:
/// 1. Create a GitHub OAuth App at https://github.com/settings/developers
/// 2. Set the callback URL to: http://127.0.0.1:8080/callback (or leave it empty)
/// 3. Set your client ID as an environment variable: export GITHUB_CLIENT_ID="your_client_id"
///
/// Run:
/// cargo run --example github_callback
use schlussel::prelude::*;
use std::env;
use std::sync::Arc;

fn main() {
    // Get client ID from environment
    let client_id = env::var("GITHUB_CLIENT_ID").expect(
        "GITHUB_CLIENT_ID environment variable not set. \
         Create an OAuth app at https://github.com/settings/developers",
    );

    println!("=== GitHub OAuth Example (Authorization Code Flow) ===\n");

    // Create file storage
    let storage =
        Arc::new(FileStorage::new("schlussel-examples").expect("Failed to create file storage"));

    // Configure OAuth for GitHub
    let config = OAuthConfig {
        client_id,
        authorization_endpoint: "https://github.com/login/oauth/authorize".to_string(),
        token_endpoint: "https://github.com/login/oauth/access_token".to_string(),
        redirect_uri: "http://127.0.0.1/callback".to_string(), // Will be overridden by callback server
        scope: Some("repo user".to_string()),
        device_authorization_endpoint: None, // Not using Device Flow
    };

    // Create OAuth client
    let client = OAuthClient::new(config, storage.clone());

    // Authorize using callback server
    println!("Starting Authorization Code Flow with callback server...\n");

    match client.authorize() {
        Ok(token) => {
            println!("\n✓ Successfully authorized!");
            println!("Access token: {}...", &token.access_token[..20]);

            if let Some(expires_in) = token.expires_in {
                println!("Expires in: {} seconds", expires_in);
            }

            // Save token
            client
                .save_token("github.com:callback-example", token)
                .expect("Failed to save token");

            println!("\nToken saved to storage.");

            // Example: Use the token
            demo_api_request(&client);
        }
        Err(e) => {
            eprintln!("\n✗ Authorization failed: {}", e);
            std::process::exit(1);
        }
    }
}

fn demo_api_request(client: &OAuthClient<FileStorage>) {
    println!("\n=== Testing GitHub API ===");

    // Retrieve the token
    let token = client
        .get_token("github.com:callback-example")
        .expect("Failed to get token")
        .expect("Token not found");

    // Make a simple API request
    let http_client = reqwest::blocking::Client::new();

    match http_client
        .get("https://api.github.com/user")
        .header("Authorization", format!("Bearer {}", token.access_token))
        .header("User-Agent", "schlussel-example")
        .send()
    {
        Ok(response) => {
            if response.status().is_success() {
                if let Ok(user) = response.json::<serde_json::Value>() {
                    println!("✓ Successfully authenticated as: {}", user["login"]);
                    println!("  Name: {}", user["name"]);
                    println!("  Public repos: {}", user["public_repos"]);
                }
            } else {
                eprintln!("API request failed with status: {}", response.status());
            }
        }
        Err(e) => {
            eprintln!("API request failed: {}", e);
        }
    }
}
