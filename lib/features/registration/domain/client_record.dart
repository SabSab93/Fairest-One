class ClientRecord {
  const ClientRecord({
    required this.id,
    required this.email,
    required this.cardUid,
    required this.photoCount,
    required this.createdAt,
    this.messages = const [],
  });

  final String id;
  final String email;
  final String? cardUid;
  final int photoCount;
  final DateTime createdAt;
  final List<String> messages;

  factory ClientRecord.fromJson(Map<String, Object?> json) {
    return ClientRecord(
      id: json['id']! as String,
      email: json['email']! as String,
      cardUid: json['cardUid'] as String?,
      photoCount: json['photoCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt']! as String),
      messages: (json['messages'] as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'email': email,
      'cardUid': cardUid,
      'photoCount': photoCount,
      'createdAt': createdAt.toIso8601String(),
      'messages': messages,
    };
  }
}
