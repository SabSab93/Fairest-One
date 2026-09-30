class ClientRecord {
  const ClientRecord({
    required this.id,
    required this.email,
    required this.cardUid,
    required this.photoCount,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String? cardUid;
  final int photoCount;
  final DateTime createdAt;

  factory ClientRecord.fromJson(Map<String, Object?> json) {
    return ClientRecord(
      id: json['id']! as String,
      email: json['email']! as String,
      cardUid: json['cardUid'] as String?,
      photoCount: json['photoCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt']! as String),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'email': email,
      'cardUid': cardUid,
      'photoCount': photoCount,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
