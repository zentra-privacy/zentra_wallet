import 'dart:ffi' as ffi;

import 'package:zentra_wallet_core/zentra_wallet_core.dart';

import '../core/ui_format.dart';
import '../core/native_wallet_messages.dart';
import '../core/network/zentra_network.dart';
import '../core/wallet_exception.dart';
import '../models/wallet_models.dart';
import 'wallet_native_snapshot.dart';
import 'wallet_native_worker.dart';

/// Embedded wallet2 (Cake/Monero-style) — keys and sync on device; remote zentrad only.
class EmbeddedWalletService {
  EmbeddedWalletService({
    required this.network,
    required this.walletDir,
    required this.daemonAddress,
  }) {
    if (!ZentraNativeWallet.isAvailable) {
      throw NativeWalletUnavailable(
        NativeWalletMessages.detail,
      );
    }
    _native = ZentraNativeWallet.instance;
    _native.init(walletDir);
    _native.setDaemon(daemonAddress, trusted: _isLocalDaemon(daemonAddress));
  }

  /// Remote public nodes must not be trusted (Monero wallet2 threat model).
  static bool isTrustedDaemon(String address) => _isLocalDaemon(address);

  static bool _isLocalDaemon(String address) {
    final host = address.split(':').first.trim().toLowerCase();
    return host == '127.0.0.1' || host == 'localhost' || host == '::1';
  }

  final ZentraNetworkConfig network;
  final String walletDir;
  final String daemonAddress;
  late final ZentraNativeWallet _native;
  ffi.Pointer<ffi.Void>? _handle;

  int get nettypeIndex => network.type.index;

  bool get isOpen => _handle != null && _handle != ffi.nullptr;

  bool get _trustedDaemon => isTrustedDaemon(daemonAddress);

  int? get _handleAddress =>
      isOpen ? _handle!.address : null;

  void createWallet({
    required String filename,
    required String password,
    int restoreHeight = 0,
  }) {
    _closeSync();
    _handle = _native.createWallet(
      filename,
      password,
      nettypeIndex,
      restoreHeight: restoreHeight,
    );
  }

  int fetchRestoreHeight() {
    _requireOpen();
    return _native.restoreHeight(_handle!);
  }

  Future<void> setRestoreHeight(int height) async {
    _requireOpen();
    await WalletNativeWorker.setRestoreHeight(
      handleAddress: _handleAddress!,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
      height: height,
    );
  }

  void openWallet({required String filename, required String password}) {
    _closeSync();
    _handle = _native.openWallet(filename, password, nettypeIndex);
  }

  /// Adopts a wallet handle opened on a worker isolate (native heap pointer).
  void adoptHandle(ffi.Pointer<ffi.Void> handle) {
    _closeSync();
    _handle = handle;
  }

  String restoreWallet({
    required String filename,
    required String password,
    required String seed,
    int restoreHeight = 0,
  }) {
    _closeSync();
    _handle = _native.restoreWallet(
      filename,
      password,
      seed,
      nettypeIndex,
      restoreHeight: restoreHeight,
    );
    return _native.address(_handle!);
  }

  /// Starts wallet2 native background sync (non-blocking). Prefer over [refresh] for steady sync.
  Future<void> startBackgroundRefresh() async {
    _requireOpen();
    await WalletNativeWorker.startBackgroundRefresh(
      handleAddress: _handleAddress!,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
    );
  }

  Future<void> pauseBackgroundRefresh() async {
    if (_handle == null || _handle == ffi.nullptr) return;
    await WalletNativeWorker.pauseBackgroundRefresh(
      handleAddress: _handle!.address,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
    );
  }

  Future<void> _closeOnWorker() async {
    if (_handle == null || _handle == ffi.nullptr) return;
    final addr = _handle!.address;
    _handle = null;
    await WalletNativeWorker.closeWallet(
      handleAddress: addr,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
    );
  }

  void _closeSync() {
    if (_handle != null && _handle != ffi.nullptr) {
      try {
        _native.pauseBackgroundRefresh(_handle!);
      } catch (_) {}
      _native.closeWallet(_handle!);
      _handle = null;
    }
  }

  Future<void> refresh() async {
    _requireOpen();
    await WalletNativeWorker.refresh(
      handleAddress: _handleAddress!,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
    );
  }

  Future<WalletNativeSnapshot> fetchSnapshot({bool includeTransfers = true}) async {
    _requireOpen();
    return WalletNativeWorker.snapshot(
      handleAddress: _handleAddress!,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
      includeTransfers: includeTransfers,
    );
  }

  Future<WalletBalance> fetchBalance() async {
    final snap = await fetchSnapshot(includeTransfers: false);
    return WalletBalance(
      balanceAtomic: snap.balanceAtomic,
      unlockedAtomic: snap.unlockedAtomic,
    );
  }

  Future<WalletAddress> fetchPrimaryAddress() async {
    final snap = await fetchSnapshot(includeTransfers: false);
    return WalletAddress(address: snap.address);
  }

  Future<int> fetchWalletHeight() async {
    final snap = await fetchSnapshot(includeTransfers: false);
    return snap.walletHeight;
  }

  Future<int> fetchDaemonHeight() async {
    final snap = await fetchSnapshot(includeTransfers: false);
    return snap.daemonHeight;
  }

  Future<List<WalletTransfer>> fetchTransfers() async {
    final snap = await fetchSnapshot(includeTransfers: true);
    return transfersFromSnapshot(snap);
  }

  Future<String?> fetchSeed() async {
    _requireOpen();
    return WalletNativeWorker.fetchSeed(
      handleAddress: _handleAddress!,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
    );
  }

  bool validateAddress(String address) =>
      _native.addressValid(address.trim(), nettypeIndex);

  String formatAtomic(int atomic) => UiFormat.ztraAmount(atomic);

  int parseDisplay(String display) => ZentraCore.instance.displayToAtomic(display.trim());

  Future<int> estimateFee({
    required String address,
    required String amountDisplay,
    int priority = 0,
  }) async {
    _requireOpen();
    final dest = address.trim();
    if (!validateAddress(dest)) {
      throw WalletException('Invalid address for ${network.label}');
    }
    final atomic = parseDisplay(amountDisplay);
    if (atomic <= 0) throw WalletException('Invalid amount');
    final fee = await WalletNativeWorker.estimateFee(
      handleAddress: _handleAddress!,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
      address: dest,
      amountAtomic: atomic,
      priority: priority,
    );
    if (fee <= 0) {
      throw WalletException(_native.lastErrorMessage());
    }
    return fee;
  }

  /// Sends [amountDisplay] ZTRA. Network fee is extra (see [estimateFee]).
  Future<String> send({
    required String address,
    required String amountDisplay,
    int priority = 0,
  }) async {
    _requireOpen();
    final dest = address.trim();
    if (!validateAddress(dest)) {
      throw WalletException('Invalid address for ${network.label}');
    }
    final atomic = parseDisplay(amountDisplay);
    if (atomic <= 0) throw WalletException('Invalid amount');
    return WalletNativeWorker.send(
      handleAddress: _handleAddress!,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
      address: dest,
      amountAtomic: atomic,
      priority: priority,
    );
  }

  Future<void> store() async {
    _requireOpen();
    await WalletNativeWorker.store(
      handleAddress: _handleAddress!,
      walletDir: walletDir,
      daemonAddress: daemonAddress,
      trustedDaemon: _trustedDaemon,
    );
  }

  /// Cake stopSync: pause, store, close on worker isolate (all platforms, esp. Windows).
  Future<void> closeAndDispose() => _closeOnWorker();

  void dispose() {
    _closeSync();
  }

  static List<WalletTransfer> transfersFromSnapshot(WalletNativeSnapshot snap) {
    return snap.transfers.map(WalletTransfer.fromNative).toList();
  }

  void _requireOpen() {
    if (!isOpen) throw WalletException('No wallet open');
  }
}
