import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import 'dart:math';

final _db = FirebaseFirestore.instance;

// ─── Caché en memoria (TTL 5 min) ──────────────────────────────
List<UserModel>? _cachedUsers;
DateTime _lastFetch = DateTime(0);

Future<List<UserModel>> _fetchOrCacheUsers() async {
  final now = DateTime.now();
  if (_cachedUsers != null && now.difference(_lastFetch).inMinutes < 5) {
    debugPrint('🔍 Usando caché de usuarios (${_cachedUsers!.length} users)');
    return _cachedUsers!;
  }

  final snapshot = await _db
      .collection('users')
      .get()
      .timeout(const Duration(seconds: 10));

  final users = snapshot.docs
      .map((doc) => UserModel.fromMap(doc.id, doc.data()))
      .toList();

  _cachedUsers = users;
  _lastFetch = now;
  debugPrint('🔍 BD -> caché: ${users.length} usuarios');
  return users;
}

void invalidateCache() {
  _cachedUsers = null;
  _lastFetch = DateTime(0);
}

// ─── Guardar usuario ───────────────────────────────────────────
Future<bool> saveUser(UserModel user) async {
  try {
    final doc = await _db
        .collection('users')
        .add(user.toMap())
        .timeout(const Duration(seconds: 10));
    user.id = doc.id;
    invalidateCache();
    debugPrint('✅ Usuario guardado: ${doc.id}');
    return true;
  } catch (e) {
    debugPrint('❌ Error saveUser: $e');
    return false;
  }
}

// ─── Buscar usuario por rostro ────────────────────────────────
Future<UserModel?> findUserByFace(List<double> loginVector) async {
  try {
    final users = await _fetchOrCacheUsers();

    UserModel? bestUser;
    double bestScore = double.infinity;

    for (final user in users) {
      final scores = <double>[];

      if (user.faceData.isNotEmpty) {
        scores.add(_euclideanDistance(loginVector, user.faceData));
      }

      for (final stepVector in user.stepData.values) {
        if (stepVector.isNotEmpty) {
          scores.add(_euclideanDistance(loginVector, stepVector));
        }
      }

      if (scores.isEmpty) continue;

      final userScore = scores.reduce(min);
      debugPrint('📊 ${user.name} → mejor score: $userScore');

      if (userScore < bestScore) {
        bestScore = userScore;
        bestUser = user;
      }
    }

    const threshold = 1.5;
    debugPrint('🏆 Mejor score global: $bestScore — ${bestScore < threshold ? "✅ MATCH" : "❌ NO MATCH"} (umbral: $threshold)');

    return bestScore < threshold ? bestUser : null;
  } catch (e) {
    debugPrint('❌ Error findUserByFace: $e');
    return null;
  }
}

// ─── Distancia euclidiana ──────────────────────────────────────
double _euclideanDistance(List<double> a, List<double> b) {
  if (a.isEmpty || b.isEmpty) return double.infinity;
  final len = min(a.length, b.length);
  double sum = 0;
  for (int i = 0; i < len; i++) {
    sum += pow(a[i] - b[i], 2);
  }
  return sqrt(sum);
}