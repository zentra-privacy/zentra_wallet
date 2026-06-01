import 'package:intl/intl.dart';
import 'package:zentra_wallet_core/zentra_wallet_core.dart';

/// Human-friendly formatting for wallet UI.
class UiFormat {
  /// Whole ZTRA only (no decimal fraction) for balances and transactions.
  static String ztraAmount(int atomic) => (atomic ~/ zentraAtomicUnits).toString();

  static String truncateMiddle(String value, {int head = 10, int tail = 8}) {
    if (value.length <= head + tail + 1) return value;
    return '${value.substring(0, head)}…${value.substring(value.length - tail)}';
  }

  static String relativeTime(int timestampSec) {
    if (timestampSec <= 0) return 'Pending';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 48) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return DateFormat.yMMMd().format(dt);
  }
}
