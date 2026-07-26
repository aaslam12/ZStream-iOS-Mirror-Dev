// net_common.h — shared HTTP utilities for plugin native sources
#pragma once
#include <string>
#include <vector>

#include <os/log.h>
// os_log_debug is not persisted to the on-device log store unless someone is
// actively streaming logs live -- useless for after-the-fact diagnosis on a
// release build. os_log_error always persists, so resolver diagnostics use
// it here despite the semantic mismatch (these aren't all "errors").
#define ZS_LOG(tag, ...) os_log_error(os_log_create("com.z-stream.app", tag), __VA_ARGS__)

struct HttpResp {
    int         code;
    std::string body;
    std::string final_url;
    std::string headers;
};

// Raw HTTPS request — handles chunked TE and redirects, no cert pinning.
HttpResp zs_https_req(
    const std::string& full_url,
    const std::string& method,
    const std::string& req_body,
    const std::vector<std::pair<std::string,std::string>>& headers,
    const std::string& cookies,
    int redirect_limit = 4);

// Convenience wrappers
HttpResp zs_get(
    const std::string& url,
    const std::vector<std::pair<std::string,std::string>>& headers,
    const std::string& cookies = "");

HttpResp zs_post(
    const std::string& url,
    const std::string& body,
    const std::vector<std::pair<std::string,std::string>>& headers,
    const std::string& cookies = "");

// Host/path helpers — used by aphrodite's cookie-aware GET
std::string zs_host_from_url(const std::string& url);
std::string zs_path_from_url(const std::string& url);
std::string zs_decode_chunked(const std::string& raw);

// Decodes a single-byte-XOR-obfuscated string literal. Unused unless a
// build pass has rewritten literals into this form (see
// scripts/obfuscate-strings.py) — a no-op / dead symbol in normal builds.
std::string zs_deob(const unsigned char* bytes, size_t len, unsigned char key);
