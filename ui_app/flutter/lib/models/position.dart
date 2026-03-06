class Position {
  final String exchange;
  final String positionId;
  final String symbol;
  final String side;
  final String qty;
  final String entryPrice;
  final String markPrice;
  final String leverage;
  final String unrealizedPnl;
  final String realizedPnl;
  final String liquidationPrice;
  final String marginMode;
  final String margin;
  final String? updatedAt;

  Position({
    required this.exchange,
    required this.positionId,
    required this.symbol,
    required this.side,
    required this.qty,
    required this.entryPrice,
    required this.markPrice,
    required this.leverage,
    required this.unrealizedPnl,
    required this.realizedPnl,
    required this.liquidationPrice,
    required this.marginMode,
    required this.margin,
    this.updatedAt,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      exchange: json['exchange'] as String? ?? '',
      positionId: json['positionId'] as String? ?? '',
      symbol: json['symbol'] as String? ?? '',
      side: json['side'] as String? ?? '',
      qty: json['qty'] as String? ?? '0',
      entryPrice: json['entryPrice'] as String? ?? '0',
      markPrice: json['markPrice'] as String? ?? '0',
      leverage: json['leverage'] as String? ?? '1',
      unrealizedPnl: json['unrealizedPnl'] as String? ?? '0',
      realizedPnl: json['realizedPnl'] as String? ?? '0',
      liquidationPrice: json['liquidationPrice'] as String? ?? '0',
      marginMode: json['marginMode'] as String? ?? '',
      margin: json['margin'] as String? ?? '0',
      updatedAt: json['updatedAt'] as String?,
    );
  }
}
