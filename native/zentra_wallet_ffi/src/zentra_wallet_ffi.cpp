#include "zentra_wallet_ffi.h"

#include <wallet/api/wallet2_api.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#ifdef _WIN32
#include <direct.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#endif
#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <cstdlib>
#endif

namespace {

std::mutex g_mutex;
Monero::WalletManager* g_wm = nullptr;
std::string g_wallet_dir;
#if defined(__APPLE__) && TARGET_OS_OSX
std::string g_saved_home;
bool g_home_redirected = false;
#endif
std::string g_daemon_address;
int g_trusted_daemon = 1;
std::string g_last_error;
thread_local std::string g_tl_error;

void set_error(const std::string& msg) {
  g_last_error = msg;
  g_tl_error = msg;
}

Monero::NetworkType to_net(int nettype) {
  switch (nettype) {
    case 1:
      return Monero::TESTNET;
    case 2:
      return Monero::STAGENET;
    default:
      return Monero::MAINNET;
  }
}

Monero::Wallet* as_wallet(ZentraWalletHandle h) {
  return reinterpret_cast<Monero::Wallet*>(h);
}

bool check_wallet(Monero::Wallet* w) {
  if (!w) {
    set_error("Wallet handle is null");
    return false;
  }
  if (w->status() != Monero::Wallet::Status_Ok) {
    set_error(w->errorString());
    return false;
  }
  return true;
}

/// Blocks below daemon tip — wallet2 resets refresh height to 0 if height >= daemon.
constexpr uint64_t kScanHeightMargin = 12;

/// Resolve refresh-from height: never >= daemon tip (avoids full rescan loop on mobile).
uint64_t clamp_refresh_height(Monero::Wallet* w, uint64_t height) {
  const uint64_t daemon_h = w->daemonBlockChainHeight();
  if (daemon_h == 0) return height;
  if (height == 0) return 0;
  if (height >= daemon_h) {
    return daemon_h > kScanHeightMargin ? daemon_h - kScanHeightMargin : 0;
  }
  return height;
}

/// After sync, persist incremental scan start (wallet file) so next open does not rescan from 0.
bool persist_scan_checkpoint(Monero::Wallet* w) {
  if (!check_wallet(w)) return false;
  const uint64_t daemon_h = w->daemonBlockChainHeight();
  const uint64_t wallet_h = w->blockChainHeight();
  if (daemon_h == 0 || wallet_h == 0) return true;

  uint64_t checkpoint = 0;
  if (wallet_h + kScanHeightMargin >= daemon_h) {
    checkpoint = daemon_h > kScanHeightMargin ? daemon_h - kScanHeightMargin : 0;
  } else {
    checkpoint = wallet_h > kScanHeightMargin ? wallet_h - kScanHeightMargin : 0;
  }

  w->setRefreshFromBlockHeight(checkpoint);
  if (!w->store("")) {
    const auto err = w->errorString();
    set_error(err.empty() ? "wallet store failed" : err);
    return false;
  }
  return true;
}

/// wallet2::init — required before refresh/balance/daemon RPC (Monero/Cake flow).
/// refresh_height < 0: keep height already in wallet file (open / restore).
bool bind_wallet_to_daemon(Monero::Wallet* w, bool persist, int64_t refresh_height) {
  if (!check_wallet(w)) return false;
  if (g_daemon_address.empty()) {
    set_error("Daemon address not set");
    return false;
  }
  if (!w->init(g_daemon_address, 0, "", "", false, false, "")) {
    const auto err = w->errorString();
    set_error(err.empty() ? "wallet init failed" : err);
    return false;
  }
  w->setTrustedDaemon(g_trusted_daemon != 0);
  if (refresh_height >= 0) {
    // Height 0 = scan from genesis (wallet2::generate keeps 0; do not estimate).
    const uint64_t h = static_cast<uint64_t>(refresh_height);
    w->setRefreshFromBlockHeight(clamp_refresh_height(w, h));
  }
  if (persist && !w->store("")) {
    const auto err = w->errorString();
    set_error(err.empty() ? "wallet store failed" : err);
    return false;
  }
  return true;
}

char* dup_string(const std::string& s) {
  char* out = static_cast<char*>(std::malloc(s.size() + 1));
  if (!out) return nullptr;
  std::memcpy(out, s.c_str(), s.size() + 1);
  return out;
}

std::string json_escape(const std::string& s) {
  std::string out;
  out.reserve(s.size() + 16);
  for (unsigned char c : s) {
    switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\b':
        out += "\\b";
        break;
      case '\f':
        out += "\\f";
        break;
      case '\n':
        out += "\\n";
        break;
      case '\r':
        out += "\\r";
        break;
      case '\t':
        out += "\\t";
        break;
      default:
        if (c < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out += static_cast<char>(c);
        }
        break;
    }
  }
  return out;
}

void ensure_wallet_dir(const std::string& dir) {
  if (dir.empty()) return;
#ifdef _WIN32
  _mkdir(dir.c_str());
#else
  mkdir(dir.c_str(), 0700);
#endif
}

std::string full_path(const char* name) {
  if (!name || !*name) return {};
  std::string p(name);
  const auto slash = p.find_last_of("/\\");
  if (slash != std::string::npos) {
    p = p.substr(slash + 1);
  }
  if (p.empty() || p == "." || p == "..") return {};
  if (g_wallet_dir.empty()) return p;
#ifdef _WIN32
  return g_wallet_dir + "\\" + p;
#else
  return g_wallet_dir + "/" + p;
#endif
}

}  // namespace

extern "C" {

ZENTRA_WM_API int zentra_wm_init(const char* wallet_dir) {
  std::lock_guard<std::mutex> lock(g_mutex);
  try {
    if (wallet_dir) {
      g_wallet_dir = wallet_dir;
      ensure_wallet_dir(g_wallet_dir);
#if defined(__APPLE__) && TARGET_OS_OSX
      // macOS App Sandbox: container $HOME (Data/) is not writable for LMDB ringdb.
      // Redirect $HOME to the app wallet folder (Application Support/.../zentra_wallets).
      if (!g_home_redirected) {
        if (const char* cur = std::getenv("HOME")) {
          g_saved_home = cur;
        }
        g_home_redirected = true;
      }
      setenv("HOME", g_wallet_dir.c_str(), 1);
      ensure_wallet_dir(g_wallet_dir + "/.shared-ringdb");
#endif
    }
    if (!g_wm) {
      Monero::Utils::onStartup();
      g_wm = Monero::WalletManagerFactory::getWalletManager();
    }
    return g_wm ? 1 : 0;
  } catch (const std::exception& e) {
    set_error(e.what());
    return 0;
  }
}

ZENTRA_WM_API void zentra_wm_shutdown(void) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_wm = nullptr;
#if defined(__APPLE__) && TARGET_OS_OSX
  if (g_home_redirected) {
    if (!g_saved_home.empty()) {
      setenv("HOME", g_saved_home.c_str(), 1);
    } else {
      unsetenv("HOME");
    }
    g_home_redirected = false;
    g_saved_home.clear();
  }
#endif
}

ZENTRA_WM_API void zentra_wm_set_daemon(const char* daemon_address, int trusted_daemon) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!daemon_address) return;
  g_daemon_address = daemon_address;
  g_trusted_daemon = trusted_daemon ? 1 : 0;
  if (g_wm) {
    g_wm->setDaemonAddress(daemon_address);
  }
}

ZENTRA_WM_API ZentraWalletHandle zentra_wm_create_wallet(
    const char* path,
    const char* password,
    int nettype,
    uint64_t restore_height) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_wm) {
    set_error("Wallet manager not initialized");
    return nullptr;
  }
  try {
    const auto full = full_path(path);
    auto* w = g_wm->createWallet(full, password ? password : "", "English", to_net(nettype));
    if (!check_wallet(w)) {
      if (w) g_wm->closeWallet(w, false);
      return nullptr;
    }
    if (!bind_wallet_to_daemon(w, true, static_cast<int64_t>(restore_height))) {
      g_wm->closeWallet(w, false);
      return nullptr;
    }
    return w;
  } catch (const std::exception& e) {
    set_error(e.what());
    return nullptr;
  }
}

ZENTRA_WM_API ZentraWalletHandle zentra_wm_open_wallet(
    const char* path,
    const char* password,
    int nettype) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_wm) {
    set_error("Wallet manager not initialized");
    return nullptr;
  }
  try {
    const auto full = full_path(path);
    auto* w = g_wm->openWallet(full, password ? password : "", to_net(nettype));
    if (!check_wallet(w)) {
      if (w) g_wm->closeWallet(w, false);
      return nullptr;
    }
    if (!bind_wallet_to_daemon(w, false, -1)) {
      g_wm->closeWallet(w, false);
      return nullptr;
    }
    return w;
  } catch (const std::exception& e) {
    set_error(e.what());
    return nullptr;
  }
}

ZENTRA_WM_API ZentraWalletHandle zentra_wm_restore_wallet(
    const char* path,
    const char* password,
    const char* mnemonic,
    int nettype,
    uint64_t restore_height) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_wm) {
    set_error("Wallet manager not initialized");
    return nullptr;
  }
  try {
    const auto full = full_path(path);
    auto* w = g_wm->recoveryWallet(
        full,
        password ? password : "",
        mnemonic ? mnemonic : "",
        to_net(nettype),
        restore_height);
    if (!check_wallet(w)) {
      if (w) g_wm->closeWallet(w, false);
      return nullptr;
    }
    // Pass restore_height so init()'s new-wallet fast-sync does not override explicit 0.
    if (!bind_wallet_to_daemon(w, true, static_cast<int64_t>(restore_height))) {
      g_wm->closeWallet(w, false);
      return nullptr;
    }
    return w;
  } catch (const std::exception& e) {
    set_error(e.what());
    return nullptr;
  }
}

ZENTRA_WM_API uint64_t zentra_wm_get_restore_height(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) return 0;
  return w->getRefreshFromBlockHeight();
}

ZENTRA_WM_API int zentra_wm_set_restore_height(ZentraWalletHandle wallet, uint64_t height) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!check_wallet(w)) return 0;
  try {
    const uint64_t clamped = clamp_refresh_height(w, height);
    w->setRefreshFromBlockHeight(clamped);
    if (!w->store("")) {
      const auto err = w->errorString();
      set_error(err.empty() ? "wallet store failed" : err);
      return 0;
    }
    return 1;
  } catch (const std::exception& e) {
    set_error(e.what());
    return 0;
  }
}

ZENTRA_WM_API void zentra_wm_close_wallet(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_wm || !wallet) return;
  auto* w = as_wallet(wallet);
  if (w) {
    try {
      w->pauseRefresh();
    } catch (...) {}
    persist_scan_checkpoint(w);
  }
  g_wm->closeWallet(w, true);
}

ZENTRA_WM_API int zentra_wm_refresh(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) return 0;
  try {
    if (!w->refresh()) {
      const auto err = w->errorString();
      set_error(err.empty() ? "refresh failed" : err);
      return 0;
    }
    persist_scan_checkpoint(w);
    return 1;
  } catch (const std::exception& e) {
    set_error(e.what());
    return 0;
  }
}

ZENTRA_WM_API int zentra_wm_start_background_refresh(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) return 0;
  try {
    w->startRefresh();
    return 1;
  } catch (const std::exception& e) {
    set_error(e.what());
    return 0;
  }
}

ZENTRA_WM_API int zentra_wm_pause_background_refresh(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) return 0;
  try {
    w->pauseRefresh();
    return 1;
  } catch (const std::exception& e) {
    set_error(e.what());
    return 0;
  }
}

ZENTRA_WM_API uint64_t zentra_wm_balance(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) return 0;
  return w->balanceAll();
}

ZENTRA_WM_API uint64_t zentra_wm_unlocked_balance(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) return 0;
  return w->unlockedBalanceAll();
}

ZENTRA_WM_API uint64_t zentra_wm_wallet_height(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) return 0;
  return w->blockChainHeight();
}

ZENTRA_WM_API uint64_t zentra_wm_daemon_height(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) return 0;
  return w->daemonBlockChainHeight();
}

ZENTRA_WM_API char* zentra_wm_address(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!check_wallet(w)) return nullptr;
  return dup_string(w->address());
}

ZENTRA_WM_API char* zentra_wm_seed(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!check_wallet(w)) return nullptr;
  return dup_string(w->seed());
}

static Monero::PendingTransaction::Priority to_priority(int priority) {
  if (priority < 0) priority = 0;
  if (priority > 3) priority = 3;
  return static_cast<Monero::PendingTransaction::Priority>(priority);
}

ZENTRA_WM_API uint64_t zentra_wm_estimate_fee(
    ZentraWalletHandle wallet,
    const char* address,
    uint64_t amount_atomic,
    int priority) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w || !address || amount_atomic == 0) {
    set_error("Invalid fee estimate parameters");
    return 0;
  }
  try {
    std::vector<std::pair<std::string, uint64_t>> dests;
    dests.emplace_back(std::string(address), amount_atomic);
    return w->estimateTransactionFee(dests, to_priority(priority));
  } catch (const std::exception& e) {
    set_error(e.what());
    return 0;
  }
}

ZENTRA_WM_API char* zentra_wm_send(
    ZentraWalletHandle wallet,
    const char* address,
    uint64_t amount_atomic,
    int priority) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w || !address) {
    set_error("Invalid send parameters");
    return nullptr;
  }
  try {
    // mixin 0 = wallet default ring size (avoids "ring size 17 too high" warnings).
    auto* tx = w->createTransaction(
        address,
        "",
        amount_atomic,
        0,
        to_priority(priority));
    if (!tx || tx->status() != Monero::PendingTransaction::Status_Ok) {
      set_error(tx ? tx->errorString() : "createTransaction failed");
      if (tx) w->disposeTransaction(tx);
      return nullptr;
    }
    // txid() must be read BEFORE commit() — commit clears m_pending_tx.
    const auto ids = tx->txid();
    if (ids.empty()) {
      set_error("No txid from pending transaction");
      w->disposeTransaction(tx);
      return nullptr;
    }
    const std::string txid = ids.front();
    if (!tx->commit()) {
      set_error(tx->errorString());
      w->disposeTransaction(tx);
      return nullptr;
    }
    w->disposeTransaction(tx);
    return dup_string(txid);
  } catch (const std::exception& e) {
    set_error(e.what());
    return nullptr;
  }
}

ZENTRA_WM_API int zentra_wm_store(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!check_wallet(w)) return 0;
  try {
    if (!w->store("")) {
      const auto err = w->errorString();
      set_error(err.empty() ? "wallet store failed" : err);
      return 0;
    }
    return 1;
  } catch (const std::exception& e) {
    set_error(e.what());
    return 0;
  }
}

ZENTRA_WM_API char* zentra_wm_last_error(void) {
  return dup_string(g_last_error);
}

ZENTRA_WM_API void zentra_wm_free_string(char* ptr) {
  std::free(ptr);
}

ZENTRA_WM_API int zentra_wm_address_valid(const char* address, int nettype) {
  if (!address) return 0;
  return Monero::Wallet::addressValid(address, to_net(nettype)) ? 1 : 0;
}


static std::vector<Monero::TransactionInfo*> sorted_transfers(
    Monero::TransactionHistory* hist) {
  std::vector<Monero::TransactionInfo*> items;
  if (!hist) return items;
  const auto all = hist->getAll();
  items.reserve(all.size());
  for (auto* ti : all) {
    if (ti) items.push_back(ti);
  }
  std::sort(items.begin(), items.end(),
            [](const Monero::TransactionInfo* a, const Monero::TransactionInfo* b) {
              if (a->timestamp() != b->timestamp()) {
                return a->timestamp() > b->timestamp();
              }
              return a->blockHeight() > b->blockHeight();
            });
  return items;
}

static char* transfers_json_from_items(
    const std::vector<Monero::TransactionInfo*>& items, uint64_t start,
    uint64_t end) {
  std::ostringstream oss;
  oss << "[";
  bool first = true;
  for (uint64_t i = start; i < end; ++i) {
    auto* ti = items[i];
    if (!ti) continue;
    if (!first) oss << ",";
    first = false;
    const bool incoming =
        ti->direction() == Monero::TransactionInfo::Direction_In;
    oss << "{\"txid\":\"" << json_escape(ti->hash()) << "\""
        << ",\"amount\":" << ti->amount()
        << ",\"incoming\":" << (incoming ? "true" : "false")
        << ",\"timestamp\":" << static_cast<uint64_t>(ti->timestamp())
        << ",\"height\":" << ti->blockHeight()
        << ",\"confirmations\":" << ti->confirmations()
        << ",\"payment_id\":\"" << json_escape(ti->paymentId()) << "\""
        << ",\"pending\":" << (ti->isPending() ? "true" : "false")
        << ",\"failed\":" << (ti->isFailed() ? "true" : "false")
        << "}";
  }
  oss << "]";
  return dup_string(oss.str());
}

ZENTRA_WM_API uint64_t zentra_wm_transfers_count(ZentraWalletHandle wallet) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) {
    set_error("Wallet handle is null");
    return 0;
  }
  try {
    return sorted_transfers(w->history()).size();
  } catch (const std::exception& e) {
    set_error(e.what());
    return 0;
  }
}

ZENTRA_WM_API char* zentra_wm_transfers_json_page(ZentraWalletHandle wallet,
                                                  uint32_t limit,
                                                  uint32_t offset) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) {
    set_error("Wallet handle is null");
    return nullptr;
  }
  try {
    const auto items = sorted_transfers(w->history());
    const uint64_t total = items.size();
    const uint64_t start = std::min<uint64_t>(offset, total);
    const uint64_t end =
        limit == 0 ? total : std::min<uint64_t>(start + limit, total);
    return transfers_json_from_items(items, start, end);
  } catch (const std::exception& e) {
    set_error(e.what());
    return nullptr;
  }
}

ZENTRA_WM_API char* zentra_wm_transfers_page_bundle(ZentraWalletHandle wallet,
                                                    uint32_t limit,
                                                    uint32_t offset) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto* w = as_wallet(wallet);
  if (!w) {
    set_error("Wallet handle is null");
    return nullptr;
  }
  try {
    const auto items = sorted_transfers(w->history());
    const uint64_t total = items.size();
    const uint64_t start = std::min<uint64_t>(offset, total);
    const uint64_t end =
        limit == 0 ? total : std::min<uint64_t>(start + limit, total);
    std::ostringstream oss;
    oss << "{\"total\":" << total << ",\"offset\":" << start << ",\"items\":";
    char* page = transfers_json_from_items(items, start, end);
    if (page == nullptr) return nullptr;
    oss << page;
    std::free(page);
    oss << "}";
    return dup_string(oss.str());
  } catch (const std::exception& e) {
    set_error(e.what());
    return nullptr;
  }
}

ZENTRA_WM_API char* zentra_wm_transfers_json(ZentraWalletHandle wallet) {
  return zentra_wm_transfers_json_page(wallet, 0, 0);
}

}  // extern "C"
