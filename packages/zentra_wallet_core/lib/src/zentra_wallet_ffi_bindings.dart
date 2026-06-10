import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

class NativeWalletUnavailable implements Exception {
  NativeWalletUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

class ZentraNativeWallet {
  ZentraNativeWallet._(this._lib);
  static ZentraNativeWallet? _instance;
  static String? _loadError;

  /// Last error from [isAvailable] (library missing, dlopen failed, or bad symbols).
  static String? get loadError => _loadError;

  static ZentraNativeWallet get instance {
    if (_instance != null) return _instance!;
    throw NativeWalletUnavailable(
      _loadError ?? 'Wallet engine is not available on this device.',
    );
  }

  static bool get isAvailable {
    try {
      _loadError = null;
      _instance ??= ZentraNativeWallet._(_NativeLib(_openLib()));
      return true;
    } catch (e, st) {
      _loadError = e.toString();
      assert(() {
        // ignore: avoid_print
        print('ZentraNativeWallet load failed: $e\n$st');
        return true;
      }());
      return false;
    }
  }

  /// Tear down native WalletManager (app exit). Re-open via [isAvailable] after this.
  static void release() {
    try {
      _instance?._lib.shutdown();
    } catch (_) {}
    _instance = null;
    _loadError = null;
  }

  static ffi.DynamicLibrary _openLib() {
    if (Platform.isLinux) {
      final fromEnv = Platform.environment['ZENTRA_WALLET_FFI_PATH'];
      if (fromEnv != null && fromEnv.isNotEmpty) {
        return ffi.DynamicLibrary.open(fromEnv);
      }
      final exe = Platform.resolvedExecutable;
      final dir = exe.contains('/')
          ? exe.substring(0, exe.lastIndexOf('/'))
          : exe;
      final candidates = <String>[
        '$dir/lib/libzentra_wallet_ffi.so',
        '$dir/libzentra_wallet_ffi.so',
        'libzentra_wallet_ffi.so',
        'zentra_wallet_ffi.so',
        // `flutter run` from repo (plugin path beside build output)
        '$dir/../packages/zentra_wallet_core/linux/libzentra_wallet_ffi.so',
      ];
      for (final path in candidates) {
        try {
          if (path.contains('/') && !File(path).existsSync()) continue;
          return ffi.DynamicLibrary.open(path);
        } catch (_) {}
      }
    }
    if (Platform.isAndroid) {
      // C++ runtime (required when wallet .so links against shared libc++).
      for (final dep in <String>[
        'libc++_shared.so',
        'libzentra_wallet_core_plugin.so',
      ]) {
        try {
          ffi.DynamicLibrary.open(dep);
        } catch (_) {}
      }
      return ffi.DynamicLibrary.open('libzentra_wallet_ffi.so');
    }
    if (Platform.isWindows) {
      // MinGW runtimes must sit beside the wallet DLL (bundled by build-windows).
      for (final dep in <String>[
        'libwinpthread-1.dll',
        'libgcc_s_seh-1.dll',
        'libstdc++-6.dll',
      ]) {
        try {
          ffi.DynamicLibrary.open(dep);
        } catch (_) {}
      }
      final exe = Platform.resolvedExecutable;
      final dir = exe.contains(r'\')
          ? exe.substring(0, exe.lastIndexOf(r'\'))
          : exe;
      Object? lastErr;
      for (final path in <String>[
        '$dir\\libzentra_wallet_ffi.dll',
        '$dir\\zentra_wallet_ffi.dll',
        'libzentra_wallet_ffi.dll',
      ]) {
        try {
          if (path.contains(r'\') && !File(path).existsSync()) continue;
          return ffi.DynamicLibrary.open(path);
        } catch (e) {
          lastErr = e;
        }
      }
      throw NativeWalletUnavailable(
        lastErr?.toString() ??
            'libzentra_wallet_ffi.dll not found next to $dir',
      );
    }
    if (Platform.isMacOS) {
      final fromEnv = Platform.environment['ZENTRA_WALLET_FFI_PATH'];
      if (fromEnv != null && fromEnv.isNotEmpty) {
        return ffi.DynamicLibrary.open(fromEnv);
      }
      final exe = Platform.resolvedExecutable;
      final dir = exe.contains('/')
          ? exe.substring(0, exe.lastIndexOf('/'))
          : exe;
      Object? lastErr;
      for (final path in <String>[
        '$dir/../Frameworks/libzentra_wallet_ffi.dylib',
        '@executable_path/../Frameworks/libzentra_wallet_ffi.dylib',
        '$dir/libzentra_wallet_ffi.dylib',
        'libzentra_wallet_ffi.dylib',
        // `flutter run` from repo before pod embed
        '$dir/../packages/zentra_wallet_core/macos/lib/libzentra_wallet_ffi.dylib',
        '$dir/../../packages/zentra_wallet_core/macos/lib/libzentra_wallet_ffi.dylib',
      ]) {
        try {
          if (path.contains('/') && !path.startsWith('@') && !File(path).existsSync()) {
            continue;
          }
          return ffi.DynamicLibrary.open(path);
        } catch (e) {
          lastErr = e;
        }
      }
      throw NativeWalletUnavailable(
        lastErr?.toString() ??
            'libzentra_wallet_ffi.dylib not found. Run: ./wallet.sh build-macos',
      );
    }
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    throw NativeWalletUnavailable('Platform ${Platform.operatingSystem}');
  }

  final _NativeLib _lib;

  void init(String walletDir) {
    final dir = walletDir.toNativeUtf8();
    try {
      final ok = _lib.init(dir);
      if (ok != 1) throw NativeWalletUnavailable(_lastError());
    } finally {
      malloc.free(dir);
    }
  }

  void shutdown() => _lib.shutdown();

  void setDaemon(String address, {bool trusted = true}) {
    final a = address.toNativeUtf8();
    try {
      _lib.setDaemon(a, trusted ? 1 : 0);
    } finally {
      malloc.free(a);
    }
  }

  ffi.Pointer<ffi.Void> createWallet(
    String path,
    String password,
    int nettype, {
    int restoreHeight = 0,
  }) =>
      _open(path, password, nettype, isRestore: false, seed: null, restoreHeight: restoreHeight);

  ffi.Pointer<ffi.Void> openWallet(String path, String password, int nettype) {
    final p = path.toNativeUtf8();
    final pw = password.toNativeUtf8();
    try {
      final h = _lib.openWallet(p, pw, nettype);
      if (h == ffi.nullptr) throw NativeWalletUnavailable(_lastError());
      return h;
    } finally {
      malloc.free(p);
      malloc.free(pw);
    }
  }

  ffi.Pointer<ffi.Void> restoreWallet(
    String path,
    String password,
    String seed,
    int nettype, {
    int restoreHeight = 0,
  }) =>
      _open(path, password, nettype, isRestore: true, seed: seed, restoreHeight: restoreHeight);

  ffi.Pointer<ffi.Void> _open(
    String path,
    String password,
    int nettype, {
    required bool isRestore,
    required String? seed,
    required int restoreHeight,
  }) {
    final p = path.toNativeUtf8();
    final pw = password.toNativeUtf8();
    try {
      final ffi.Pointer<ffi.Void> h;
      if (isRestore) {
        final s = (seed ?? '').toNativeUtf8();
        try {
          h = _lib.restoreWallet(p, pw, s, nettype, restoreHeight);
        } finally {
          malloc.free(s);
        }
      } else {
        h = _lib.createWallet(p, pw, nettype, restoreHeight);
      }
      if (h == ffi.nullptr) throw NativeWalletUnavailable(_lastError());
      return h;
    } finally {
      malloc.free(p);
      malloc.free(pw);
    }
  }

  void closeWallet(ffi.Pointer<ffi.Void> handle) => _lib.closeWallet(handle);

  void refresh(ffi.Pointer<ffi.Void> handle) {
    if (_lib.refresh(handle) != 1) throw NativeWalletUnavailable(_lastError());
  }

  bool startBackgroundRefresh(ffi.Pointer<ffi.Void> handle) =>
      _lib.startBgRefresh(handle) == 1;

  void pauseBackgroundRefresh(ffi.Pointer<ffi.Void> handle) {
    _lib.pauseBgRefresh?.call(handle);
  }

  String lastErrorMessage() => _lastError();

  int balance(ffi.Pointer<ffi.Void> handle) => _lib.balance(handle);

  int unlockedBalance(ffi.Pointer<ffi.Void> handle) => _lib.unlockedBalance(handle);

  int walletHeight(ffi.Pointer<ffi.Void> handle) => _lib.walletHeight(handle);

  int daemonHeight(ffi.Pointer<ffi.Void> handle) => _lib.daemonHeight(handle);

  String address(ffi.Pointer<ffi.Void> handle) => _takeString(_lib.address(handle));

  String seed(ffi.Pointer<ffi.Void> handle) => _takeString(_lib.seed(handle));

  int estimateFee(ffi.Pointer<ffi.Void> handle, String to, int amountAtomic, {int priority = 0}) {
    final addr = to.toNativeUtf8();
    try {
      return _lib.estimateFee(handle, addr, amountAtomic, priority);
    } finally {
      malloc.free(addr);
    }
  }

  String send(
    ffi.Pointer<ffi.Void> handle,
    String to,
    int amountAtomic, {
    int priority = 0,
  }) {
    final addr = to.toNativeUtf8();
    try {
      final ptr = _lib.send(handle, addr, amountAtomic, priority);
      if (ptr == ffi.nullptr) throw NativeWalletUnavailable(_lastError());
      return _takeString(ptr);
    } finally {
      malloc.free(addr);
    }
  }

  void store(ffi.Pointer<ffi.Void> handle) {
    if (_lib.store(handle) != 1) throw NativeWalletUnavailable(_lastError());
  }

  int restoreHeight(ffi.Pointer<ffi.Void> handle) => _lib.getRestoreHeight(handle);

  void setRestoreHeight(ffi.Pointer<ffi.Void> handle, int height) {
    if (_lib.setRestoreHeight(handle, height) != 1) {
      throw NativeWalletUnavailable(_lastError());
    }
  }

  bool addressValid(String address, int nettype) {
    final a = address.toNativeUtf8();
    try {
      return _lib.addressValid(a, nettype) == 1;
    } finally {
      malloc.free(a);
    }
  }

  List<Map<String, dynamic>> transfers(ffi.Pointer<ffi.Void> handle) {
    return transfersPage(handle, limit: 0, offset: 0);
  }

  int transferCount(ffi.Pointer<ffi.Void> handle) {
    if (_lib.transfersCount != null) {
      return _lib.transfersCount!(handle);
    }
    return transfers(handle).length;
  }

  List<Map<String, dynamic>> transfersPage(
    ffi.Pointer<ffi.Void> handle, {
    required int limit,
    required int offset,
  }) {
    return transfersPageBundle(
      handle,
      limit: limit,
      offset: offset,
    ).items;
  }

  ({int total, int offset, List<Map<String, dynamic>> items}) transfersPageBundle(
    ffi.Pointer<ffi.Void> handle, {
    required int limit,
    required int offset,
  }) {
    if (_lib.transfersPageBundle != null) {
      final ptr = _lib.transfersPageBundle!(handle, limit, offset);
      if (ptr == ffi.nullptr) throw NativeWalletUnavailable(_lastError());
      final json = _takeString(ptr);
      final decoded = jsonDecode(json);
      if (decoded is! Map) {
        return (total: 0, offset: offset, items: const <Map<String, dynamic>>[]);
      }
      final map = Map<String, dynamic>.from(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
      final total = (map['total'] as num?)?.toInt() ?? 0;
      final pageOffset = (map['offset'] as num?)?.toInt() ?? offset;
      final rawItems = map['items'];
      final items = <Map<String, dynamic>>[
        if (rawItems is List)
          for (final item in rawItems)
            if (item is Map)
              Map<String, dynamic>.from(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ),
      ];
      return (total: total, offset: pageOffset, items: items);
    }

    final total = transferCount(handle);
    final ptr = _lib.transfersJsonPage != null
        ? _lib.transfersJsonPage!(handle, limit, offset)
        : _lib.transfersJson(handle);
    if (ptr == ffi.nullptr) throw NativeWalletUnavailable(_lastError());
    final json = _takeString(ptr);
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      return (total: total, offset: offset, items: const <Map<String, dynamic>>[]);
    }
    var list = [
      for (final item in decoded)
        if (item is Map)
          Map<String, dynamic>.from(
            item.map((k, v) => MapEntry(k.toString(), v)),
          ),
    ];
    if (_lib.transfersJsonPage == null && limit > 0) {
      final start = offset.clamp(0, list.length);
      final end = (start + limit).clamp(0, list.length);
      list = list.sublist(start, end);
    }
    return (total: total, offset: offset, items: list);
  }

  String _lastError() {
    final p = _lib.lastError();
    try {
      return p == ffi.nullptr ? 'Unknown native error' : p.toDartString();
    } finally {
      if (p != ffi.nullptr) _lib.freeString(p);
    }
  }

  String _takeString(ffi.Pointer<Utf8> ptr) {
    if (ptr == ffi.nullptr) return '';
    try {
      return ptr.toDartString();
    } finally {
      _lib.freeString(ptr);
    }
  }
}

class _NativeLib {
  _NativeLib(ffi.DynamicLibrary lib)
      : init = lib.lookupFunction<_InitNative, _Init>('zentra_wm_init'),
        shutdown = lib.lookupFunction<_VoidNative, _Void>('zentra_wm_shutdown'),
        setDaemon = lib.lookupFunction<_SetDaemonNative, _SetDaemon>('zentra_wm_set_daemon'),
        createWallet = lib.lookupFunction<_CreateNative, _Create>('zentra_wm_create_wallet'),
        openWallet = lib.lookupFunction<_OpenNative, _Open>('zentra_wm_open_wallet'),
        restoreWallet = lib.lookupFunction<_RestoreNative, _Restore>('zentra_wm_restore_wallet'),
        closeWallet = lib.lookupFunction<_CloseNative, _Close>('zentra_wm_close_wallet'),
        refresh = lib.lookupFunction<_RefreshNative, _Refresh>('zentra_wm_refresh'),
        startBgRefresh = lib.lookupFunction<_RefreshNative, _Refresh>('zentra_wm_start_background_refresh'),
        pauseBgRefresh = _tryLookupPauseBg(lib),
        balance = lib.lookupFunction<_BalNative, _Bal>('zentra_wm_balance'),
        unlockedBalance = lib.lookupFunction<_BalNative, _Bal>('zentra_wm_unlocked_balance'),
        walletHeight = lib.lookupFunction<_BalNative, _Bal>('zentra_wm_wallet_height'),
        daemonHeight = lib.lookupFunction<_BalNative, _Bal>('zentra_wm_daemon_height'),
        address = lib.lookupFunction<_StrNative, _Str>('zentra_wm_address'),
        seed = lib.lookupFunction<_StrNative, _Str>('zentra_wm_seed'),
        estimateFee = lib.lookupFunction<_EstimateFeeNative, _EstimateFee>('zentra_wm_estimate_fee'),
        send = lib.lookupFunction<_SendWithPriorityNative, _SendWithPriority>('zentra_wm_send'),
        store = lib.lookupFunction<_RefreshNative, _Refresh>('zentra_wm_store'),
        getRestoreHeight = lib.lookupFunction<_BalNative, _Bal>('zentra_wm_get_restore_height'),
        setRestoreHeight = lib.lookupFunction<_SetHeightNative, _SetHeight>('zentra_wm_set_restore_height'),
        lastError = lib.lookupFunction<_LastErrorNative, _LastError>('zentra_wm_last_error'),
        freeString = lib.lookupFunction<_FreeNative, _Free>('zentra_wm_free_string'),
        addressValid = lib.lookupFunction<_AddrValidNative, _AddrValid>('zentra_wm_address_valid'),
        transfersJson = lib.lookupFunction<_StrNative, _Str>('zentra_wm_transfers_json'),
        transfersJsonPage = _tryLookupTransfersPage(lib),
        transfersPageBundle = _tryLookupTransfersPageBundle(lib),
        transfersCount = _tryLookupTransfersCount(lib);

  final _Init init;
  final _Void shutdown;
  final _SetDaemon setDaemon;
  final _Create createWallet;
  final _Open openWallet;
  final _Restore restoreWallet;
  final _Close closeWallet;
  final _Refresh refresh;
  final _Refresh startBgRefresh;
  final _PauseBg? pauseBgRefresh;
  final _Bal balance;
  final _Bal unlockedBalance;
  final _Bal walletHeight;
  final _Bal daemonHeight;
  final _Str address;
  final _Str seed;
  final _EstimateFee estimateFee;
  final _SendWithPriority send;
  final _Refresh store;
  final _Bal getRestoreHeight;
  final _SetHeight setRestoreHeight;
  final _LastError lastError;
  final _Free freeString;
  final _AddrValid addressValid;
  final _Str transfersJson;
  final _TransfersPage? transfersJsonPage;
  final _TransfersPage? transfersPageBundle;
  final _Bal? transfersCount;
}

typedef _InitNative = ffi.Int32 Function(ffi.Pointer<Utf8>);
typedef _Init = int Function(ffi.Pointer<Utf8>);
typedef _VoidNative = ffi.Void Function();
typedef _Void = void Function();
typedef _SetDaemonNative = ffi.Void Function(ffi.Pointer<Utf8>, ffi.Int32);
typedef _SetDaemon = void Function(ffi.Pointer<Utf8>, int);
typedef _OpenNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32);
typedef _Open = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int);
typedef _CreateNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32, ffi.Uint64);
typedef _Create = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int, int);
typedef _RestoreNative = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Int32, ffi.Uint64);
typedef _Restore = ffi.Pointer<ffi.Void> Function(ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, int, int);
typedef _CloseNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _Close = void Function(ffi.Pointer<ffi.Void>);
typedef _RefreshNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _Refresh = int Function(ffi.Pointer<ffi.Void>);
typedef _BalNative = ffi.Uint64 Function(ffi.Pointer<ffi.Void>);
typedef _Bal = int Function(ffi.Pointer<ffi.Void>);
typedef _StrNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>);
typedef _Str = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>);
typedef _LastErrorNative = ffi.Pointer<Utf8> Function();
typedef _LastError = ffi.Pointer<Utf8> Function();
typedef _EstimateFeeNative = ffi.Uint64 Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>, ffi.Uint64, ffi.Int32);
typedef _EstimateFee = int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>, int, int);
typedef _SendWithPriorityNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>, ffi.Uint64, ffi.Int32);
typedef _SendWithPriority = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>, ffi.Pointer<Utf8>, int, int);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _Free = void Function(ffi.Pointer<Utf8>);
typedef _AddrValidNative = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32);
typedef _AddrValid = int Function(ffi.Pointer<Utf8>, int);
typedef _SetHeightNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint64);
typedef _SetHeight = int Function(ffi.Pointer<ffi.Void>, int);
typedef _PauseBgNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _PauseBg = int Function(ffi.Pointer<ffi.Void>);
typedef _TransfersPageNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<ffi.Void>, ffi.Uint32, ffi.Uint32);
typedef _TransfersPage = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>, int, int);

_PauseBg? _tryLookupPauseBg(ffi.DynamicLibrary lib) {
  try {
    return lib.lookupFunction<_PauseBgNative, _PauseBg>(
      'zentra_wm_pause_background_refresh',
    );
  } catch (_) {
    return null;
  }
}

_TransfersPage? _tryLookupTransfersPage(ffi.DynamicLibrary lib) {
  try {
    return lib.lookupFunction<_TransfersPageNative, _TransfersPage>(
      'zentra_wm_transfers_json_page',
    );
  } catch (_) {
    return null;
  }
}

_TransfersPage? _tryLookupTransfersPageBundle(ffi.DynamicLibrary lib) {
  try {
    return lib.lookupFunction<_TransfersPageNative, _TransfersPage>(
      'zentra_wm_transfers_page_bundle',
    );
  } catch (_) {
    return null;
  }
}

_Bal? _tryLookupTransfersCount(ffi.DynamicLibrary lib) {
  try {
    return lib.lookupFunction<_BalNative, _Bal>('zentra_wm_transfers_count');
  } catch (_) {
    return null;
  }
}
