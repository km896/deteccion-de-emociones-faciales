import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ReminderPhase { active, resting, off }

class ReminderState {
  final ReminderPhase phase;
  final int secondsLeft;
  final int totalBreaks;

  const ReminderState({
    this.phase = ReminderPhase.active,
    this.secondsLeft = 20,
    this.totalBreaks = 0,
  });
}

class ReminderNotifier extends Notifier<ReminderState> {
  Timer? _workTimer;
  Timer? _restTimer;

  @override
  ReminderState build() {
    ref.onDispose(() {
      _workTimer?.cancel();
      _restTimer?.cancel();
    });
    return const ReminderState();
  }

  void start() {
    _workTimer?.cancel();
    state = ReminderState(
      phase: ReminderPhase.active,
      totalBreaks: state.totalBreaks,
    );
    _workTimer = Timer(const Duration(minutes: 20), _startRest);
  }

  void _startRest() {
    _workTimer?.cancel();
    state = ReminderState(
      phase: ReminderPhase.resting,
      secondsLeft: 20,
      totalBreaks: state.totalBreaks + 1,
    );

    _restTimer?.cancel();
    var tick = 0;
    _restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      tick++;
      final left = 20 - tick;
      if (left <= 0) {
        _restTimer?.cancel();
        start();
      } else {
        state = ReminderState(
          phase: ReminderPhase.resting,
          secondsLeft: left,
          totalBreaks: state.totalBreaks,
        );
      }
    });
  }

  void skipRest() {
    _restTimer?.cancel();
    start();
  }

  void toggle() {
    if (state.phase == ReminderPhase.off) {
      start();
    } else {
      _workTimer?.cancel();
      _restTimer?.cancel();
      state = const ReminderState(phase: ReminderPhase.off);
    }
  }
}

final reminderProvider = NotifierProvider<ReminderNotifier, ReminderState>(
  ReminderNotifier.new,
);
