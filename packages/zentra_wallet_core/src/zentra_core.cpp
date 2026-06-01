#include "zentra_core.h"

#include <cctype>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

struct NetworkParams {
  char prefix;
  size_t min_len;
  size_t max_len;
};

NetworkParams params_for(int network) {
  switch (network) {
    case ZENTRA_TESTNET:
      return {'T', 90, 110};
    case ZENTRA_STAGENET:
      return {'S', 90, 110};
    default:
      return {'Z', 90, 110};
  }
}

bool is_base58_char(char c) {
  return (c >= '1' && c <= '9') || (c >= 'A' && c <= 'H') ||
         (c >= 'J' && c <= 'N') || (c >= 'P' && c <= 'Z') ||
         (c >= 'a' && c <= 'k') || (c >= 'm' && c <= 'z');
}

std::string trim(const char* s) {
  std::string str(s);
  while (!str.empty() && isspace(static_cast<unsigned char>(str.front()))) {
    str.erase(str.begin());
  }
  while (!str.empty() && isspace(static_cast<unsigned char>(str.back()))) {
    str.pop_back();
  }
  return str;
}

char* duplicate_c_string(const char* src) {
  if (!src) return nullptr;
  const size_t n = strlen(src) + 1;
  char* out = static_cast<char*>(malloc(n));
  if (out) memcpy(out, src, n);
  return out;
}

}  // namespace

extern "C" {

// Prefix/length/base58 only — not checksum-safe. Use wallet FFI addressValid for sends.
ZENTRA_API int zentra_validate_address(const char* address, int network) {
  if (!address) return 0;
  const auto p = params_for(network);
  const size_t len = strlen(address);
  if (len < p.min_len || len > p.max_len) return 0;
  if (address[0] != p.prefix) return 0;
  for (size_t i = 0; i < len; ++i) {
    if (!is_base58_char(address[i])) return 0;
  }
  return 1;
}

ZENTRA_API char* zentra_atomic_to_display(uint64_t atomic) {
  const uint64_t whole = atomic / ZENTRA_ATOMIC_UNITS;
  char buf[64];
  snprintf(buf, sizeof(buf), "%llu", static_cast<unsigned long long>(whole));
  return duplicate_c_string(buf);
}

ZENTRA_API uint64_t zentra_display_to_atomic(const char* display) {
  if (!display || !*display) return 0;
  std::string s = trim(display);
  if (s.empty()) return 0;
  size_t dot = s.find('.');
  std::string whole_part = dot == std::string::npos ? s : s.substr(0, dot);
  std::string frac_part = dot == std::string::npos ? "" : s.substr(dot + 1);

  if (whole_part.empty() && frac_part.empty()) return 0;

  uint64_t whole = 0;
  for (char c : whole_part) {
    if (!isdigit(static_cast<unsigned char>(c))) return 0;
    whole = whole * 10 + (c - '0');
  }

  while (frac_part.size() < ZENTRA_DISPLAY_DECIMALS) frac_part.push_back('0');
  if (frac_part.size() > ZENTRA_DISPLAY_DECIMALS) return 0;

  uint64_t frac = 0;
  for (char c : frac_part) {
    if (!isdigit(static_cast<unsigned char>(c))) return 0;
    frac = frac * 10 + (c - '0');
  }

  return whole * ZENTRA_ATOMIC_UNITS + frac;
}

ZENTRA_API void zentra_free_string(char* ptr) {
  free(ptr);
}

ZENTRA_API uint16_t zentra_daemon_rpc_port(int network) {
  switch (network) {
    case ZENTRA_TESTNET:
      return 29081;
    case ZENTRA_STAGENET:
      return 39081;
    default:
      return 19081;
  }
}

ZENTRA_API char zentra_address_prefix_char(int network) {
  return params_for(network).prefix;
}

ZENTRA_API const char* zentra_coin_ticker(void) {
  return "ZTRA";
}

}  // extern "C"
