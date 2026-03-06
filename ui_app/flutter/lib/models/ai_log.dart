class AILog {
  final int id;
  final String? createdAt;
  final String? model;
  final String? userPrompt;
  final String? response;
  final int? tokensIn;
  final int? tokensOut;
  final double? costUsd;
  final bool? isTest;

  AILog({
    required this.id,
    this.createdAt,
    this.model,
    this.userPrompt,
    this.response,
    this.tokensIn,
    this.tokensOut,
    this.costUsd,
    this.isTest,
  });

  factory AILog.fromJson(Map<String, dynamic> json) {
    return AILog(
      id: json['id'] as int,
      createdAt: json['created_at'] as String?,
      model: json['model'] as String?,
      userPrompt: json['user_prompt'] as String?,
      response: json['response'] as String? ?? json['ai_response'] as String?,
      tokensIn: json['tokens_in'] as int?,
      tokensOut: json['tokens_out'] as int?,
      costUsd: (json['cost_usd'] as num?)?.toDouble(),
      isTest: json['is_test'] as bool?,
    );
  }
}
