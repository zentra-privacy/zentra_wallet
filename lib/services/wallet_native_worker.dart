import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:zentra_wallet_core/zentra_wallet_core.dart';

import 'wallet_native_snapshot.dart';

/// Heavy wallet2 FFI on a worker isolate (Cake Wallet pattern).
class WalletNativeWorker {
  static Future<int> openWallet({
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String filename,
    required String password,
    required int nettype,
  }) async {
    return Isolate.run(() => _openWallet(
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
          filename: filename,
          password: password,
          nettype: nettype,
        ));
  }

  static Future<int> createWallet({
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String filename,
    required String password,
    required int nettype,
    required int restoreHeight,
  }) async {
    return Isolate.run(() => _createWallet(
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
          filename: filename,
          password: password,
          nettype: nettype,
          restoreHeight: restoreHeight,
        ));
  }

  static Future<int> restoreWallet({
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String filename,
    required String password,
    required String seed,
    required int nettype,
    required int restoreHeight,
  }) async {
    return Isolate.run(() => _restoreWallet(
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
          filename: filename,
          password: password,
          seed: seed,
          nettype: nettype,
          restoreHeight: restoreHeight,
        ));
  }

  static Future<void> refresh({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    return Isolate.run(() => _refresh(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
        ));
  }

  static Future<WalletNativeSnapshot> snapshot({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    bool includeTransfers = false,
    int transferLimit = 0,
    int transferOffset = 0,
  }) {
    return Isolate.run(() => _snapshot(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
          includeTransfers: includeTransfers,
          transferLimit: transferLimit,
          transferOffset: transferOffset,
        ));
  }

  static Future<void> store({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    return Isolate.run(() => _store(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
        ));
  }

  static Future<void> startBackgroundRefresh({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    return Isolate.run(() => _startBackgroundRefresh(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
        ));
  }

  /// Pause refresh, persist, and close (Cake stopSync / Windows-safe close on isolate).
  static Future<void> closeWallet({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    return Isolate.run(() => _closeWallet(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
        ));
  }

  static Future<void> pauseBackgroundRefresh({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    return Isolate.run(() => _pauseBackgroundRefresh(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
        ));
  }

  static Future<int> estimateFee({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String address,
    required int amountAtomic,
    required int priority,
  }) {
    return Isolate.run(() => _estimateFee(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
          address: address,
          amountAtomic: amountAtomic,
          priority: priority,
        ));
  }

  static Future<String> send({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String address,
    required int amountAtomic,
    required int priority,
  }) {
    return Isolate.run(() => _send(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
          address: address,
          amountAtomic: amountAtomic,
          priority: priority,
        ));
  }

  static Future<void> setRestoreHeight({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required int height,
  }) {
    return Isolate.run(() => _setRestoreHeight(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
          height: height,
        ));
  }

  static Future<String?> fetchSeed({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    return Isolate.run(() => _fetchSeed(
          handleAddress: handleAddress,
          walletDir: walletDir,
          daemonAddress: daemonAddress,
          trustedDaemon: trustedDaemon,
        ));
  }

  static ffi.Pointer<ffi.Void> pointerFromAddress(int address) =>
      ffi.Pointer<ffi.Void>.fromAddress(address);

  static ffi.Pointer<ffi.Void> _ptr(int handleAddress) =>
      ffi.Pointer<ffi.Void>.fromAddress(handleAddress);

  static int _openWallet({
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String filename,
    required String password,
    required int nettype,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    final handle = native.openWallet(filename, password, nettype);
    return handle.address;
  }

  static int _createWallet({
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String filename,
    required String password,
    required int nettype,
    required int restoreHeight,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    final handle = native.createWallet(
      filename,
      password,
      nettype,
      restoreHeight: restoreHeight,
    );
    return handle.address;
  }

  static int _restoreWallet({
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String filename,
    required String password,
    required String seed,
    required int nettype,
    required int restoreHeight,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    final handle = native.restoreWallet(
      filename,
      password,
      seed,
      nettype,
      restoreHeight: restoreHeight,
    );
    return handle.address;
  }

  static void _refresh({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    native.refresh(_ptr(handleAddress));
  }

  static WalletNativeSnapshot _snapshot({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required bool includeTransfers,
    required int transferLimit,
    required int transferOffset,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    final handle = _ptr(handleAddress);
    final bundle = includeTransfers
        ? native.transfersPageBundle(
            handle,
            limit: transferLimit > 0 ? transferLimit : 1 << 20,
            offset: transferOffset,
          )
        : (total: 0, offset: 0, items: const <Map<String, dynamic>>[]);
    final transfers = includeTransfers
        ? bundle.items.map((r) => Map<String, dynamic>.from(r)).toList()
        : const <Map<String, dynamic>>[];
    return WalletNativeSnapshot(
      balanceAtomic: native.balance(handle),
      unlockedAtomic: native.unlockedBalance(handle),
      walletHeight: native.walletHeight(handle),
      daemonHeight: native.daemonHeight(handle),
      address: native.address(handle),
      restoreHeight: native.restoreHeight(handle),
      transfers: transfers,
      transferTotalCount: bundle.total,
      transferOffset: bundle.offset,
    );
  }

  static void _store({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    native.store(_ptr(handleAddress));
  }

  static void _startBackgroundRefresh({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    if (!native.startBackgroundRefresh(_ptr(handleAddress))) {
      throw NativeWalletUnavailable(native.lastErrorMessage());
    }
  }

  static void _closeWallet({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    final handle = _ptr(handleAddress);
    try {
      native.pauseBackgroundRefresh(handle);
    } catch (_) {}
    try {
      native.store(handle);
    } catch (_) {}
    native.closeWallet(handle);
  }

  static void _pauseBackgroundRefresh({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    native.pauseBackgroundRefresh(_ptr(handleAddress));
  }

  static int _estimateFee({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String address,
    required int amountAtomic,
    required int priority,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    return native.estimateFee(
      _ptr(handleAddress),
      address,
      amountAtomic,
      priority: priority,
    );
  }

  static String _send({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required String address,
    required int amountAtomic,
    required int priority,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    return native.send(
      _ptr(handleAddress),
      address,
      amountAtomic,
      priority: priority,
    );
  }

  static void _setRestoreHeight({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
    required int height,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    native.setRestoreHeight(_ptr(handleAddress), height);
  }

  static String? _fetchSeed({
    required int handleAddress,
    required String walletDir,
    required String daemonAddress,
    required bool trustedDaemon,
  }) {
    final native = _loadNative(walletDir, daemonAddress, trustedDaemon);
    return native.seed(_ptr(handleAddress));
  }

  static ZentraNativeWallet _loadNative(
    String walletDir,
    String daemonAddress,
    bool trustedDaemon,
  ) {
    if (!ZentraNativeWallet.isAvailable) {
      throw NativeWalletUnavailable(
        ZentraNativeWallet.loadError ?? 'Wallet engine unavailable',
      );
    }
    final native = ZentraNativeWallet.instance;
    native.init(walletDir);
    native.setDaemon(daemonAddress, trusted: trustedDaemon);
    return native;
  }
}
