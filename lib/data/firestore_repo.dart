import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/task.dart';
import 'task_repository.dart';

/// `updatedAt` is stamped by the server so last-write-wins doesn't depend on device clocks.
Map<String, Object?> taskToFirestore(Task t) => {
      'name': t.name,
      'startDate': t.startDate,
      'startTime': t.startTime,
      'endDate': t.endDate,
      'endTime': t.endTime,
      'people': t.people,
      'notes': t.notes,
      'reminder': t.reminder,
      'done': t.done,
      'doneAt': t.doneAt == null ? null : Timestamp.fromDate(t.doneAt!),
      'createdAt': Timestamp.fromDate(t.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };

/// A pending local write reads back with a null server timestamp; treat that as "just now".
Task taskFromFirestore(String id, Map<String, Object?> d, {DateTime? now}) {
  DateTime ts(Object? v) => v is Timestamp ? v.toDate().toUtc() : (now ?? DateTime.now()).toUtc();
  return Task(
    id: id,
    name: d['name'] as String? ?? '',
    startDate: d['startDate'] as String?,
    startTime: d['startTime'] as String?,
    endDate: d['endDate'] as String?,
    endTime: d['endTime'] as String?,
    people: [for (final p in (d['people'] as List? ?? const [])) '$p'],
    notes: d['notes'] as String? ?? '',
    reminder: d['reminder'] as bool? ?? false,
    done: d['done'] as bool? ?? false,
    doneAt: d['doneAt'] is Timestamp ? (d['doneAt'] as Timestamp).toDate().toUtc() : null,
    createdAt: ts(d['createdAt']),
    updatedAt: ts(d['updatedAt']),
  );
}

class FirestoreRepo implements TaskRepository {
  FirestoreRepo(String uid, {FirebaseFirestore? db}) : _col = (db ?? FirebaseFirestore.instance).collection('users').doc(uid).collection('tasks');

  final CollectionReference<Map<String, dynamic>> _col;

  @override
  final pending = ValueNotifier(0); // the SDK queues offline writes itself

  @override
  Stream<List<Task>> watch() => _col.snapshots().map((s) => [for (final d in s.docs) taskFromFirestore(d.id, d.data())]);

  @override
  Future<void> upsert(Task task) => _col.doc(task.id).set(taskToFirestore(task));

  @override
  Future<void> delete(String id) => _col.doc(id).delete();
}
