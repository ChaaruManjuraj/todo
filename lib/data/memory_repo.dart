import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/task.dart';
import 'task_repository.dart';

class MemoryRepo implements TaskRepository {
  MemoryRepo([Iterable<Task> initial = const [], DateTime Function()? now]) : _now = now ?? DateTime.now {
    for (final t in initial) {
      _tasks[t.id] = t;
    }
  }

  final DateTime Function() _now;
  final _tasks = <String, Task>{};
  final _listeners = <MultiStreamController<List<Task>>>{};

  @override
  final pending = ValueNotifier(0);

  List<Task> get _snapshot => List.unmodifiable(_tasks.values);

  @override
  Stream<List<Task>> watch() => Stream.multi((c) {
        _listeners.add(c);
        c.onCancel = () => _listeners.remove(c);
        c.add(_snapshot);
      });

  @override
  Future<void> upsert(Task task) async {
    _tasks[task.id] = task.copyWith(updatedAt: _now().toUtc());
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _tasks.remove(id);
    _emit();
  }

  void _emit() {
    final s = _snapshot;
    for (final c in _listeners) {
      c.add(s);
    }
  }
}
