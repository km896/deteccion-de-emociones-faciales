class EmotionEntry {
  final String emotion;
  final double confidence;
  final DateTime timestamp;
  final String? userName;

  const EmotionEntry({
    required this.emotion,
    required this.confidence,
    required this.timestamp,
    this.userName,
  });

  Map<String, dynamic> toMap() => {
    'emotion': emotion,
    'confidence': confidence,
    'timestamp': timestamp.toIso8601String(),
    'userName': userName,
  };

  factory EmotionEntry.fromMap(Map<String, dynamic> map) => EmotionEntry(
    emotion: map['emotion'] as String,
    confidence: (map['confidence'] as num).toDouble(),
    timestamp: DateTime.parse(map['timestamp'] as String),
    userName: map['userName'] as String?,
  );
}
