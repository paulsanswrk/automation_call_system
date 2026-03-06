class ChannelSubscription {
  final int? id;
  final String status;
  final String tpRule;
  final bool autoSlAfterTp1;
  final String positionSizeType;
  final double positionSizeValue;
  final String? notes;

  ChannelSubscription({
    this.id,
    required this.status,
    required this.tpRule,
    required this.autoSlAfterTp1,
    required this.positionSizeType,
    required this.positionSizeValue,
    this.notes,
  });

  factory ChannelSubscription.fromJson(Map<String, dynamic> json) {
    return ChannelSubscription(
      id: json['id'] as int?,
      status: json['status'] as String? ?? 'off',
      tpRule: json['tp_rule'] as String? ?? 'halving',
      autoSlAfterTp1: json['auto_sl_after_tp1'] as bool? ?? false,
      positionSizeType: json['position_size_type'] as String? ?? 'min_qty',
      positionSizeValue: (json['position_size_value'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'tp_rule': tpRule,
    'auto_sl_after_tp1': autoSlAfterTp1,
    'position_size_type': positionSizeType,
    'position_size_value': positionSizeValue,
    'notes': notes ?? '',
  };
}

class Channel {
  final int id;
  final String channelName;
  final String? description;
  final String? firstSeenAt;
  String? lastMessageAt;
  String? lastHeartbeatAt;
  ChannelSubscription? subscription;
  List<int> exchangeAccountIds;

  Channel({
    required this.id,
    required this.channelName,
    this.description,
    this.firstSeenAt,
    this.lastMessageAt,
    this.lastHeartbeatAt,
    this.subscription,
    required this.exchangeAccountIds,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as int,
      channelName: json['channel_name'] as String? ?? '',
      description: json['description'] as String?,
      firstSeenAt: json['first_seen_at'] as String?,
      lastMessageAt: json['last_message_at'] as String?,
      lastHeartbeatAt: json['last_heartbeat_at'] as String?,
      subscription: json['subscription'] != null
          ? ChannelSubscription.fromJson(json['subscription'] as Map<String, dynamic>)
          : null,
      exchangeAccountIds: (json['exchange_account_ids'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList() ?? [],
    );
  }

  String get subStatus => subscription?.status ?? 'none';
}
