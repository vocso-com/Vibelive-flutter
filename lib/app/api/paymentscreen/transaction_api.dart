import '../../../core/network/api_client.dart';
import 'payment_json.dart';
import 'wallet_api.dart';
import 'wallet_models.dart';

/// Wallet transaction history.
abstract final class TransactionApi {
  /// Wallet screen page size (RN `TRANSACTIONS_PER_PAGE`).
  static const pageSize = 10;

  /// `GET /transactions` touching any wallet of [userDocumentId], newest
  /// first. A full page (length == [size]) means there may be more.
  /// Commission rows are included; the screen hides them.
  static Future<List<WalletTransaction>> fetchPage(
    String userDocumentId, {
    TransactionFilter filter = TransactionFilter.all,
    int page = 1,
    int size = pageSize,
  }) async {
    final uid = userDocumentId.trim();
    if (uid.isEmpty) return const [];
    final walletType = switch (filter) {
      TransactionFilter.all => null,
      TransactionFilter.cash => WalletType.cash,
      TransactionFilter.earnings => WalletType.earnings,
    };
    final body = await ApiClient.get(
      '/transactions',
      query: {
        r'filters[$or][0][FromWallet][user][documentId][$eq]': uid,
        r'filters[$or][0][FromWallet][wallet_type][$eq]': ?walletType,
        r'filters[$or][1][to_wallet][user][documentId][$eq]': uid,
        r'filters[$or][1][to_wallet][wallet_type][$eq]': ?walletType,
        'sort': 'createdAt:desc',
        'pagination[page]': page,
        'pagination[pageSize]': size,
        ..._listFields,
      },
    );
    return [for (final row in paymentRows(body)) WalletTransaction(row)];
  }

  static const _listFields = {
    'fields[0]': 'createdAt',
    'fields[1]': 'transaction_Id',
    'fields[2]': 'amount',
    'fields[3]': 'paymentStatus',
    'fields[4]': 'transactionType',
    'fields[5]': 'method',
    // Chat rows: who and how many ("Chat with Priya · 12 messages").
    'fields[6]': 'Note',
    'populate[call][fields][0]': 'type',
    'populate[call][populate][caller][fields][0]': 'name',
    'populate[call][populate][receiver][fields][0]': 'name',
    'populate[to_wallet][fields][0]': 'wallet_type',
    'populate[to_wallet][fields][1]': 'balance',
    'populate[FromWallet][fields][0]': 'wallet_type',
    'populate[FromWallet][fields][1]': 'balance',
    'populate[invoices][populate][Invoice_PDF][fields][0]': 'url',
    'populate[invoices][populate][Invoice_PDF][fields][1]': 'name',
  };

  /// Latest 5 rows of one wallet, with both sides' users (for the
  /// counterparty name).
  static Future<List<WalletTransaction>> fetchLatestForWallet(
    Wallet wallet,
  ) async {
    final docId = wallet.documentId;
    final field = docId != null ? 'documentId' : 'id';
    final value = docId ?? '${wallet.id}';
    final body = await ApiClient.get(
      '/transactions',
      query: {
        'filters[\$or][0][FromWallet][$field][\$eq]': value,
        'filters[\$or][1][to_wallet][$field][\$eq]': value,
        'populate[FromWallet][populate][user][populate]': 'profilePic',
        'populate[to_wallet][populate][user][populate]': 'profilePic',
        'pagination[page]': 1,
        'pagination[pageSize]': 5,
        'sort': 'createdAt:desc',
      },
    );
    return [for (final row in paymentRows(body)) WalletTransaction(row)];
  }

  /// For a wallet push that doesn't say who paid whom: the transfer made in
  /// the last 30 s, or null. Callers treat errors as "no notification".
  static Future<RecentWalletTransfer?> resolveRecentTransfer(
    String userDocumentId, {
    DateTime? now,
  }) async {
    final wallet = await WalletApi.fetchPreferredWallet(userDocumentId);
    if (wallet == null || (wallet.documentId == null && wallet.id == null)) {
      return null;
    }
    final rows = await fetchLatestForWallet(wallet);
    return RecentWalletTransfer.resolve(
      rows,
      wallet,
      now: now ?? DateTime.now(),
    );
  }
}
