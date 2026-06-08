import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/services/emotion_analyzer.dart';
import '../core/providers/emotion_providers.dart';
import '../core/models/emotion_entry.dart';

const _todayEmotionColors = {
  'happy': Color(0xFFFFD93D),
  'sad': Color(0xFF6C9BCF),
  'surprised': Color(0xFFFF8C42),
  'angry': Color(0xFFEF5350),
  'sleepy': Color(0xFF7E57C2),
  'thinking': Color(0xFF26C6DA),
  'neutral': Color(0xFF4F8EF7),
};

class HistoryPage extends ConsumerStatefulWidget {
  final String? userName;
  const HistoryPage({super.key, this.userName});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  Map<String, int> _todayCounts = {};
  int _streak = 0;
  Map<DateTime, List<EmotionEntry>> _week = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(emotionHistoryRepoProvider);
    final today = await repo.getToday(userName: widget.userName);
    final week = await repo.getWeek(userName: widget.userName);

    final counts = <String, int>{};
    for (final e in today) {
      counts[e.emotion] = (counts[e.emotion] ?? 0) + 1;
    }

    int streak = 0;
    final now = DateTime.now();
    for (int i = 0; i < 30; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      final entries = week[day] ?? [];
      if (entries.isEmpty) break;
      streak++;
    }

    if (mounted) {
      setState(() {
        _todayCounts = counts;
        _streak = streak;
        _week = week;
        _loading = false;
      });
    }
  }

  String get _dominantEmotion {
    if (_todayCounts.isEmpty) return 'neutral';
    return _todayCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }

  String _recommendation() {
    final total = _todayCounts.values.fold(0, (a, b) => a + b);
    if (total == 0) return 'Aún no hay suficientes datos hoy. Usa la cámara para comenzar el análisis.';

    final angry = (_todayCounts['angry'] ?? 0) / total;
    final sad = (_todayCounts['sad'] ?? 0) / total;
    final sleepy = (_todayCounts['sleepy'] ?? 0) / total;
    final thinking = (_todayCounts['thinking'] ?? 0) / total;
    final happy = (_todayCounts['happy'] ?? 0) / total;

    if (angry > 0.3) return 'Has mostrado señales de tensión. Prueba el recordatorio 20-20-20 para desconectar.';
    if (sad > 0.3) return 'Estado melancólico detectado. Tomar un descanso al aire libre puede ayudar.';
    if (sleepy > 0.3) return 'Somnolencia frecuente detectada. Considera ajustar tu descanso nocturno.';
    if (thinking > 0.3) return 'Mente muy activa hoy. La respiración guiada puede ayudarte a enfocarte.';
    if (happy > 0.5) return 'Excelente ánimo hoy. Sigue así.';
    return 'Estado equilibrado. Sigue monitoreando tu bienestar emocional.';
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    const days = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
    return days[d.weekday % 7];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060810),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Historial Emocional',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4F8EF7)))
          : RefreshIndicator(
              color: const Color(0xFF4F8EF7),
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildStatsSummary(),
                  const SizedBox(height: 20),
                  _buildTodayChart(),
                  const SizedBox(height: 20),
                  _buildWeekChart(),
                  const SizedBox(height: 20),
                  _buildRecommendation(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsSummary() {
    final dominant = _dominantEmotion;
    final dColor = _todayEmotionColors[dominant] ?? const Color(0xFF4F8EF7);
    final total = _todayCounts.values.fold(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            dColor.withValues(alpha: 0.15),
            const Color(0xFF060810),
          ],
        ),
        border: Border.all(color: dColor.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                EmotionAnalyzer.nameFor(
                    Emotion.values.firstWhere((e) => e.name == dominant)),
                style: TextStyle(
                  color: dColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Emoción dominante hoy',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
              ),
            ],
          ),
        ),
        Column(children: [
          Text(
            '$total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text('registros',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
        ]),
        const SizedBox(width: 24),
        Column(children: [
          Text(
            '$_streak',
            style: const TextStyle(
              color: Color(0xFFFFD93D),
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text('días seguidos',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
        ]),
      ]),
    );
  }

  Widget _buildTodayChart() {
    if (_todayCounts.isEmpty) {
      return _emptyCard('Sin datos hoy');
    }

    final sorted = _todayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = sorted.first.value.toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Distribución de emociones',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.3,
                barGroups: sorted.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value.toDouble(),
                        color:
                            _todayEmotionColors[e.value.key] ?? Colors.white,
                        width: 32,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(8)),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= sorted.length) {
                          return const SizedBox();
                        }
                        final emoji =
                            EmotionAnalyzer.emojiFor(Emotion.values.firstWhere(
                                (e) => e.name == sorted[idx].key));
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(emoji, style: const TextStyle(fontSize: 18)),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekChart() {
    final days = _week.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Últimos 7 días',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              children: days.map((d) {
                final dayEmotions = d.value;
                String emoji;
                if (dayEmotions.isEmpty) {
                  emoji = '—';
                } else {
                  final counts = <String, int>{};
                  for (final e in dayEmotions) {
                    counts[e.emotion] = (counts[e.emotion] ?? 0) + 1;
                  }
                  final dom = counts.entries
                      .reduce((a, b) => a.value > b.value ? a : b)
                      .key;
                  emoji = EmotionAnalyzer.emojiFor(
                      Emotion.values.firstWhere((e) => e.name == dom));
                }
                return Expanded(
                  child: Column(children: [
                    Text(emoji,
                        style: TextStyle(
                            fontSize: 24,
                            color: dayEmotions.isEmpty
                                ? Colors.white24
                                : Colors.white)),
                    const SizedBox(height: 6),
                    Text(
                      _dayLabel(d.key)[0],
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 11),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendation() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF4F8EF7).withValues(alpha: 0.1),
            const Color(0xFF7B5EA7).withValues(alpha: 0.05),
          ],
        ),
        border: Border.all(
            color: const Color(0xFF4F8EF7).withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recomendación',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  _recommendation(),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Center(
        child: Text(msg,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3), fontSize: 14)),
      ),
    );
  }
}
