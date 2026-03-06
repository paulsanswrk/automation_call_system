class TradeAction {
  final int id;
  final String? createdAt;
  final String? discordMessageId;
  final String? action;
  final String? exchange;
  final String? symbol;
  final String? side;
  final String? orderType;
  final String? qty;
  final String? price;
  final String? orderId;
  final String? slPrice;
  final String? notes;
  final dynamic request;
  final dynamic result;
  final String? clientId;

  TradeAction({
    required this.id,
    this.createdAt,
    this.discordMessageId,
    this.action,
    this.exchange,
    this.symbol,
    this.side,
    this.orderType,
    this.qty,
    this.price,
    this.orderId,
    this.slPrice,
    this.notes,
    this.request,
    this.result,
    this.clientId,
  });

  factory TradeAction.fromJson(Map<String, dynamic> json) {
    return TradeAction(
      id: json['id'] as int,
      createdAt: json['created_at'] as String?,
      discordMessageId: json['discord_message_id'] as String?,
      action: json['action'] as String?,
      exchange: json['exchange'] as String?,
      symbol: json['symbol'] as String?,
      side: json['side'] as String?,
      orderType: json['order_type'] as String?,
      qty: json['qty'] as String?,
      price: json['price'] as String?,
      orderId: json['order_id'] as String?,
      slPrice: json['sl_price'] as String?,
      notes: json['notes'] as String?,
      request: json['request'],
      result: json['result'],
      clientId: json['client_id'] as String?,
    );
  }
}
