///! C FFI bindings for cross-language compatibility

use crate::oauth::{AuthFlowResult, OAuthClient, OAuthConfig, TokenRefresher};
use crate::session::MemoryStorage;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Arc;

/// Error codes for C API
#[repr(C)]
pub enum SchlusselError {
    Ok = 0,
    OutOfMemory = 1,
    InvalidArgument = 2,
    NotFound = 3,
    Unknown = 99,
}

/// OAuth configuration for C API
#[repr(C)]
pub struct SchlusselOAuthConfig {
    pub client_id: *const c_char,
    pub authorization_endpoint: *const c_char,
    pub token_endpoint: *const c_char,
    pub redirect_uri: *const c_char,
    pub scope: *const c_char,
}

/// Auth flow result for C API
#[repr(C)]
pub struct SchlusselAuthFlow {
    pub url: *mut c_char,
    pub state: *mut c_char,
}

/// Get library version
#[no_mangle]
pub extern "C" fn schlussel_version() -> *const c_char {
    b"0.1.0\0".as_ptr() as *const c_char
}

/// Create in-memory storage
#[no_mangle]
pub extern "C" fn schlussel_storage_memory_create() -> *mut MemoryStorage {
    Box::into_raw(Box::new(MemoryStorage::new()))
}

/// Destroy storage
#[no_mangle]
pub unsafe extern "C" fn schlussel_storage_destroy(storage: *mut MemoryStorage) {
    if !storage.is_null() {
        drop(Box::from_raw(storage));
    }
}

/// Create OAuth client
#[no_mangle]
pub unsafe extern "C" fn schlussel_oauth_create(
    config: *const SchlusselOAuthConfig,
    storage: *mut MemoryStorage,
) -> *mut OAuthClient<MemoryStorage> {
    if config.is_null() || storage.is_null() {
        return std::ptr::null_mut();
    }

    let config_ref = &*config;

    let client_id = CStr::from_ptr(config_ref.client_id)
        .to_string_lossy()
        .to_string();
    let authorization_endpoint = CStr::from_ptr(config_ref.authorization_endpoint)
        .to_string_lossy()
        .to_string();
    let token_endpoint = CStr::from_ptr(config_ref.token_endpoint)
        .to_string_lossy()
        .to_string();
    let redirect_uri = CStr::from_ptr(config_ref.redirect_uri)
        .to_string_lossy()
        .to_string();

    let scope = if !config_ref.scope.is_null() {
        Some(CStr::from_ptr(config_ref.scope).to_string_lossy().to_string())
    } else {
        None
    };

    let oauth_config = OAuthConfig {
        client_id,
        authorization_endpoint,
        token_endpoint,
        redirect_uri,
        scope,
    };

    let storage_arc = Arc::from_raw(storage as *const MemoryStorage);
    let client = OAuthClient::new(oauth_config, storage_arc.clone());
    // Prevent the Arc from being dropped
    std::mem::forget(storage_arc);

    Box::into_raw(Box::new(client))
}

/// Destroy OAuth client
#[no_mangle]
pub unsafe extern "C" fn schlussel_oauth_destroy(client: *mut OAuthClient<MemoryStorage>) {
    if !client.is_null() {
        drop(Box::from_raw(client));
    }
}

/// Start OAuth flow
#[no_mangle]
pub unsafe extern "C" fn schlussel_oauth_start_flow(
    client: *mut OAuthClient<MemoryStorage>,
    result: *mut SchlusselAuthFlow,
) -> SchlusselError {
    if client.is_null() || result.is_null() {
        return SchlusselError::InvalidArgument;
    }

    let client_ref = &*client;

    match client_ref.start_auth_flow() {
        Ok(flow_result) => {
            let url = CString::new(flow_result.url).unwrap();
            let state = CString::new(flow_result.state).unwrap();

            (*result).url = url.into_raw();
            (*result).state = state.into_raw();

            SchlusselError::Ok
        }
        Err(_) => SchlusselError::Unknown,
    }
}

/// Free auth flow result
#[no_mangle]
pub unsafe extern "C" fn schlussel_auth_flow_free(result: *mut SchlusselAuthFlow) {
    if !result.is_null() {
        let result_ref = &mut *result;

        if !result_ref.url.is_null() {
            drop(CString::from_raw(result_ref.url));
        }

        if !result_ref.state.is_null() {
            drop(CString::from_raw(result_ref.state));
        }
    }
}

/// Create token refresher
#[no_mangle]
pub unsafe extern "C" fn schlussel_token_refresher_create(
    client: *mut OAuthClient<MemoryStorage>,
) -> *mut TokenRefresher<MemoryStorage> {
    if client.is_null() {
        return std::ptr::null_mut();
    }

    let client_arc = Arc::from_raw(client as *const OAuthClient<MemoryStorage>);
    let refresher = TokenRefresher::new(client_arc.clone());
    // Prevent the Arc from being dropped
    std::mem::forget(client_arc);

    Box::into_raw(Box::new(refresher))
}

/// Destroy token refresher
#[no_mangle]
pub unsafe extern "C" fn schlussel_token_refresher_destroy(
    refresher: *mut TokenRefresher<MemoryStorage>,
) {
    if !refresher.is_null() {
        drop(Box::from_raw(refresher));
    }
}

/// Wait for refresh to complete
#[no_mangle]
pub unsafe extern "C" fn schlussel_token_refresher_wait(
    refresher: *mut TokenRefresher<MemoryStorage>,
    key: *const c_char,
) {
    if refresher.is_null() || key.is_null() {
        return;
    }

    let refresher_ref = &*refresher;
    let key_str = CStr::from_ptr(key).to_string_lossy();

    refresher_ref.wait_for_refresh(&key_str);
}
