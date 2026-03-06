class ExchangeAccount {
  final int id;
  final String exchangeType;
  final String label;
  final String apiKeyMasked;
  final bool isActive;
  final bool isConnected;
  final String? lastError;
  final String? availableBalance;
  final String createdAt;

  ExchangeAccount({
    required this.id,
    required this.exchangeType,
    required this.label,
    required this.apiKeyMasked,
    required this.isActive,
    required this.isConnected,
    this.lastError,
    this.availableBalance,
    required this.createdAt,
  });

  factory ExchangeAccount.fromJson(Map<String, dynamic> json) {
    return ExchangeAccount(
      id: json['id'] as int,
      exchangeType: json['exchange_type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      apiKeyMasked: json['api_key_masked'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      isConnected: json['is_connected'] as bool? ?? false,
      lastError: json['last_error'] as String?,
      availableBalance: json['available_balance'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  String get exchangeIcon {
    switch (exchangeType) {
      case 'bitunix': return '⚡';
      case 'phemex': return '🔷';
      default: return '🔗';
    }
  }

  String get exchangeDisplayName {
    switch (exchangeType) {
      case 'bitunix': return 'BitUnix';
      case 'phemex': return 'Phemex';
      default: return exchangeType;
    }
  }
}
