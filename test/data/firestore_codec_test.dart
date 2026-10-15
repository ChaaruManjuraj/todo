import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/firestore_repo.dart';
import 'package:todo/domain/task.dart';

final t0 = DateTime.utc(2026, 10, 1, 8);
final full = Task(
  id: 'a',
  name: 'Buy milk',
  startDate: '2026-10-15',
  startTime: '10:00',
  endDate: '2026-10-15',
  endTime: '11:00',
  people: ['Ann', 'Bo'],
  notes: 'n',
  reminder: true,
  done: true,
  doneAt: DateTime.utc(2026, 10, 15, 12),
  createdAt: t0,
  updatedAt: t0,
);

void main() {
  test('toFirestore writes the schema the security rules expect', () {
    final m = taskToFirestore(full);
    expect(m.keys.toSet(), {'name', 'startDate', 'startTime', 'endDate', 'endTime', 'people', 'notes', 'reminder', 'done', 'doneAt', 'createdAt', 'updatedAt'});
    expect(m['createdAt'], isA<Timestamp>());
    expect(m['doneAt'], isA<Timestamp>());
    expect(m['updatedAt'], isA<FieldValue>()); // server-stamped
    expect(m['people'], ['Ann', 'Bo']);
  });

  test('a task without optional fields writes explicit nulls', () {
    final m = taskToFirestore(Task(id: 'b', name: 'x', createdAt: t0, updatedAt: t0));
    for (final k in ['startDate', 'startTime', 'endDate', 'endTime', 'doneAt']) {
      expect(m.containsKey(k) && m[k] == null, isTrue, reason: k);
    }
  });

  test('fromFirestore round-trips every field', () {
    final doc = {...taskToFirestore(full), 'updatedAt': Timestamp.fromDate(t0)};
    expect(taskFromFirestore('a', doc), full);
  });

  test('a pending server timestamp (null) reads back as "now"', () {
    final now = DateTime.utc(2026, 10, 15, 9);
    final doc = {...taskToFirestore(full)}..['updatedAt'] = null;
    expect(taskFromFirestore('a', doc, now: now).updatedAt, now);
  });

  test('missing optional fields get safe defaults', () {
    final t = taskFromFirestore('c', {'name': 'x', 'createdAt': Timestamp.fromDate(t0), 'updatedAt': Timestamp.fromDate(t0)});
    expect(t.people, isEmpty);
    expect(t.notes, '');
    expect(t.reminder, isFalse);
    expect(t.done, isFalse);
    expect(t.doneAt, isNull);
  });
}
