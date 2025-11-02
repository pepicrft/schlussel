/// C FFI for Swift/Objective-C interoperability
use crate::oauth::{OAuthClient, OAuthConfig};
use crate::session::{SecureStorage, Token};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::Arc;

/// Opaque pointer to OAuthClient
pub struct SchlusselClient {
    _private: [u8; 0],
}

/// Opaque pointer to Token
pub struct SchlusselToken {
    _private: [u8; 0],
}

/// Error code
#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum SchlusselError {
    Ok = 0,
    InvalidParameter = 1,
    StorageError = 2,
    HttpError = 3,
    AuthorizationDenied = 4,
    TokenExpired = 5,
    NoRefreshToken = 6,
    UnknownError = 99,
}

/// Create a new OAuth client with GitHub preset
///
/// # Safety
///
/// - `client_id` must be a valid null-terminated UTF-8 string
/// - `app_name` must be a valid null-terminated UTF-8 string
/// - `scopes` may be null for no scopes, or a valid null-terminated UTF-8 string
/// - Returns null on error
#[no_mangle]
pub unsafe extern "C" fn schlussel_client_new_github(
    client_id: *const c_char,
    scopes: *const c_char,
    app_name: *const c_char,
) -> *mut SchlusselClient {
    if client_id.is_null() || app_name.is_null() {
        return ptr::null_mut();
    }

    let client_id_str = match CStr::from_ptr(client_id).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let app_name_str = match CStr::from_ptr(app_name).to_str() {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };

    let scopes_opt = if scopes.is_null() {
        None
    } else {
        CStr::from_ptr(scopes).to_str().ok()
    };

    // Create secure storage
    let storage = match SecureStorage::new(app_name_str) {
        Ok(s) => Arc::new(s),
        Err(_) => return ptr::null_mut(),
    };

    // Create config with GitHub preset
    let config = OAuthConfig::github(client_id_str, scopes_opt);

    // Create client
    let client = Arc::new(OAuthClient::new(config, storage));

    Box::into_raw(Box::new(client)) as *mut SchlusselClient
}

/// Authorize using Device Code Flow
///
/// # Safety
///
/// - `client` must be a valid client pointer from `schlussel_client_new_*`
/// - Returns null on error
#[no_mangle]
pub unsafe extern "C" fn schlussel_authorize_device(
    client: *mut SchlusselClient,
) -> *mut SchlusselToken {
    if client.is_null() {
        return ptr::null_mut();
    }

    let client_ref = &*(client as *const Arc<OAuthClient<SecureStorage>>);

    match client_ref.authorize_device() {
        Ok(token) => Box::into_raw(Box::new(token)) as *mut SchlusselToken,
        Err(_) => ptr::null_mut(),
    }
}

/// Save a token with a key
///
/// # Safety
///
/// - `client` must be a valid client pointer
/// - `key` must be a valid null-terminated UTF-8 string
/// - `token` must be a valid token pointer
#[no_mangle]
pub unsafe extern "C" fn schlussel_save_token(
    client: *mut SchlusselClient,
    key: *const c_char,
    token: *mut SchlusselToken,
) -> SchlusselError {
    if client.is_null() || key.is_null() || token.is_null() {
        return SchlusselError::InvalidParameter;
    }

    let client_ref = &*(client as *const Arc<OAuthClient<SecureStorage>>);
    let token_ref = &*(token as *const Token);

    let key_str = match CStr::from_ptr(key).to_str() {
        Ok(s) => s,
        Err(_) => return SchlusselError::InvalidParameter,
    };

    match client_ref.save_token(key_str, token_ref.clone()) {
        Ok(_) => SchlusselError::Ok,
        Err(_) => SchlusselError::StorageError,
    }
}

/// Get the access token from a token object
///
/// # Safety
///
/// - `token` must be a valid token pointer
/// - Returns a newly allocated string that must be freed with `schlussel_string_free`
/// - Returns null on error
#[no_mangle]
pub unsafe extern "C" fn schlussel_token_get_access_token(
    token: *mut SchlusselToken,
) -> *mut c_char {
    if token.is_null() {
        return ptr::null_mut();
    }

    let token_ref = &*(token as *const Token);

    match CString::new(token_ref.access_token.clone()) {
        Ok(s) => s.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Check if a token is expired
///
/// # Safety
///
/// - `token` must be a valid token pointer
/// - Returns 1 if expired, 0 if not expired
#[no_mangle]
pub unsafe extern "C" fn schlussel_token_is_expired(token: *mut SchlusselToken) -> i32 {
    if token.is_null() {
        return 0;
    }

    let token_ref = &*(token as *const Token);
    if token_ref.is_expired() {
        1
    } else {
        0
    }
}

/// Free a string allocated by schlussel
///
/// # Safety
///
/// - `s` must be a string returned by a schlussel function
/// - Must not be called more than once on the same pointer
#[no_mangle]
pub unsafe extern "C" fn schlussel_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Free a token
///
/// # Safety
///
/// - `token` must be a valid token pointer
/// - Must not be called more than once on the same pointer
#[no_mangle]
pub unsafe extern "C" fn schlussel_token_free(token: *mut SchlusselToken) {
    if !token.is_null() {
        drop(Box::from_raw(token as *mut Token));
    }
}

/// Free a client
///
/// # Safety
///
/// - `client` must be a valid client pointer
/// - Must not be called more than once on the same pointer
#[no_mangle]
pub unsafe extern "C" fn schlussel_client_free(client: *mut SchlusselClient) {
    if !client.is_null() {
        drop(Box::from_raw(
            client as *mut Arc<OAuthClient<SecureStorage>>,
        ));
    }
}
