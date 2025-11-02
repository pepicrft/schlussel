#ifndef SCHLUSSEL_H
#define SCHLUSSEL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque pointer to OAuth client
typedef struct SchlusselClient SchlusselClient;

/// Opaque pointer to Token
typedef struct SchlusselToken SchlusselToken;

/// Error codes
typedef enum {
    SCHLUSSEL_OK = 0,
    SCHLUSSEL_INVALID_PARAMETER = 1,
    SCHLUSSEL_STORAGE_ERROR = 2,
    SCHLUSSEL_HTTP_ERROR = 3,
    SCHLUSSEL_AUTHORIZATION_DENIED = 4,
    SCHLUSSEL_TOKEN_EXPIRED = 5,
    SCHLUSSEL_NO_REFRESH_TOKEN = 6,
    SCHLUSSEL_UNKNOWN_ERROR = 99,
} SchlusselError;

/// Create a new OAuth client with GitHub preset
///
/// @param client_id The GitHub OAuth App client ID
/// @param scopes Optional scopes (e.g., "repo user"), or NULL
/// @param app_name Application name for secure storage
/// @return Pointer to client, or NULL on error
SchlusselClient* schlussel_client_new_github(
    const char* client_id,
    const char* scopes,
    const char* app_name
);

/// Authorize using Device Code Flow
///
/// This will display a URL and code to the user, open the browser,
/// and poll for authorization completion.
///
/// @param client The OAuth client
/// @return Pointer to token, or NULL on error
SchlusselToken* schlussel_authorize_device(SchlusselClient* client);

/// Save a token with a key
///
/// @param client The OAuth client
/// @param key The token key (e.g., "github.com:user")
/// @param token The token to save
/// @return Error code
SchlusselError schlussel_save_token(
    SchlusselClient* client,
    const char* key,
    SchlusselToken* token
);

/// Get the access token string
///
/// @param token The token
/// @return Newly allocated string (must be freed with schlussel_string_free), or NULL on error
char* schlussel_token_get_access_token(SchlusselToken* token);

/// Check if token is expired
///
/// @param token The token
/// @return 1 if expired, 0 if not expired
int32_t schlussel_token_is_expired(SchlusselToken* token);

/// Free a string allocated by schlussel
///
/// @param s The string to free
void schlussel_string_free(char* s);

/// Free a token
///
/// @param token The token to free
void schlussel_token_free(SchlusselToken* token);

/// Free a client
///
/// @param client The client to free
void schlussel_client_free(SchlusselClient* client);

#ifdef __cplusplus
}
#endif

#endif // SCHLUSSEL_H
