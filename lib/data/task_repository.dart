import 'package:flutter/foundation.dart';

import '../domain/task.dart';

abstract class TaskRepository {
  /// Emits the current list immediately on listen, then on every change.
  Stream<List<Task>> watch();

  /// Stamps `updatedAt`, then stores the task.
  Future<void> upsert(Task task);

  Future<void> delete(String id);

  /// Writes not yet synced; always 0 except for the desktop REST repo.
  ValueListenable<int> get pending;
}
