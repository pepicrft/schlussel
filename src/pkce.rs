/// PKCE (Proof Key for Code Exchange) implementation
/// RFC 7636: https://tools.ietf.org/html/rfc7636
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use rand::Rng;
use sha2::{Digest, Sha256};

/// PKCE challenge pair containing code verifier and code challenge
#[derive(Debug, Clone)]
pub struct Pkce {
    code_verifier: String,
    code_challenge: String,
}

impl Pkce {
    /// Generate a new PKCE challenge pair
    ///
    /// Creates a cryptographically secure random code verifier and derives
    /// the code challenge using SHA256.
    ///
    /// # Examples
    ///
    /// ```
    /// use schlussel::pkce::Pkce;
    ///
    /// let pkce = Pkce::generate();
    /// assert_eq!(Pkce::code_challenge_method(), "S256");
    /// ```
    pub fn generate() -> Self {
        // Generate 32 random bytes for code_verifier
        let mut rng = rand::thread_rng();
        let random_bytes: [u8; 32] = rng.gen();

        // Base64 URL encode without padding
        let code_verifier = URL_SAFE_NO_PAD.encode(random_bytes);

        // Create SHA256 hash of code_verifier
        let mut hasher = Sha256::new();
        hasher.update(code_verifier.as_bytes());
        let hash = hasher.finalize();

        // Base64 URL encode the hash for code_challenge
        let code_challenge = URL_SAFE_NO_PAD.encode(hash);

        Self {
            code_verifier,
            code_challenge,
        }
    }

    /// Get the code verifier
    pub fn code_verifier(&self) -> &str {
        &self.code_verifier
    }

    /// Get the code challenge
    pub fn code_challenge(&self) -> &str {
        &self.code_challenge
    }

    /// Get the code challenge method (always S256)
    pub fn code_challenge_method() -> &'static str {
        "S256"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pkce_generation() {
        let pkce = Pkce::generate();

        // Verify lengths (base64 encoded 32 bytes = 43 chars without padding)
        assert_eq!(pkce.code_verifier().len(), 43);
        assert_eq!(pkce.code_challenge().len(), 43);

        // Verify they are different
        assert_ne!(pkce.code_verifier(), pkce.code_challenge());
    }

    #[test]
    fn test_pkce_generates_different_values() {
        let pkce1 = Pkce::generate();
        let pkce2 = Pkce::generate();

        assert_ne!(pkce1.code_verifier(), pkce2.code_verifier());
        assert_ne!(pkce1.code_challenge(), pkce2.code_challenge());
    }

    #[test]
    fn test_code_challenge_method() {
        assert_eq!(Pkce::code_challenge_method(), "S256");
    }
}
