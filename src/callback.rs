/// Local HTTP server for OAuth callbacks
use crate::error::{OAuthError, Result};
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::time::Duration;

/// Callback result containing authorization code and state
#[derive(Debug, Clone)]
pub struct CallbackResult {
    pub code: String,
    pub state: String,
}

/// Local callback server for OAuth redirect
pub struct CallbackServer {
    listener: TcpListener,
    port: u16,
}

impl CallbackServer {
    /// Create a new callback server on a random available port
    pub fn new() -> Result<Self> {
        let listener = TcpListener::bind("127.0.0.1:0")?;
        let port = listener.local_addr()?.port();

        // Set non-blocking with timeout
        listener.set_nonblocking(false)?;

        Ok(Self { listener, port })
    }

    /// Get the redirect URI for this server
    pub fn redirect_uri(&self) -> String {
        format!("http://127.0.0.1:{}/callback", self.port)
    }

    /// Get the port number
    pub fn port(&self) -> u16 {
        self.port
    }

    /// Wait for OAuth callback (blocking with timeout)
    pub fn wait_for_callback(&self, timeout: Duration) -> Result<CallbackResult> {
        // Set timeout for incoming connections
        let deadline = std::time::Instant::now() + timeout;

        loop {
            // Check if we've exceeded the timeout
            if std::time::Instant::now() > deadline {
                return Err(OAuthError::InvalidResponse(
                    "Timeout waiting for callback".into(),
                ));
            }

            // Set a short timeout for accept to allow checking the deadline
            match self.listener.accept() {
                Ok((stream, _)) => {
                    if let Some(result) = self.handle_request(stream)? {
                        return Ok(result);
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    std::thread::sleep(Duration::from_millis(100));
                    continue;
                }
                Err(e) => return Err(e.into()),
            }
        }
    }

    fn handle_request(&self, stream: TcpStream) -> Result<Option<CallbackResult>> {
        let mut reader = BufReader::new(stream.try_clone()?);
        let mut request_line = String::new();
        reader.read_line(&mut request_line)?;

        // Parse request line: GET /callback?code=...&state=... HTTP/1.1
        let parts: Vec<&str> = request_line.split_whitespace().collect();
        if parts.len() < 2 {
            send_error_response(stream, "Invalid request")?;
            return Ok(None);
        }

        let path = parts[1];
        if !path.starts_with("/callback") {
            send_error_response(stream, "Not found")?;
            return Ok(None);
        }

        // Extract query parameters
        let query = if let Some(pos) = path.find('?') {
            &path[pos + 1..]
        } else {
            send_error_response(stream, "Missing query parameters")?;
            return Ok(None);
        };

        let params = parse_query_params(query);

        // Check for error
        if let Some(error) = params.get("error") {
            let description = params.get("error_description").map(|s| s.as_str());
            send_error_response(stream, &format!("Authorization failed: {}", error))?;
            return Err(OAuthError::OAuthErrorResponse {
                error: error.clone(),
                description: description.map(String::from),
            });
        }

        // Extract code and state
        let code = params
            .get("code")
            .ok_or_else(|| OAuthError::MissingField("code".into()))?;

        let state = params
            .get("state")
            .ok_or_else(|| OAuthError::MissingField("state".into()))?;

        // Send success response
        send_success_response(stream)?;

        Ok(Some(CallbackResult {
            code: code.clone(),
            state: state.clone(),
        }))
    }
}

fn parse_query_params(query: &str) -> std::collections::HashMap<String, String> {
    query
        .split('&')
        .filter_map(|pair| {
            let mut parts = pair.splitn(2, '=');
            let key = parts.next()?;
            let value = parts.next().unwrap_or("");
            Some((
                urlencoding::decode(key).ok()?.into_owned(),
                urlencoding::decode(value).ok()?.into_owned(),
            ))
        })
        .collect()
}

fn send_success_response(mut stream: TcpStream) -> Result<()> {
    let html = r#"<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Authorization Successful</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        .container {
            background: white;
            padding: 3rem;
            border-radius: 1rem;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 400px;
        }
        h1 {
            color: #2d3748;
            margin-bottom: 1rem;
            font-size: 1.875rem;
        }
        p {
            color: #4a5568;
            line-height: 1.6;
            margin-bottom: 1.5rem;
        }
        .checkmark {
            font-size: 4rem;
            color: #48bb78;
            margin-bottom: 1rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="checkmark">✓</div>
        <h1>Authorization Successful!</h1>
        <p>You have successfully authorized the application. You can close this window and return to your terminal.</p>
    </div>
</body>
</html>"#;

    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\n\r\n{}",
        html.len(),
        html
    );

    stream.write_all(response.as_bytes())?;
    stream.flush()?;
    Ok(())
}

fn send_error_response(mut stream: TcpStream, error: &str) -> Result<()> {
    let html = format!(
        r#"<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Authorization Failed</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
        }}
        .container {{
            background: white;
            padding: 3rem;
            border-radius: 1rem;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 400px;
        }}
        h1 {{
            color: #2d3748;
            margin-bottom: 1rem;
            font-size: 1.875rem;
        }}
        p {{
            color: #4a5568;
            line-height: 1.6;
        }}
        .error-icon {{
            font-size: 4rem;
            color: #f56565;
            margin-bottom: 1rem;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="error-icon">✗</div>
        <h1>Authorization Failed</h1>
        <p>{}</p>
    </div>
</body>
</html>"#,
        error
    );

    let response = format!(
        "HTTP/1.1 400 Bad Request\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\n\r\n{}",
        html.len(),
        html
    );

    stream.write_all(response.as_bytes())?;
    stream.flush()?;
    Ok(())
}

mod urlencoding {
    pub fn decode(s: &str) -> Result<std::borrow::Cow<'_, str>, std::str::Utf8Error> {
        let mut result = String::new();
        let mut chars = s.chars().peekable();

        while let Some(ch) = chars.next() {
            match ch {
                '%' => {
                    let hex: String = chars.by_ref().take(2).collect();
                    if let Ok(byte) = u8::from_str_radix(&hex, 16) {
                        result.push(byte as char);
                    } else {
                        result.push('%');
                        result.push_str(&hex);
                    }
                }
                '+' => result.push(' '),
                _ => result.push(ch),
            }
        }

        Ok(std::borrow::Cow::Owned(result))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_callback_server_creation() {
        let server = CallbackServer::new().unwrap();
        assert!(server.port() > 0);
        assert!(server.redirect_uri().contains("http://127.0.0.1:"));
        assert!(server.redirect_uri().contains("/callback"));
    }

    #[test]
    fn test_query_param_parsing() {
        let query = "code=abc123&state=xyz789";
        let params = parse_query_params(query);
        assert_eq!(params.get("code"), Some(&"abc123".to_string()));
        assert_eq!(params.get("state"), Some(&"xyz789".to_string()));
    }

    #[test]
    fn test_query_param_url_decoding() {
        let query = "code=abc%20123&state=xyz%2F789";
        let params = parse_query_params(query);
        assert_eq!(params.get("code"), Some(&"abc 123".to_string()));
        assert_eq!(params.get("state"), Some(&"xyz/789".to_string()));
    }
}
