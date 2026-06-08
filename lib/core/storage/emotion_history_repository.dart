import 'package:hive_flutter/hive_flutter.dart';
import '../models/emotion_entry.dart';

class EmotionHistoryRepository {
  static const _boxName = 'emotions';

  Future<Box> _openBox() => Hive.openBox(_boxName);

  Future<void> saveEntry(EmotionEntry entry) async {
    final box = await _openBox();
    await box.add(entry.toMap());
  }

  Future<List<EmotionEntry>> getRecent({int limit = 50}) async {
    final box = await _openBox();
    final all = box.values
        .cast<Map<dynamic, dynamic>>()
        .map((m) => EmotionEntry.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(limit).toList();
  }

  Future<List<EmotionEntry>> getByUser(String userName, {int limit = 50}) async {
    final box = await _openBox();
    final all = box.values
        .cast<Map<dynamic, dynamic>>()
        .map((m) => EmotionEntry.fromMap(Map<String, dynamic>.from(m)))
        .where((e) => e.userName == userName)
        .toList();
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(limit).toList();
  }

  Future<List<EmotionEntry>> getToday({String? userName}) async {
    final box = await _openBox();
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    return box.values
        .cast<Map<dynamic, dynamic>>()
        .map((m) => EmotionEntry.fromMap(Map<String, dynamic>.from(m)))
        .where((e) => e.timestamp.isAfter(startOfDay))
        .where((e) => userName == null || e.userName == userName)
        .toList();
  }

  Future<Map<DateTime, List<EmotionEntry>>> getWeek({String? userName}) async {
    final box = await _openBox();
    final now = DateTime.now();
    final result = <DateTime, List<EmotionEntry>>{};

    for (int i = 6; i >= 0; i--) {
      final day = DateTime(now.year, now.month, now.day - i);
      result[day] = [];
    }

    final start = result.keys.first;
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final entries = box.values
        .cast<Map<dynamic, dynamic>>()
        .map((m) => EmotionEntry.fromMap(Map<String, dynamic>.from(m)))
        .where((e) => e.timestamp.isAfter(start) && e.timestamp.isBefore(end))
        .where((e) => userName == null || e.userName == userName)
        .toList();

    for (final e in entries) {
      final day = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      result[day]?.add(e);
    }

    return result;
  }

  Future<void> clear() async {
    final box = await _openBox();
    await box.clear();
  }
}
