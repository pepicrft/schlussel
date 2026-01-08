//! PKCE (Proof Key for Code Exchange) implementation
//!
//! RFC 7636 compliant implementation for OAuth 2.0 PKCE extension.
//! Generates cryptographically secure code verifiers and challenges.
//!
//! ## Example
//!
//! ```zig
//! const pkce = Pkce.generate();
//! const verifier = pkce.verifier;    // 43-character base64url string
//! const challenge = pkce.challenge;  // SHA256 hash of verifier, base64url encoded
//! ```

const std = @import("std");
const crypto = std.crypto;

/// PKCE code verifier and challenge pair
pub const Pkce = struct {
    /// The code verifier (43 characters, base64url without padding)
    verifier: [43]u8,
    /// The code challenge (43 characters, SHA256 of verifier, base64url without padding)
    challenge: [43]u8,

    /// Generate a new PKCE code verifier and challenge pair
    ///
    /// Uses cryptographically secure random bytes for the verifier,
    /// and SHA256 for the challenge transformation.
    pub fn generate() Pkce {
        var verifier_bytes: [32]u8 = undefined;
        crypto.random.bytes(&verifier_bytes);

        var verifier: [43]u8 = undefined;
        _ = base64UrlEncode(&verifier_bytes, &verifier);

        // Calculate SHA256 of the verifier
        var hash: [32]u8 = undefined;
        crypto.hash.sha2.Sha256.hash(&verifier, &hash, .{});

        var challenge: [43]u8 = undefined;
        _ = base64UrlEncode(&hash, &challenge);

        return .{
            .verifier = verifier,
            .challenge = challenge,
        };
    }

    /// Create PKCE from an existing verifier string
    ///
    /// Useful for testing or when verifier is provided externally.
    pub fn fromVerifier(verifier_str: []const u8) !Pkce {
        if (verifier_str.len != 43) {
            return error.InvalidParameter;
        }

        var verifier: [43]u8 = undefined;
        @memcpy(&verifier, verifier_str);

        // Calculate SHA256 of the verifier
        var hash: [32]u8 = undefined;
        crypto.hash.sha2.Sha256.hash(&verifier, &hash, .{});

        var challenge: [43]u8 = undefined;
        _ = base64UrlEncode(&hash, &challenge);

        return .{
            .verifier = verifier,
            .challenge = challenge,
        };
    }

    /// Get the verifier as a slice
    pub fn getVerifier(self: *const Pkce) []const u8 {
        return &self.verifier;
    }

    /// Get the challenge as a slice
    pub fn getChallenge(self: *const Pkce) []const u8 {
        return &self.challenge;
    }

    /// Get the challenge method (always "S256")
    pub fn getChallengeMethod() []const u8 {
        return "S256";
    }
};

/// Base64 URL-safe alphabet without padding
const base64_url_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/// Encode bytes to base64url without padding
///
/// Returns the number of characters written
fn base64UrlEncode(input: []const u8, output: []u8) usize {
    var out_idx: usize = 0;
    var i: usize = 0;

    while (i + 3 <= input.len) {
        const b0 = input[i];
        const b1 = input[i + 1];
        const b2 = input[i + 2];

        output[out_idx] = base64_url_alphabet[b0 >> 2];
        output[out_idx + 1] = base64_url_alphabet[((b0 & 0x03) << 4) | (b1 >> 4)];
        output[out_idx + 2] = base64_url_alphabet[((b1 & 0x0F) << 2) | (b2 >> 6)];
        output[out_idx + 3] = base64_url_alphabet[b2 & 0x3F];

        i += 3;
        out_idx += 4;
    }

    // Handle remaining bytes (for 32 bytes input, we have 2 remaining)
    const remaining = input.len - i;
    if (remaining == 1) {
        const b0 = input[i];
        output[out_idx] = base64_url_alphabet[b0 >> 2];
        output[out_idx + 1] = base64_url_alphabet[(b0 & 0x03) << 4];
        out_idx += 2;
    } else if (remaining == 2) {
        const b0 = input[i];
        const b1 = input[i + 1];
        output[out_idx] = base64_url_alphabet[b0 >> 2];
        output[out_idx + 1] = base64_url_alphabet[((b0 & 0x03) << 4) | (b1 >> 4)];
        output[out_idx + 2] = base64_url_alphabet[(b1 & 0x0F) << 2];
        out_idx += 3;
    }

    return out_idx;
}

/// Decode base64url to bytes
pub fn base64UrlDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoded_len = (input.len * 3) / 4;
    var output = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(output);

    var out_idx: usize = 0;
    var i: usize = 0;

    while (i + 4 <= input.len) {
        const v0 = decodeChar(input[i]) orelse return error.InvalidParameter;
        const v1 = decodeChar(input[i + 1]) orelse return error.InvalidParameter;
        const v2 = decodeChar(input[i + 2]) orelse return error.InvalidParameter;
        const v3 = decodeChar(input[i + 3]) orelse return error.InvalidParameter;

        output[out_idx] = (v0 << 2) | (v1 >> 4);
        output[out_idx + 1] = (v1 << 4) | (v2 >> 2);
        output[out_idx + 2] = (v2 << 6) | v3;

        i += 4;
        out_idx += 3;
    }

    // Handle remaining characters
    const remaining = input.len - i;
    if (remaining >= 2) {
        const v0 = decodeChar(input[i]) orelse return error.InvalidParameter;
        const v1 = decodeChar(input[i + 1]) orelse return error.InvalidParameter;
        output[out_idx] = (v0 << 2) | (v1 >> 4);
        out_idx += 1;

        if (remaining >= 3) {
            const v2 = decodeChar(input[i + 2]) orelse return error.InvalidParameter;
            output[out_idx] = (v1 << 4) | (v2 >> 2);
            out_idx += 1;
        }
    }

    return output[0..out_idx];
}

fn decodeChar(c: u8) ?u8 {
    if (c >= 'A' and c <= 'Z') return c - 'A';
    if (c >= 'a' and c <= 'z') return c - 'a' + 26;
    if (c >= '0' and c <= '9') return c - '0' + 52;
    if (c == '-') return 62;
    if (c == '_') return 63;
    return null;
}

test "PKCE generation produces correct lengths" {
    const pkce = Pkce.generate();
    try std.testing.expectEqual(@as(usize, 43), pkce.verifier.len);
    try std.testing.expectEqual(@as(usize, 43), pkce.challenge.len);
}

test "PKCE verifier only contains valid base64url characters" {
    const pkce = Pkce.generate();
    for (pkce.verifier) |c| {
        const valid = (c >= 'A' and c <= 'Z') or
            (c >= 'a' and c <= 'z') or
            (c >= '0' and c <= '9') or
            c == '-' or c == '_';
        try std.testing.expect(valid);
    }
}

test "PKCE challenge is SHA256 of verifier" {
    const pkce = Pkce.generate();

    // Manually compute SHA256 of verifier
    var hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(&pkce.verifier, &hash, .{});

    var expected_challenge: [43]u8 = undefined;
    _ = base64UrlEncode(&hash, &expected_challenge);

    try std.testing.expectEqualSlices(u8, &expected_challenge, &pkce.challenge);
}

test "PKCE from verifier produces consistent challenge" {
    // Test with a known verifier
    const pkce1 = Pkce.generate();
    const pkce2 = try Pkce.fromVerifier(&pkce1.verifier);

    try std.testing.expectEqualSlices(u8, &pkce1.verifier, &pkce2.verifier);
    try std.testing.expectEqualSlices(u8, &pkce1.challenge, &pkce2.challenge);
}

test "PKCE challenge method is S256" {
    try std.testing.expectEqualStrings("S256", Pkce.getChallengeMethod());
}

test "base64url encode and decode roundtrip" {
    const allocator = std.testing.allocator;
    const original = "Hello, World!";
    var encoded: [18]u8 = undefined;
    const encoded_len = base64UrlEncode(original, &encoded);

    const decoded = try base64UrlDecode(allocator, encoded[0..encoded_len]);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings(original, decoded);
}
