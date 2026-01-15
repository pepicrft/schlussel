/**
 * Schlussel - Cross-platform OAuth 2.0 library
 *
 * This header provides C-compatible bindings for the Schlussel OAuth library.
 * It supports PKCE, Device Code Flow, and secure token storage.
 *
 * ## Usage Example
 *
 * ```c
 * #include <schlussel.h>
 *
 * int main() {
 *     // Create GitHub OAuth client
 *     SchlusselClient *client = schlussel_client_new_github(
 *         "your-client-id",
 *         "repo user",
 *         "my-app"
 *     );
 *     if (!client) {
 *         fprintf(stderr, "Failed to create client\n");
 *         return 1;
 *     }
 *
 *     // Perform device code authorization
 *     SchlusselToken *token = schlussel_authorize_device(client);
 *     if (token) {
 *         char *access_token = schlussel_token_get_access_token(token);
 *         printf("Access token: %s\n", access_token);
 *         schlussel_string_free(access_token);
 *         schlussel_token_free(token);
 *     }
 *
 *     schlussel_client_free(client);
 *     return 0;
 * }
 * ```
 */

#ifndef SCHLUSSEL_H
#define SCHLUSSEL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Error codes returned by Schlussel functions
 */
typedef enum {
    SCHLUSSEL_OK = 0,
    SCHLUSSEL_ERROR_INVALID_PARAMETER = 1,
    SCHLUSSEL_ERROR_STORAGE = 2,
    SCHLUSSEL_ERROR_HTTP = 3,
    SCHLUSSEL_ERROR_AUTHORIZATION_DENIED = 4,
    SCHLUSSEL_ERROR_TOKEN_EXPIRED = 5,
    SCHLUSSEL_ERROR_NO_REFRESH_TOKEN = 6,
    SCHLUSSEL_ERROR_INVALID_STATE = 7,
    SCHLUSSEL_ERROR_DEVICE_CODE_EXPIRED = 8,
    SCHLUSSEL_ERROR_JSON = 9,
    SCHLUSSEL_ERROR_IO = 10,
    SCHLUSSEL_ERROR_SERVER = 11,
    SCHLUSSEL_ERROR_CALLBACK_SERVER = 12,
    SCHLUSSEL_ERROR_CONFIGURATION = 13,
    SCHLUSSEL_ERROR_LOCK = 14,
    SCHLUSSEL_ERROR_UNSUPPORTED = 15,
    SCHLUSSEL_ERROR_OUT_OF_MEMORY = 16,
    SCHLUSSEL_ERROR_CONNECTION_FAILED = 17,
    SCHLUSSEL_ERROR_TIMEOUT = 18,
    SCHLUSSEL_ERROR_AUTHORIZATION_PENDING = 19,
    SCHLUSSEL_ERROR_SLOW_DOWN = 20,
    SCHLUSSEL_ERROR_UNKNOWN = 99,
} SchlusselError;

/**
 * Opaque OAuth client handle
 *
 * Created by schlussel_client_new_* functions.
 * Must be freed with schlussel_client_free().
 */
typedef struct SchlusselClient SchlusselClient;

/**
 * Opaque OAuth token handle
 *
 * Created by authorization functions or schlussel_get_token().
 * Must be freed with schlussel_token_free().
 */
typedef struct SchlusselToken SchlusselToken;

/**
 * Opaque dynamic registration client handle
 *
 * Created by schlussel_registration_new().
 * Must be freed with schlussel_registration_free().
 */
typedef struct SchlusselRegistrationClient SchlusselRegistrationClient;

/**
 * Opaque registration response handle
 *
 * Created by schlussel_register_client().
 * Must be freed with schlussel_registration_response_free().
 */
typedef struct SchlusselRegistrationResponse SchlusselRegistrationResponse;

/* ============================================================================
 * Client creation functions
 * ============================================================================ */

/**
 * Create a new OAuth client with GitHub configuration
 *
 * @param client_id     The OAuth client ID (null-terminated)
 * @param scopes        Space-separated scopes (null-terminated, may be NULL)
 * @param app_name      Application name for storage (null-terminated)
 * @return              Client pointer on success, NULL on error
 */
SchlusselClient* schlussel_client_new_github(
    const char* client_id,
    const char* scopes,
    const char* app_name
);

/**
 * Create a new OAuth client with Google configuration
 *
 * @param client_id     The OAuth client ID (null-terminated)
 * @param scopes        Space-separated scopes (null-terminated, may be NULL)
 * @param app_name      Application name for storage (null-terminated)
 * @return              Client pointer on success, NULL on error
 */
SchlusselClient* schlussel_client_new_google(
    const char* client_id,
    const char* scopes,
    const char* app_name
);

/**
 * Create a new OAuth client with custom configuration
 *
 * @param client_id                     The OAuth client ID
 * @param authorization_endpoint        Authorization endpoint URL
 * @param token_endpoint                Token endpoint URL
 * @param redirect_uri                  Redirect URI for callbacks
 * @param scopes                        Space-separated scopes (may be NULL)
 * @param device_authorization_endpoint Device code endpoint (may be NULL)
 * @return                              Client pointer on success, NULL on error
 */
SchlusselClient* schlussel_client_new(
    const char* client_id,
    const char* authorization_endpoint,
    const char* token_endpoint,
    const char* redirect_uri,
    const char* scopes,
    const char* device_authorization_endpoint
);

/**
 * Free an OAuth client
 *
 * @param client    The client to free (may be NULL)
 */
void schlussel_client_free(SchlusselClient* client);

/* ============================================================================
 * Authorization functions
 * ============================================================================ */

/**
 * Perform Device Code Flow authorization
 *
 * This will print the verification URI and user code to stderr, and
 * optionally open a browser. It blocks until the user completes
 * authorization or the device code expires.
 *
 * @param client    The OAuth client
 * @return          Token pointer on success, NULL on error
 */
SchlusselToken* schlussel_authorize_device(SchlusselClient* client);

/**
 * Perform Authorization Code Flow with callback server
 *
 * This starts a local server, opens the browser for authorization,
 * and waits for the callback.
 *
 * @param client    The OAuth client
 * @return          Token pointer on success, NULL on error
 */
SchlusselToken* schlussel_authorize(SchlusselClient* client);

/* ============================================================================
 * Token storage operations
 * ============================================================================ */

/**
 * Save a token to storage
 *
 * @param client    The OAuth client
 * @param key       Storage key (null-terminated)
 * @param token     The token to save
 * @return          SCHLUSSEL_OK on success, error code on failure
 */
SchlusselError schlussel_save_token(
    SchlusselClient* client,
    const char* key,
    SchlusselToken* token
);

/**
 * Get a token from storage
 *
 * @param client    The OAuth client
 * @param key       Storage key (null-terminated)
 * @return          Token pointer on success, NULL if not found or on error
 */
SchlusselToken* schlussel_get_token(
    SchlusselClient* client,
    const char* key
);

/**
 * Delete a token from storage
 *
 * @param client    The OAuth client
 * @param key       Storage key (null-terminated)
 * @return          SCHLUSSEL_OK on success, error code on failure
 */
SchlusselError schlussel_delete_token(
    SchlusselClient* client,
    const char* key
);

/**
 * Refresh an access token using a refresh token
 *
 * @param client            The OAuth client
 * @param refresh_token     The refresh token string (null-terminated)
 * @return                  New token pointer on success, NULL on error
 */
SchlusselToken* schlussel_refresh_token(
    SchlusselClient* client,
    const char* refresh_token
);

/* ============================================================================
 * Token accessors
 * ============================================================================ */

/**
 * Get the access token string
 *
 * @param token     The token
 * @return          Newly allocated string, or NULL on error
 *                  Must be freed with schlussel_string_free()
 */
char* schlussel_token_get_access_token(SchlusselToken* token);

/**
 * Get the refresh token string
 *
 * @param token     The token
 * @return          Newly allocated string, or NULL if not present
 *                  Must be freed with schlussel_string_free()
 */
char* schlussel_token_get_refresh_token(SchlusselToken* token);

/**
 * Get the token type string (usually "Bearer")
 *
 * @param token     The token
 * @return          Newly allocated string, or NULL on error
 *                  Must be freed with schlussel_string_free()
 */
char* schlussel_token_get_token_type(SchlusselToken* token);

/**
 * Get the scope string
 *
 * @param token     The token
 * @return          Newly allocated string, or NULL if not present
 *                  Must be freed with schlussel_string_free()
 */
char* schlussel_token_get_scope(SchlusselToken* token);

/**
 * Check if the token is expired
 *
 * @param token     The token
 * @return          1 if expired, 0 if not expired, -1 on error
 */
int schlussel_token_is_expired(SchlusselToken* token);

/**
 * Get the token expiration timestamp
 *
 * @param token     The token
 * @return          Unix timestamp (seconds), or 0 if not set
 */
uint64_t schlussel_token_get_expires_at(SchlusselToken* token);

/**
 * Free a token
 *
 * @param token     The token to free (may be NULL)
 */
void schlussel_token_free(SchlusselToken* token);

/* ============================================================================
 * String operations
 * ============================================================================ */

/**
 * Free a string returned by Schlussel functions
 *
 * @param str       The string to free (may be NULL)
 */
void schlussel_string_free(char* str);

/**
 * Get the last error code for the calling thread
 *
 * @return          Error code for the most recent failure (0 if none)
 */
int schlussel_last_error_code(void);

/**
 * Get the last error message for the calling thread
 *
 * @return          Newly allocated string, or NULL if no error
 *                  Must be freed with schlussel_string_free()
 */
char* schlussel_last_error_message(void);

/**
 * Clear the last error for the calling thread
 */
void schlussel_clear_last_error(void);

/* ============================================================================
 * Formula script functions
 * ============================================================================ */

/**
 * Emit a JSON script from a formula JSON document.
 *
 * @param formula_json  Formula JSON (null-terminated)
 * @return              Newly allocated string on success, NULL on error
 *                      Must be freed with schlussel_string_free()
 */
char* schlussel_script_from_formula_json(const char* formula_json);

/**
 * Emit a resolved JSON script from a formula JSON document.
 *
 * @param formula_json  Formula JSON (null-terminated)
 * @param method        Authentication method (e.g. "authorization_code")
 * @param client_id     OAuth client ID override (may be NULL)
 * @param client_secret OAuth client secret override (may be NULL)
 * @param scope         OAuth scopes (may be NULL)
 * @param redirect_uri  Redirect URI (may be NULL, defaults to auto-assigned)
 * @return              Newly allocated string on success, NULL on error
 *                      Must be freed with schlussel_string_free()
 */
char* schlussel_script_resolve_from_formula_json(
    const char* formula_json,
    const char* method,
    const char* client_id,
    const char* client_secret,
    const char* scope,
    const char* redirect_uri
);

/**
 * Execute a resolved script using an existing client.
 *
 * @param client        OAuth client handle
 * @param script_json   Resolved script JSON (null-terminated)
 * @return              Token handle on success, NULL on error
 */
SchlusselToken* schlussel_run_script(SchlusselClient* client, const char* script_json);

/* ============================================================================
 * Dynamic Client Registration functions
 * ============================================================================ */

/**
 * Create a new dynamic registration client
 *
 * @param endpoint  Registration endpoint URL (null-terminated)
 * @return          Registration client pointer on success, NULL on error
 */
SchlusselRegistrationClient* schlussel_registration_new(
    const char* endpoint
);

/**
 * Free a registration client
 *
 * @param client    The registration client to free (may be NULL)
 */
void schlussel_registration_free(SchlusselRegistrationClient* client);

/**
 * Register a new OAuth client with the authorization server
 *
 * @param reg_client                  The registration client
 * @param redirect_uris               Array of redirect URI strings
 * @param redirect_uris_count         Number of redirect URIs
 * @param client_name                 Human-readable client name (may be NULL)
 * @param grant_types                 Comma-separated grant types (may be NULL)
 * @param response_types              Comma-separated response types (may be NULL)
 * @param scope                       OAuth scope (may be NULL)
 * @param token_auth_method           Token endpoint auth method (may be NULL)
 * @return                            Registration response on success, NULL on error
 */
SchlusselRegistrationResponse* schlussel_register_client(
    SchlusselRegistrationClient* reg_client,
    const char** redirect_uris,
    size_t redirect_uris_count,
    const char* client_name,
    const char* grant_types,
    const char* response_types,
    const char* scope,
    const char* token_auth_method
);

/**
 * Read client configuration from the registration endpoint
 *
 * @param reg_client                  The registration client
 * @param registration_access_token   Registration access token
 * @return                            Registration response on success, NULL on error
 */
SchlusselRegistrationResponse* schlussel_registration_read(
    SchlusselRegistrationClient* reg_client,
    const char* registration_access_token
);

/**
 * Update client configuration at the authorization server
 *
 * @param reg_client                  The registration client
 * @param registration_access_token   Registration access token
 * @param redirect_uris               Array of redirect URI strings
 * @param redirect_uris_count         Number of redirect URIs
 * @param client_name                 Human-readable client name (may be NULL)
 * @param grant_types                 Comma-separated grant types (may be NULL)
 * @param response_types              Comma-separated response types (may be NULL)
 * @param scope                       OAuth scope (may be NULL)
 * @param token_auth_method           Token endpoint auth method (may be NULL)
 * @return                            Registration response on success, NULL on error
 */
SchlusselRegistrationResponse* schlussel_registration_update(
    SchlusselRegistrationClient* reg_client,
    const char* registration_access_token,
    const char** redirect_uris,
    size_t redirect_uris_count,
    const char* client_name,
    const char* grant_types,
    const char* response_types,
    const char* scope,
    const char* token_auth_method
);

/**
 * Delete client registration
 *
 * @param reg_client                  The registration client
 * @param registration_access_token   Registration access token
 * @return                            SCHLUSSEL_OK on success, error code on failure
 */
int schlussel_registration_delete(
    SchlusselRegistrationClient* reg_client,
    const char* registration_access_token
);

/**
 * Free a registration response
 *
 * @param response  The registration response to free (may be NULL)
 */
void schlussel_registration_response_free(SchlusselRegistrationResponse* response);

/**
 * Get the client ID from a registration response
 *
 * @param response  The registration response
 * @return          Newly allocated string, or NULL on error
 *                  Must be freed with schlussel_string_free()
 */
char* schlussel_registration_response_get_client_id(
    SchlusselRegistrationResponse* response
);

/**
 * Get the client secret from a registration response
 *
 * @param response  The registration response
 * @return          Newly allocated string, or NULL if not present
 *                  Must be freed with schlussel_string_free()
 */
char* schlussel_registration_response_get_client_secret(
    SchlusselRegistrationResponse* response
);

/**
 * Get the client ID issued at timestamp
 *
 * @param response  The registration response
 * @return          Unix timestamp (seconds), or 0 if not set
 */
int64_t schlussel_registration_response_get_client_id_issued_at(
    SchlusselRegistrationResponse* response
);

/**
 * Get the client secret expires at timestamp
 *
 * @param response  The registration response
 * @return          Unix timestamp (seconds), or 0 if never expires
 */
int64_t schlussel_registration_response_get_client_secret_expires_at(
    SchlusselRegistrationResponse* response
);

/**
 * Get the registration access token
 *
 * @param response  The registration response
 * @return          Newly allocated string, or NULL if not present
 *                  Must be freed with schlussel_string_free()
 */
char* schlussel_registration_response_get_registration_access_token(
    SchlusselRegistrationResponse* response
);

/**
 * Get the registration client URI
 *
 * @param response  The registration response
 * @return          Newly allocated string, or NULL if not present
 *                  Must be freed with schlussel_string_free()
 */
char* schlussel_registration_response_get_registration_client_uri(
    SchlusselRegistrationResponse* response
);

#ifdef __cplusplus
}
#endif

#endif /* SCHLUSSEL_H */
