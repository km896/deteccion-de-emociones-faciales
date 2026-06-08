class UserModel {
  String? id;
  String name;
  List<double> faceData;        // vector del centro (para login)
  Map<String, List<double>> stepData; // vectores por paso (para mejor precisión)
  DateTime createdAt;

  UserModel({
    this.id,
    required this.name,
    required this.faceData,
    required this.stepData,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'faceData': faceData,
    'stepData': stepData.map((k, v) => MapEntry(k, v)),
    'createdAt': createdAt.toIso8601String(),
  };

  factory UserModel.fromMap(String id, Map<String, dynamic> map) {
    // Leer stepData de Firestore de forma segura
    final rawStepData = map['stepData'] as Map<String, dynamic>? ?? {};
    final stepData = rawStepData.map(
          (k, v) => MapEntry(k, List<double>.from(v as List)),
    );

    return UserModel(
      id: id,
      name: map['name'] ?? '',
      faceData: List<double>.from(map['faceData'] ?? []),
      stepData: stepData,
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}