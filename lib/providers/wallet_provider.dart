import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:zentra_wallet_core/zentra_wallet_core.dart';

import '../core/transfer_list_merge.dart';
import '../core/transfer_pagination.dart';
import '../core/ui_format.dart';
import '../core/native_wallet_messages.dart';
import '../core/wallet_sync_progress.dart';
import '../core/network/zentra_network.dart';
import '../core/network/zentra_public_nodes.dart';
import '../core/restore_height_utils.dart';
import '../core/seed_utils.dart';
import '../core/wallet_directory.dart';
import '../core/wallet_exception.dart';
import '../models/local_wallet_info.dart';
import '../models/wallet_backup_info.dart';
import '../models/wallet_models.dart';
import '../models/wallet_sync_status.dart';
import '../services/embedded_wallet_service.dart';
import '../services/settings_store.dart';
import '../services/wallet_auto_store.dart';
import '../services/wallet_blockchain_jobs.dart';
import '../services/wallet_connection_watchdog.dart';
import '../services/wallet_native_snapshot.dart';
import '../services/wallet_native_worker.dart';
import '../services/wallet_sync_coordinator.dart';

enum WalletConnectionState { disconnected, connecting, connected, error }

class WalletProvider extends ChangeNotifier {
  WalletProvider({SettingsStore? settings})
      : _settings = settings ?? SettingsStore();

  final SettingsStore _settings;
  final WalletBlockchainJobRunner _blockchainJobs = WalletBlockchainJobRunner();
  final WalletBackgroundSync _backgroundSync = WalletBackgroundSync();
  final WalletAutoStore _autoStore = WalletAutoStore();
  final WalletSyncCoordinator _syncCoordinator = WalletSyncCoordinator();
  final WalletConnectionWatchdog _connectionWatchdog = WalletConnectionWatchdog();
  Future<void> _storeTail = Future<void>.value();
  bool _pollInFlight = false;
  bool _isUpdatingTransfers = false;
  bool _connectionUnhealthy = false;
  int _zeroDaemonPolls = 0;
  int _pollCount = 0;
  int _lastSnapshotWalletHeight = -1;
  int _lastSnapshotBalance = -1;
  int _lastHeadTransferFingerprint = 0;
  WalletSyncProgress? _lastSyncProgress;

  WalletConnectionState connectionState = WalletConnectionState.disconnected;
  WalletSyncStatus syncStatus = WalletSyncStatus.disconnected;
  String? errorMessage;
  bool nativeAvailable = ZentraNativeWallet.isAvailable;

  ZentraNetType networkType = ZentraNetType.mainnet;
  ZentraNetworkConfig? networkConfig;
  NodeConnectionSettings? nodeSettings;
  EmbeddedWalletService? _wallet;
  String? _walletDir;
  int _connectGeneration = 0;
  bool _isSwitchingWallet = false;

  WalletBalance? balance;
  WalletAddress? primaryAddress;
  List<WalletTransfer> transfers = [];
  int transferTotalCount = 0;
  bool isLoadingMoreTransfers = false;
  int walletHeight = 0;
  int daemonBlockHeight = 0;
  String? daemonStatus;
  bool isRefreshing = false;

  /// Native wallet2 sync thread is running; UI updates via periodic snapshot polls.
  bool get isBackgroundSyncing => _backgroundSync.isActive;

  String? walletFilename;
  ZentraNetType? walletNetworkType;
  ZentraPublicNode? selectedPublicNode;
  int defaultRestoreHeight = 0;
  /// Last saved scan checkpoint in wallet file (refresh-from-block-height).
  int walletScanHeight = 0;

  Future<void> initialize() async {
    networkType = await _settings.loadNetwork();
    networkConfig = ZentraNetworkConfig.fromType(networkType);
    nodeSettings = await _settings.loadNode();
    walletFilename = await _settings.loadWalletFilename();
    walletNetworkType = await _settings.loadWalletNetwork();
    defaultRestoreHeight = await _settings.loadDefaultRestoreHeight();
    selectedPublicNode = ZentraPublicNode.byId(nodeSettings?.publicNodeId);
    nativeAvailable = ZentraNativeWallet.isAvailable;
    _walletDir = await _resolveWalletDir();
    notifyListeners();
  }

  Future<String> _resolveWalletDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/zentra_wallets');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// Wallet base names saved on this device (`*.keys` in the wallet folder).
  Future<List<String>> listLocalWalletFilenames() async {
    _walletDir ??= await _resolveWalletDir();
    return WalletDirectory.listWalletFilenames(_walletDir!);
  }

  /// MetaMask-style wallet list for Settings (local `*.keys` files).
  Future<List<LocalWalletInfo>> listLocalWallets() async {
    final names = await listLocalWalletFilenames();
    final active = walletFilename?.trim().toLowerCase();
    final addr = primaryAddress?.address;
    final preview = addr != null && addr.length > 16
        ? '${addr.substring(0, 8)}…${addr.substring(addr.length - 6)}'
        : addr;
    final list = <LocalWalletInfo>[];
    for (final name in names) {
      final isActive = active != null &&
          name.toLowerCase() == active &&
          connectionState == WalletConnectionState.connected;
      final net = await _settings.loadWalletNetworkFor(name);
      list.add(LocalWalletInfo(
        filename: name,
        isActive: isActive,
        hasStoredPassword: await _settings.hasWalletPasswordFor(name),
        networkLabel: net != null
            ? ZentraNetworkConfig.fromType(net).label
            : networkConfig?.label,
        addressPreview: isActive ? preview : null,
      ));
    }
    return list;
  }

  /// Switch active wallet (disconnect current, open selected).
  Future<bool> switchToWallet({
    required String filename,
    String? password,
  }) async {
    if (_isSwitchingWallet) {
      errorMessage = 'Wallet switch already in progress';
      notifyListeners();
      return false;
    }
    _isSwitchingWallet = true;
    try {
      return await _switchToWalletImpl(filename: filename, password: password);
    } finally {
      _isSwitchingWallet = false;
    }
  }

  Future<bool> _switchToWalletImpl({
    required String filename,
    String? password,
  }) async {
    if (!isValidWalletFilename(filename)) {
      errorMessage = 'Invalid wallet name';
      notifyListeners();
      return false;
    }
    _walletDir ??= await _resolveWalletDir();
    if (!await WalletDirectory.walletKeysExist(_walletDir!, filename)) {
      errorMessage = 'Wallet file not found';
      notifyListeners();
      return false;
    }

    if (walletFilename?.trim().toLowerCase() == filename.trim().toLowerCase() &&
        connectionState == WalletConnectionState.connected) {
      return true;
    }

    final pwd = password ?? await _settings.loadWalletPasswordFor(filename);
    if (pwd == null || pwd.isEmpty) {
      errorMessage = 'Wallet password required';
      notifyListeners();
      return false;
    }

    final previousFilename = walletFilename;
    final previousNetwork = walletNetworkType;
    final previousNetworkType = networkType;

    final savedNet =
        await _settings.loadWalletNetworkFor(filename) ?? walletNetworkType ?? networkType;
    final networkChanged = savedNet != previousNetworkType;
    if (networkChanged) {
      await _settings.saveNetwork(savedNet);
      networkType = savedNet;
      networkConfig = ZentraNetworkConfig.fromType(savedNet);
      if (savedNet == ZentraNetType.mainnet) {
        final node = ZentraPublicNode.seedPrimary;
        nodeSettings = node.toNodeSettings();
        selectedPublicNode = node;
      } else {
        final cfg = networkConfig!;
        nodeSettings = NodeConnectionSettings(
          daemonAddress: '127.0.0.1:${cfg.daemonRpcPort}',
        );
        selectedPublicNode = null;
      }
      await _settings.saveNode(nodeSettings!);
    }

    await _teardownActiveWallet();

    walletFilename = filename;
    walletNetworkType = savedNet;

    final ok = await connect(passwordOverride: pwd, waitForInitialSync: false);
    if (ok) {
      await _persistWalletSession(filename, pwd);
      errorMessage = null;
    } else {
      await _restoreWalletSessionAfterFailedSwitch(
        previousFilename: previousFilename,
        previousNetwork: previousNetwork,
        previousNetworkType: previousNetworkType,
        networkWasChanged: networkChanged,
      );
    }
    notifyListeners();
    return ok;
  }

  Future<void> _restoreWalletSessionAfterFailedSwitch({
    required String? previousFilename,
    required ZentraNetType? previousNetwork,
    required ZentraNetType previousNetworkType,
    required bool networkWasChanged,
  }) async {
    walletFilename = previousFilename;
    walletNetworkType = previousNetwork;
    if (networkWasChanged) {
      await _settings.saveNetwork(previousNetworkType);
      networkType = previousNetworkType;
      networkConfig = ZentraNetworkConfig.fromType(previousNetworkType);
      nodeSettings = await _settings.loadNode();
      selectedPublicNode = ZentraPublicNode.byId(nodeSettings?.publicNodeId);
    }

    if (previousFilename == null || previousFilename.isEmpty) return;
    _walletDir ??= await _resolveWalletDir();
    if (!await WalletDirectory.walletKeysExist(_walletDir!, previousFilename)) return;

    final prevPwd = await _settings.loadWalletPasswordFor(previousFilename);
    if (prevPwd == null || prevPwd.isEmpty) return;

    walletFilename = previousFilename;
    walletNetworkType = previousNetwork ?? previousNetworkType;
    await connect(passwordOverride: prevPwd, waitForInitialSync: false);
  }

  /// Returns [desired] or the next free name (`my_wallet` → `my_wallet1`, …).
  Future<String> resolveAvailableWalletFilename(String desired) async {
    final existing = await listLocalWalletFilenames();
    return WalletDirectory.uniqueWalletFilename(desired, existing);
  }

  Future<String> _resolveAvailableFilename(String desired) =>
      resolveAvailableWalletFilename(desired);

  Future<void> _ensureWallet() async {
    if (_wallet != null) return;
    if (networkConfig == null || nodeSettings == null) await initialize();
    _walletDir ??= await _resolveWalletDir();
    _wallet = EmbeddedWalletService(
      network: networkConfig!,
      walletDir: _walletDir!,
      daemonAddress: nodeSettings!.daemonAddress,
    );
  }

  void _refreshNativeFlag() => nativeAvailable = ZentraNativeWallet.isAvailable;

  static String _userMessage(Object e) {
    final s = e.toString();
    if (e is NativeWalletUnavailable || e is WalletException) {
      return s;
    }
    return s.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  bool get hasMoreTransfers => transfers.length < transferTotalCount;

  Future<void> _applyWalletSnapshot({
    bool includeTransfers = true,
    int transferLimit = kTransferInitialLoad,
    int transferOffset = 0,
    bool replaceAllTransfers = true,
  }) async {
    final snap = await _wallet!.fetchSnapshot(
      includeTransfers: includeTransfers,
      transferLimit: transferLimit,
      transferOffset: transferOffset,
    );
    await _applyNativeSnapshot(
      snap,
      includeTransfers: includeTransfers,
      replaceAllTransfers: replaceAllTransfers,
    );
  }

  /// Wallet-file cache (no daemon refresh) — balance/address first; transfers load separately.
  Future<void> _loadCachedWalletSnapshot() async {
    if (_wallet == null || !_wallet!.isOpen) return;
    await _blockchainJobs.run(() async {
      final snap = await _wallet!.fetchSnapshot(includeTransfers: false);
      await _applyNativeSnapshot(
        snap,
        includeTransfers: false,
        replaceAllTransfers: false,
      );
      _lastSnapshotWalletHeight = snap.walletHeight;
      _lastSnapshotBalance = snap.balanceAtomic;
    });
  }

  Future<void> _loadTransfersSnapshot(int gen) async {
    if (_wallet == null || !_wallet!.isOpen || gen != _connectGeneration) return;
    try {
      await _blockchainJobs.run(() async {
        if (gen != _connectGeneration || _wallet == null || !_wallet!.isOpen) return;
        final snap = await _wallet!.fetchSnapshot(
          includeTransfers: true,
          transferLimit: kTransferInitialLoad,
        );
        if (gen != _connectGeneration) return;
        final changed = await _applyNativeSnapshot(
          snap,
          includeTransfers: true,
          replaceAllTransfers: true,
        );
        _lastSnapshotWalletHeight = snap.walletHeight;
        _lastSnapshotBalance = snap.balanceAtomic;
        if (changed) notifyListeners();
      });
    } catch (_) {}
  }

  /// Loads the next page of transaction history from wallet2 (History scroll).
  Future<void> loadMoreTransfers() async {
    if (_wallet == null ||
        !_wallet!.isOpen ||
        isLoadingMoreTransfers ||
        !hasMoreTransfers) {
      return;
    }
    isLoadingMoreTransfers = true;
    notifyListeners();
    try {
      await _blockchainJobs.run(() async {
        if (_wallet == null || !_wallet!.isOpen) return;
        final snap = await _wallet!.fetchSnapshot(
          includeTransfers: true,
          transferLimit: kTransferPageSize,
          transferOffset: transfers.length,
        );
        final changed = await _applyNativeSnapshot(
          snap,
          includeTransfers: true,
          replaceAllTransfers: false,
        );
        if (changed) notifyListeners();
      });
    } catch (_) {
    } finally {
      isLoadingMoreTransfers = false;
      notifyListeners();
    }
  }

  /// Ensures recent transfers are loaded (History tab / empty dashboard).
  Future<void> ensureRecentTransfersLoaded() async {
    if (_wallet == null || !_wallet!.isOpen || transfers.isNotEmpty) return;
    if (isLoadingMoreTransfers) return;
    await _blockchainJobs.run(() async {
      if (_wallet == null || !_wallet!.isOpen || transfers.isNotEmpty) return;
      final snap = await _wallet!.fetchSnapshot(
        includeTransfers: true,
        transferLimit: kTransferInitialLoad,
      );
      final changed = await _applyNativeSnapshot(
        snap,
        includeTransfers: true,
        replaceAllTransfers: true,
      );
      if (changed) notifyListeners();
    });
  }

  Future<bool> _applyNativeSnapshot(
    WalletNativeSnapshot snap, {
    required bool includeTransfers,
    required bool replaceAllTransfers,
  }) async {
    var changed = walletHeight != snap.walletHeight ||
        daemonBlockHeight != snap.daemonHeight ||
        balance?.balanceAtomic != snap.balanceAtomic ||
        balance?.unlockedAtomic != snap.unlockedAtomic ||
        walletScanHeight != snap.restoreHeight ||
        primaryAddress?.address != snap.address;
    balance = WalletBalance(
      balanceAtomic: snap.balanceAtomic,
      unlockedAtomic: snap.unlockedAtomic,
    );
    primaryAddress = WalletAddress(address: snap.address);
    walletHeight = snap.walletHeight;
    daemonBlockHeight = snap.daemonHeight;
    daemonStatus = 'Daemon height $daemonBlockHeight';
    walletScanHeight = snap.restoreHeight;
    if (includeTransfers) {
      if (transferTotalCount != snap.transferTotalCount) {
        transferTotalCount = snap.transferTotalCount;
        changed = true;
      }

      final page = EmbeddedWalletService.transfersFromSnapshot(snap);
      if (page.isEmpty && snap.transferOffset == 0 && transfers.isNotEmpty) {
        return changed;
      }

      if (snap.transferOffset == 0) {
        final headFingerprint =
            fingerprintTransferHead(snap.transfers, snap.transferTotalCount);
        final headChanged = headFingerprint != _lastHeadTransferFingerprint;
        if (headChanged ||
            replaceAllTransfers ||
            transfers.isEmpty ||
            _hasPendingTransfers()) {
          transfers = replaceAllTransfers || transfers.isEmpty
              ? page
              : mergeTransferHead(transfers, page);
          _lastHeadTransferFingerprint = headFingerprint;
          changed = true;
        }
      } else {
        final merged = appendTransferPage(transfers, page);
        if (merged.length != transfers.length) {
          transfers = merged;
          changed = true;
        }
      }
    }
    return changed;
  }

  void _clearWalletSnapshot() {
    balance = null;
    primaryAddress = null;
    transfers = [];
    transferTotalCount = 0;
    isLoadingMoreTransfers = false;
    walletHeight = 0;
    daemonBlockHeight = 0;
    daemonStatus = null;
    walletScanHeight = 0;
    _lastHeadTransferFingerprint = 0;
  }

  bool _hasPendingTransfers() => transfers.any((t) => t.pending);

  void _beginWalletOperation() {
    _connectGeneration++;
    _stopBlockchainSync();
    errorMessage = null;
  }

  Future<void> _closeWalletService() async {
    final w = _wallet;
    _wallet = null;
    if (w != null) {
      await w.closeAndDispose();
    }
  }

  void _disposeWalletOnFailure() {
    _stopBlockchainSync();
    unawaited(_closeWalletService());
    connectionState = WalletConnectionState.disconnected;
    syncStatus = WalletSyncStatus.disconnected;
    _clearWalletSnapshot();
  }

  /// Stop sync/polls, drain FFI jobs, then close native wallet (avoids switch crash).
  Future<void> _teardownActiveWallet() async {
    _connectGeneration++;
    // Stop timers first; finish in-flight store + FFI before reset/close.
    _stopBlockchainSync(keepJobQueue: true);
    await _blockchainJobs.awaitIdle();
    try {
      await _storeTail;
    } catch (_) {}
    _blockchainJobs.reset();
    _storeTail = Future<void>.value();
    final w = _wallet;
    if (w != null && w.isOpen) {
      try {
        await w.pauseBackgroundRefresh();
      } catch (_) {}
    }
    await _closeWalletService();
    _clearWalletSnapshot();
    connectionState = WalletConnectionState.disconnected;
  }

  void _stopBlockchainSync({bool keepJobQueue = false}) {
    _backgroundSync.stop();
    _autoStore.stop();
    _connectionWatchdog.stop();
    _syncCoordinator.reset();
    _lastSyncProgress = null;
    if (!keepJobQueue) {
      _blockchainJobs.reset();
      _storeTail = Future<void>.value();
    }
    _pollInFlight = false;
    _isUpdatingTransfers = false;
    _connectionUnhealthy = false;
    _zeroDaemonPolls = 0;
    _pollCount = 0;
    _lastSnapshotWalletHeight = -1;
    _lastSnapshotBalance = -1;
    _lastHeadTransferFingerprint = 0;
    syncStatus = WalletSyncStatus.disconnected;
    unawaited(_setWakelock(false));
  }

  Future<void> _setWakelock(bool enabled) async {
    if (kIsWeb) return;
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  Future<void> _startBlockchainSync() async {
    if (_wallet == null || !_wallet!.isOpen) return;
    syncStatus = WalletSyncStatus.syncing;
    await _setWakelock(true);
    await _wallet!.startBackgroundRefresh();
    _backgroundSync.start(
      onPoll: _pollSnapshotFromBackground,
    );
    _autoStore.start(
      onStore: ({required bool force}) => _persistWalletFile(force: force),
    );
    _connectionWatchdog.start(
      isConnectionFailed: () async => _connectionUnhealthy,
      onReconnect: _reconnectToNode,
    );
  }

  /// Cake check_connection: reconnect daemon after network / node failure.
  Future<void> _reconnectToNode() async {
    if (_wallet == null || !_wallet!.isOpen || walletFilename == null) return;
    final gen = _connectGeneration;
    try {
      await _blockchainJobs.run(() async {
        if (gen != _connectGeneration) return;
        await _wallet!.pauseBackgroundRefresh();
        await _wallet!.refresh();
      });
      if (gen != _connectGeneration) return;
      _connectionUnhealthy = false;
      if (!_backgroundSync.isActive) {
        await _startBlockchainSync();
      }
      errorMessage = null;
      notifyListeners();
    } catch (e) {
      if (gen == _connectGeneration) {
        errorMessage = _userMessage(e);
        notifyListeners();
      }
    }
  }

  /// Daemon refresh after [_loadCachedWalletSnapshot] (updates balance + recent txs).
  Future<void> _runInitialWalletRefresh() async {
    await _blockchainJobs.run(() async {
      await _wallet!.refresh();
      final snap = await _wallet!.fetchSnapshot(
        includeTransfers: true,
        transferLimit: kTransferInitialLoad,
      );
      await _applyNativeSnapshot(
        snap,
        includeTransfers: true,
        replaceAllTransfers: true,
      );
      _lastSnapshotWalletHeight = snap.walletHeight;
      _lastSnapshotBalance = snap.balanceAtomic;
    });
    _updateSyncStatusFromHeights();
  }

  Future<void> _pollSnapshotFromBackground() async {
    if (_wallet == null || !_wallet!.isOpen || _pollInFlight) return;
    final gen = _connectGeneration;
    _pollInFlight = true;
    try {
      await _blockchainJobs.run(() async {
        if (gen != _connectGeneration || _wallet == null || !_wallet!.isOpen) return;
        final wasSynced = isSynced;
        _pollCount++;
        var needTransfers = _pollCount == 1 ||
            walletHeight != _lastSnapshotWalletHeight ||
            balance?.balanceAtomic != _lastSnapshotBalance ||
            _hasPendingTransfers();
        if (!needTransfers) {
          needTransfers = wasSynced ? _pollCount % 25 == 0 : _pollCount % 8 == 0;
        }
        if (needTransfers && _isUpdatingTransfers) {
          needTransfers = false;
        }
        var snap = await _wallet!.fetchSnapshot(
          includeTransfers: needTransfers,
          transferLimit: needTransfers ? kTransferInitialLoad : 0,
        );
        if (snap.daemonHeight <= 0) {
          _zeroDaemonPolls++;
          if (_zeroDaemonPolls >= 10) {
            _connectionUnhealthy = true;
          }
          if (_zeroDaemonPolls == 3 || (_zeroDaemonPolls > 3 && _zeroDaemonPolls % 15 == 0)) {
            await _wallet!.refresh();
            snap = await _wallet!.fetchSnapshot(
              includeTransfers: needTransfers,
              transferLimit: needTransfers ? kTransferInitialLoad : 0,
            );
          }
        } else {
          _zeroDaemonPolls = 0;
          _connectionUnhealthy = false;
        }
        final progress = _syncCoordinator.progressForSnapshot(snap);
        var progressChanged = false;
        if (progress != null) {
          final prev = _lastSyncProgress;
          progressChanged = prev == null ||
              prev.progressFraction != progress.progressFraction ||
              prev.blocksLeft != progress.blocksLeft ||
              prev.walletHeight != progress.walletHeight;
          _lastSyncProgress = progress;
        }
        if (gen != _connectGeneration) return;

        final fetchTxs = needTransfers;
        if (fetchTxs) _isUpdatingTransfers = true;
        try {
          final prevSyncStatus = syncStatus;
          final changed = await _applyNativeSnapshot(
            snap,
            includeTransfers: needTransfers,
            replaceAllTransfers: false,
          );
          _lastSnapshotWalletHeight = snap.walletHeight;
          _lastSnapshotBalance = snap.balanceAtomic;
          _updateSyncStatusFromHeights();
          final syncStateChanged = wasSynced != isSynced || prevSyncStatus != syncStatus;
          if (!wasSynced && isSynced) {
            await _persistWalletFile(force: true);
          } else {
            await _persistWalletFile(force: false);
          }
          if (changed || syncStateChanged || progressChanged) {
            if (daemonBlockHeight > 0) {
              errorMessage = null;
            }
            notifyListeners();
          }
        } finally {
          if (fetchTxs) _isUpdatingTransfers = false;
        }
      });
      if (gen == _connectGeneration && daemonBlockHeight > 0 && errorMessage != null) {
        errorMessage = null;
        notifyListeners();
      }
    } catch (e) {
      if (gen == _connectGeneration) {
        if (daemonBlockHeight <= 0) {
          errorMessage = _userMessage(e);
          notifyListeners();
        }
        assert(() {
          debugPrint('Wallet background poll failed: $e');
          return true;
        }());
      }
    } finally {
      _pollInFlight = false;
    }
  }

  void _updateSyncStatusFromHeights() {
    if (connectionState != WalletConnectionState.connected) return;
    if (isSynced) {
      syncStatus = WalletSyncStatus.synced;
      _connectionUnhealthy = false;
      unawaited(_setWakelock(false));
      WalletSyncProgress.reset();
      _lastSyncProgress = null;
    } else {
      syncStatus = WalletSyncStatus.syncing;
    }
  }

  /// Serializes wallet [store] without the blockchain job queue (avoids deadlock with send).
  Future<void> _persistWalletFile({required bool force}) async {
    if (_wallet == null || !_wallet!.isOpen) return;
    final op = _storeTail.then((_) async {
      if (_wallet == null || !_wallet!.isOpen) return;
      await _autoStore.maybeStore(
        force: force,
        isSynced: isSynced,
        walletHeight: walletHeight,
        store: () async => _wallet!.store(),
      );
    });
    _storeTail = op.catchError((Object e) {
      if (force) {
        assert(() {
          debugPrint('Wallet store failed: $e');
          return true;
        }());
      }
    });
    await op;
  }

  /// Called when [connect] is aborted externally (e.g. splash screen timeout).
  void markConnectFailed(String message) {
    _connectGeneration++;
    _stopBlockchainSync();
    connectionState = WalletConnectionState.error;
    errorMessage = message;
    unawaited(_closeWalletService());
    _clearWalletSnapshot();
    notifyListeners();
  }

  /// Resets session before onboarding create/open/restore (Settings → different wallet).
  void prepareForNewWalletFlow() {
    _resetWalletSession();
    notifyListeners();
  }

  /// True when a newer connect/reset superseded [gen]; cleans up stale native wallet.
  bool _connectStale(int gen) {
    if (gen == _connectGeneration) return false;
    _disposeWalletOnFailure();
    return true;
  }

  Future<bool> connect({
    String? passwordOverride,
    /// When false, opens the wallet and starts background sync without blocking on [refresh].
    /// Use on splash so Home can show while the node syncs (mobile networks are slower).
    bool waitForInitialSync = true,
  }) async {
    final gen = ++_connectGeneration;
    _stopBlockchainSync();
    _refreshNativeFlag();
    if (!nativeAvailable) {
      connectionState = WalletConnectionState.error;
      errorMessage =
          NativeWalletMessages.detail;
      notifyListeners();
      return false;
    }
    if (walletFilename == null || walletFilename!.isEmpty) {
      connectionState = WalletConnectionState.disconnected;
      notifyListeners();
      return false;
    }

    _walletDir ??= await _resolveWalletDir();
    if (!await WalletDirectory.walletKeysExist(_walletDir!, walletFilename!)) {
      await _settings.clearWalletFilename();
      walletFilename = null;
      connectionState = WalletConnectionState.disconnected;
      notifyListeners();
      return false;
    }

    connectionState = WalletConnectionState.connecting;
    syncStatus = WalletSyncStatus.disconnected;
    errorMessage = null;
    notifyListeners();

    if (walletNetworkType != null && walletNetworkType != networkType) {
      connectionState = WalletConnectionState.error;
      errorMessage =
          'Wallet "${walletFilename!}" is for ${ZentraNetworkConfig.fromType(walletNetworkType!).label}. '
          'Switch network in Settings or use another wallet file.';
      notifyListeners();
      return false;
    }

    try {
      await _ensureWallet();
      if (_connectStale(gen)) return false;
      final password = passwordOverride ?? await _settings.loadWalletPassword() ?? '';
      syncStatus = WalletSyncStatus.connecting;
      final trusted = EmbeddedWalletService.isTrustedDaemon(nodeSettings!.daemonAddress);
      final handleAddr = await _blockchainJobs.run(() => WalletNativeWorker.openWallet(
            walletDir: _walletDir!,
            daemonAddress: nodeSettings!.daemonAddress,
            trustedDaemon: trusted,
            filename: walletFilename!,
            password: password,
            nettype: networkConfig!.type.index,
          ));
      if (_connectStale(gen)) return false;
      _wallet!.adoptHandle(WalletNativeWorker.pointerFromAddress(handleAddr));
      await _loadCachedWalletSnapshot();
      if (_connectStale(gen)) return false;
      connectionState = WalletConnectionState.connected;
      notifyListeners();
      if (waitForInitialSync) {
        await _runInitialWalletRefresh();
        if (_connectStale(gen)) return false;
      } else {
        unawaited(_loadTransfersSnapshot(gen));
      }
      await _startBlockchainSync();
      if (!waitForInitialSync) {
        // Background sync + polls only — avoid blocking refresh racing native refresh thread.
        syncStatus = WalletSyncStatus.syncing;
      }
      if (_connectStale(gen)) return false;
      errorMessage = null;
      return true;
    } catch (e) {
      if (_connectStale(gen)) return false;
      _stopBlockchainSync();
      connectionState = WalletConnectionState.error;
      errorMessage = _userMessage(e);
      unawaited(_closeWalletService());
      return false;
    } finally {
      if (gen == _connectGeneration) {
        if (connectionState == WalletConnectionState.connecting) {
          _stopBlockchainSync();
          connectionState = WalletConnectionState.error;
          errorMessage ??= 'Connection interrupted';
          unawaited(_closeWalletService());
        }
        notifyListeners();
      }
    }
  }

  /// Pull-to-refresh / manual update. Uses a light snapshot poll while background sync runs.
  Future<void> refresh({bool forceBlocking = false}) async {
    if (_wallet == null || !_wallet!.isOpen) return;
    isRefreshing = true;
    notifyListeners();
    try {
      if (_backgroundSync.isActive && !forceBlocking) {
        await _pollSnapshotFromBackground();
      } else {
        await _blockchainJobs.run(() async {
          await _wallet!.refresh();
          await _applyWalletSnapshot();
        });
      }
      errorMessage = null;
    } catch (e) {
      errorMessage = _userMessage(e);
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  Future<void> updateDefaultRestoreHeight(int height) async {
    defaultRestoreHeight = height.clamp(0, 0x7FFFFFFF);
    await _settings.saveDefaultRestoreHeight(defaultRestoreHeight);
    notifyListeners();
  }

  /// Applies restore height to the open wallet and saves as default.
  Future<bool> applyRestoreHeightToOpenWallet(int height) async {
    if (_wallet == null || !_wallet!.isOpen) {
      errorMessage = 'Open a wallet first';
      notifyListeners();
      return false;
    }
    _stopBlockchainSync();
    try {
      await updateDefaultRestoreHeight(height);
      await _blockchainJobs.run(() async {
        await _wallet!.setRestoreHeight(height);
        await _wallet!.refresh();
        await _applyWalletSnapshot();
      });
      _updateSyncStatusFromHeights();
      return true;
    } catch (e) {
      errorMessage = _userMessage(e);
      return false;
    } finally {
      if (_wallet != null && _wallet!.isOpen) {
        await _startBlockchainSync();
      }
      notifyListeners();
    }
  }

  Future<bool> createNewWallet({
    required String filename,
    required String password,
    int? restoreHeight,
  }) async {
    _refreshNativeFlag();
    if (!nativeAvailable) {
      errorMessage =
          NativeWalletMessages.detail;
      notifyListeners();
      return false;
    }
    if (!isValidWalletFilename(filename)) {
      errorMessage = 'Wallet name must be a simple filename (no path separators)';
      notifyListeners();
      return false;
    }
    final resolved = await _resolveAvailableFilename(filename);
    await _ensureWallet();
    _beginWalletOperation();
    try {
      final trusted = EmbeddedWalletService.isTrustedDaemon(nodeSettings!.daemonAddress);
      final handleAddr = await WalletNativeWorker.createWallet(
        walletDir: _walletDir!,
        daemonAddress: nodeSettings!.daemonAddress,
        trustedDaemon: trusted,
        filename: resolved,
        password: password,
        nettype: networkConfig!.type.index,
        restoreHeight: restoreHeight ?? 0,
      );
      _wallet!.adoptHandle(WalletNativeWorker.pointerFromAddress(handleAddr));
      if (restoreHeight == null) {
        await _setScanHeightFromDaemonTip();
      }
      final ok = await _syncAfterOpen();
      if (ok) {
        await _persistWalletSession(resolved, password);
        if (restoreHeight != null) await updateDefaultRestoreHeight(restoreHeight);
      }
      return ok;
    } catch (e) {
      _disposeWalletOnFailure();
      connectionState = WalletConnectionState.error;
      errorMessage = _userMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> restoreFromSeed({
    required String filename,
    required String seed,
    required String password,
    int? restoreHeight,
  }) async {
    _refreshNativeFlag();
    if (!nativeAvailable) {
      errorMessage =
          NativeWalletMessages.detail;
      notifyListeners();
      return false;
    }
    final normalized = SeedUtils.normalize(seed);
    if (!SeedUtils.isValidWordCount(normalized)) {
      errorMessage = 'Seed must be 12, 13, 24, or 25 words';
      notifyListeners();
      return false;
    }
    if (!isValidWalletFilename(filename)) {
      errorMessage = 'Wallet name must be a simple filename (no path separators)';
      notifyListeners();
      return false;
    }
    final resolved = await _resolveAvailableFilename(filename);
    await _ensureWallet();
    _beginWalletOperation();
    try {
      final trusted = EmbeddedWalletService.isTrustedDaemon(nodeSettings!.daemonAddress);
      final handleAddr = await WalletNativeWorker.restoreWallet(
        walletDir: _walletDir!,
        daemonAddress: nodeSettings!.daemonAddress,
        trustedDaemon: trusted,
        filename: resolved,
        password: password,
        seed: normalized,
        nettype: networkConfig!.type.index,
        restoreHeight: restoreHeight ?? defaultRestoreHeight,
      );
      _wallet!.adoptHandle(WalletNativeWorker.pointerFromAddress(handleAddr));
      final ok = await _syncAfterOpen();
      if (ok) {
        await _persistWalletSession(resolved, password);
        if (restoreHeight != null) await updateDefaultRestoreHeight(restoreHeight);
      }
      return ok;
    } catch (e) {
      _disposeWalletOnFailure();
      connectionState = WalletConnectionState.error;
      errorMessage = _userMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// New wallets: start scan near daemon tip (fast). Restore still uses user height.
  Future<void> _setScanHeightFromDaemonTip() async {
    if (_wallet == null || !_wallet!.isOpen) return;
    try {
      final daemonH = await _wallet!.fetchDaemonHeight();
      final tip = RestoreHeightUtils.scanHeightFromDaemonTip(daemonH);
      if (tip > 0) {
        await _wallet!.setRestoreHeight(tip);
      }
    } catch (_) {
      // First refresh may still proceed from height 0.
    }
  }

  Future<bool> _syncAfterOpen() async {
    connectionState = WalletConnectionState.connected;
    syncStatus = WalletSyncStatus.syncing;
    errorMessage = null;
    notifyListeners();
    try {
      await _runInitialWalletRefresh();
      await _startBlockchainSync();
      return true;
    } catch (e) {
      _disposeWalletOnFailure();
      connectionState = WalletConnectionState.error;
      errorMessage = _userMessage(e);
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> _persistWalletSession(String filename, String password) async {
    await _settings.saveWalletFilename(filename);
    await _settings.saveWalletPassword(password);
    await _settings.saveWalletPasswordFor(filename, password);
    await _settings.saveWalletNetwork(networkType);
    await _settings.saveWalletNetworkFor(filename, networkType);
    await _settings.setOnboarded(true);
    walletFilename = filename;
    walletNetworkType = networkType;
  }

  Future<bool> openExistingWallet({
    required String filename,
    required String password,
  }) async {
    return switchToWallet(filename: filename, password: password);
  }

  static bool isValidWalletFilename(String name) {
    final t = name.trim();
    return t.isNotEmpty && !t.contains('/') && !t.contains('\\');
  }

  int sendPriority = 0;

  Future<int?> estimateTransferFee({
    required String address,
    required String amount,
    int? priority,
  }) async {
    if (_wallet == null || !_wallet!.isOpen) return null;
    return _blockchainJobs.run(
      () async => _wallet!.estimateFee(
        address: address,
        amountDisplay: amount,
        priority: priority ?? sendPriority,
      ),
    );
  }

  Future<String?> sendTransfer({
    required String address,
    required String amount,
    int? priority,
  }) async {
    if (_wallet == null || !_wallet!.isOpen) {
      errorMessage = 'Wallet not open';
      notifyListeners();
      return null;
    }
    if (!canTransact) {
      errorMessage = !isSynced
          ? 'Wait for sync to finish before sending'
          : 'Wallet not ready';
      notifyListeners();
      return null;
    }
    try {
      final tx = await _blockchainJobs.run(
        () => _wallet!.send(
          address: address,
          amountDisplay: amount,
          priority: priority ?? sendPriority,
        ),
      );
      await _persistWalletFile(force: true);
      try {
        await refresh();
      } catch (_) {
        // Send may have succeeded; background sync will catch up on Home.
      }
      return tx;
    } catch (e) {
      errorMessage = _userMessage(e);
      notifyListeners();
      return null;
    }
  }

  int get lockedBalanceAtomic {
    final b = balance;
    if (b == null) return 0;
    final locked = b.balanceAtomic - b.unlockedAtomic;
    return locked > 0 ? locked : 0;
  }

  String formatAmount(int atomic) => UiFormat.ztraAmount(atomic);

  int parseAmount(String display) =>
      _wallet?.parseDisplay(display) ?? ZentraCore.instance.displayToAtomic(display);

  /// Seed + address from the open wallet (for backup screen).
  Future<WalletBackupInfo?> fetchBackupInfo() async {
    if (_wallet == null || !_wallet!.isOpen) return null;
    try {
      final addr = primaryAddress ?? await _wallet!.fetchPrimaryAddress();
      final seed = await _wallet!.fetchSeed();
      return WalletBackupInfo(
        address: addr.address,
        seedPhrase: seed?.trim().isNotEmpty == true ? seed!.trim() : null,
        walletName: walletFilename ?? 'wallet',
      );
    } catch (_) {
      return null;
    }
  }

  bool validateAddress(String addr) {
    final trimmed = addr.trim();
    if (trimmed.isEmpty) return false;
    if (_wallet != null) return _wallet!.validateAddress(trimmed);
    if (!nativeAvailable || networkConfig == null) return false;
    return ZentraNativeWallet.instance.addressValid(trimmed, networkConfig!.type.index);
  }

  int get blocksBehindDaemon {
    if (daemonBlockHeight <= 0) return 0;
    if (walletHeight <= 0) return daemonBlockHeight;
    final behind = daemonBlockHeight - walletHeight;
    return behind > 0 ? behind : 0;
  }

  /// Cake Wallet: synced when within [kWalletSyncedBlocksThreshold] of daemon tip.
  bool get isSynced =>
      connectionState == WalletConnectionState.connected &&
      daemonBlockHeight > 0 &&
      blocksBehindDaemon < kWalletSyncedBlocksThreshold;

  bool get isWalletBehindDaemon => !isSynced && daemonBlockHeight > 0;

  /// True only while the wallet file is being opened (not blockchain catch-up sync).
  bool get isOpeningWallet =>
      syncStatus == WalletSyncStatus.connecting ||
      (connectionState == WalletConnectionState.connecting && !_backgroundSync.isActive);

  /// Connected but daemon height not available yet (node RPC / first refresh pending).
  bool get isWaitingForDaemon =>
      connectionState == WalletConnectionState.connected && daemonBlockHeight <= 0;

  bool get showSyncBanner =>
      isWalletBehindDaemon || isWaitingForDaemon || (connectionState == WalletConnectionState.connected && !isSynced);

  /// Subtitle under the sync banner on Home / History / Settings.
  String? get syncBannerSubtitle {
    if (isWaitingForDaemon) {
      return isBackgroundSyncing ? 'Fetching node status…' : 'Connecting to node…';
    }
    final label = syncProgressLabel;
    final eta = _lastSyncProgress?.formattedEta;
    if (label != null && eta != null) return '$label · $eta';
    return label ?? eta;
  }

  bool get canTransact =>
      connectionState == WalletConnectionState.connected && isSynced;

  String get connectionStatusLabel {
    if (connectionState == WalletConnectionState.error) return 'Error';
    if (connectionState == WalletConnectionState.disconnected) return 'Offline';
    if (connectionState == WalletConnectionState.connecting) return 'Connecting';
    switch (syncStatus) {
      case WalletSyncStatus.synced:
        return 'Synced';
      case WalletSyncStatus.syncing:
        return 'Syncing';
      case WalletSyncStatus.attempting:
        return 'Syncing';
      case WalletSyncStatus.connected:
        return 'Connected';
      case WalletSyncStatus.connecting:
        return 'Opening';
      case WalletSyncStatus.disconnected:
        return 'Offline';
    }
  }

  /// e.g. "Block 650 of 668 · 18 blocks behind" while catching up.
  String? get syncProgressLabel {
    if (!isWalletBehindDaemon || daemonBlockHeight <= 0) return null;
    final behind = blocksBehindDaemon;
    if (behind > 0 && behind < daemonBlockHeight) {
      return 'Block $walletHeight of $daemonBlockHeight · $behind behind';
    }
    return 'Block $walletHeight of $daemonBlockHeight';
  }

  double? get syncProgressFraction {
    if (!isWalletBehindDaemon || daemonBlockHeight <= 0) return null;
    final p = _lastSyncProgress?.progressFraction;
    if (p != null && p > 0) return p;
    return (walletHeight / daemonBlockHeight).clamp(0.0, 1.0);
  }

  Future<void> updateNetwork(ZentraNetType type) async {
    final reconnect = walletFilename != null && walletFilename!.isNotEmpty;
    if (reconnect &&
        walletNetworkType != null &&
        walletNetworkType != type) {
      errorMessage =
          'This wallet belongs to ${ZentraNetworkConfig.fromType(walletNetworkType!).label}. '
          'Use a different wallet file for ${ZentraNetworkConfig.fromType(type).label}.';
      notifyListeners();
      return;
    }
    networkType = type;
    networkConfig = ZentraNetworkConfig.fromType(type);
    await _settings.saveNetwork(type);
    if (type == ZentraNetType.mainnet) {
      final node = ZentraPublicNode.seedPrimary;
      nodeSettings = node.toNodeSettings();
      selectedPublicNode = node;
    } else {
      final cfg = networkConfig!;
      nodeSettings = NodeConnectionSettings(
        daemonAddress: '127.0.0.1:${cfg.daemonRpcPort}',
      );
      selectedPublicNode = null;
    }
    await _settings.saveNode(nodeSettings!);
    _resetWalletSession();
    notifyListeners();
    if (reconnect) await connect();
  }

  Future<void> updateNode(NodeConnectionSettings settings) async {
    final reconnect = connectionState == WalletConnectionState.connected &&
        walletFilename != null &&
        walletFilename!.isNotEmpty;
    nodeSettings = settings;
    selectedPublicNode = ZentraPublicNode.byId(settings.publicNodeId);
    await _settings.saveNode(settings);
    _resetWalletSession();
    notifyListeners();
    if (reconnect) await connect();
  }

  void _resetWalletSession() {
    _connectGeneration++;
    _stopBlockchainSync();
    unawaited(_closeWalletService());
    balance = null;
    primaryAddress = null;
    transfers = [];
    transferTotalCount = 0;
    isLoadingMoreTransfers = false;
    walletHeight = 0;
    daemonBlockHeight = 0;
    daemonStatus = null;
    walletScanHeight = 0;
    connectionState = WalletConnectionState.disconnected;
    errorMessage = null;
  }

  @override
  void dispose() {
    _connectGeneration++;
    _stopBlockchainSync();
    unawaited(_closeWalletService().whenComplete(ZentraNativeWallet.release));
    super.dispose();
  }
}
