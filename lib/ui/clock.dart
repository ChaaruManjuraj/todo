import 'dart:async';

import 'package:flutter/foundation.dart';

/// "Now", refreshed every minute and on demand (app resume / window focus).
/// Pass `tick: null` and a fake [now] in tests.
class Clock extends ValueNotifier<DateTime> {
  Clock({DateTime Function()? now, Duration? tick = const Duration(minutes: 1)})
      : _now = now ?? DateTime.now,
        super((now ?? DateTime.now)()) {
    if (tick != null) _timer = Timer.periodic(tick, (_) => refresh());
  }

  final DateTime Function() _now;
  Timer? _timer;

  void refresh() => value = _now();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
