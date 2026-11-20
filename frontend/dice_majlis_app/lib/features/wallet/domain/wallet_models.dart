/// The two currencies, by the code the server uses.
abstract final class Currencies {
  static const gold = 'gold';
  static const diamond = 'diamond';
}

/// How much of each currency the player has (from the server).
class Balances {
  const Balances({this.gold = 0, this.diamond = 0});

  factory Balances.fromJson(Map<String, dynamic> json) {
    int amount(Object? value) => value is num ? value.toInt() : 0;
    return Balances(
      gold: amount(json[Currencies.gold]),
      diamond: amount(json[Currencies.diamond]),
    );
  }

  final int gold;
  final int diamond;

  @override
  bool operator ==(Object other) =>
      other is Balances && other.gold == gold && other.diamond == diamond;

  @override
  int get hashCode => Object.hash(gold, diamond);
}

/// One line of the wallet's history (a ledger entry).
class WalletEntry {
  const WalletEntry({
    required this.id,
    required this.reference,
    required this.currency,
    required this.amount,
    required this.balanceAfter,
    required this.type,
    required this.createdAt,
  });

  factory WalletEntry.fromJson(Map<String, dynamic> json) => WalletEntry(
    id: json['id'].toString(),
    reference: json['reference']?.toString() ?? '',
    currency: json['currency']?.toString() ?? '',
    amount: (json['amount'] as num).toInt(),
    balanceAfter: (json['balance_after'] as num?)?.toInt() ?? 0,
    type: json['type']?.toString() ?? '',
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
  );

  final String id;

  /// Short id to give support, e.g. `TXN-1A2B3C4D`.
  final String reference;
  final String currency;

  /// + received, − spent or taken back.
  final int amount;
  final int balanceAfter;

  /// Why it happened: `reward_daily`, `admin_grant`, ...
  final String type;
  final DateTime? createdAt;
}

/// A page of history; [next] fetches the one after it (null = the end).
class WalletPage {
  const WalletPage({required this.entries, this.next});

  factory WalletPage.fromJson(Map<String, dynamic> json) => WalletPage(
    entries: [
      for (final entry in json['transactions'] as List? ?? const [])
        WalletEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
    ],
    next: json['next']?.toString(),
  );

  final List<WalletEntry> entries;
  final String? next;
}
