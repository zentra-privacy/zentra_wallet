import '../models/wallet_models.dart';

/// Replace the loaded head with [headPage] while keeping previously paged tail rows.
List<WalletTransfer> mergeTransferHead(
  List<WalletTransfer> current,
  List<WalletTransfer> headPage,
) {
  if (current.isEmpty || current.length <= headPage.length) {
    return headPage;
  }
  return [...headPage, ...current.sublist(headPage.length)];
}

/// Append [page] without duplicate txids.
List<WalletTransfer> appendTransferPage(
  List<WalletTransfer> current,
  List<WalletTransfer> page,
) {
  if (page.isEmpty) return current;
  final seen = current.map((t) => t.txid).toSet();
  final merged = [...current];
  for (final tx in page) {
    if (seen.add(tx.txid)) merged.add(tx);
  }
  return merged;
}

int fingerprintTransferHead(List<Map<String, dynamic>> headRows, int totalCount) {
  var hash = totalCount;
  var pendingInHead = 0;
  for (final row in headRows) {
    if (row['pending'] == true) pendingInHead++;
  }
  hash = Object.hash(hash, pendingInHead);
  for (final row in headRows.take(5)) {
    hash = Object.hash(
      hash,
      row['txid'],
      row['pending'],
      row['amount'],
      row['timestamp'],
    );
  }
  return hash;
}
