class DiscordMessage {
  final int id;
  final String messageId;
  final String author;
  final String channelName;
  final String textContent;
  final String receivedAt;
  final bool? isTest;

  DiscordMessage({
    required this.id,
    required this.messageId,
    required this.author,
    required this.channelName,
    required this.textContent,
    required this.receivedAt,
    this.isTest,
  });

  factory DiscordMessage.fromJson(Map<String, dynamic> json) {
    return DiscordMessage(
      id: json['id'] as int,
      messageId: json['message_id'] as String? ?? '',
      author: json['author'] as String? ?? '',
      channelName: json['channel_name'] as String? ?? '',
      textContent: json['text_content'] as String? ?? '',
      receivedAt: json['received_at'] as String? ?? '',
      isTest: json['is_test'] as bool?,
    );
  }
}
