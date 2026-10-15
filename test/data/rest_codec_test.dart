import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/firestore_rest_codec.dart';
import 'package:todo/domain/task.dart';

final t0 = DateTime.utc(2026, 10, 1, 8);
final full = Task(
  id: 'a',
  name: 'Buy milk',
  startDate: '2026-10-15',
  startTime: '10:00',
  endDate: '2026-10-16',
  endTime: '11:00',
  people: ['Ann', 'Bo'],
  notes: 'line 1\nline 2',
  reminder: true,
  done: true,
  doneAt: DateTime.utc(2026, 10, 15, 12),
  createdAt: t0,
  updatedAt: DateTime.utc(2026, 10, 2),
);

Map<String, Object?> doc(Task t) => {'name': 'projects/p/databases/(default)/documents/users/u/tasks/${t.id}', 'fields': toFirestoreFields(t)};

void main() {
  test('every field survives a round trip', () {
    expect(fromFirestoreDoc(doc(full)), full);
  });

  test('a task with nulls and no people round-trips', () {
    final t = Task(id: 'b', name: 'x', createdAt: t0, updatedAt: t0);
    expect(fromFirestoreDoc(doc(t)), t);
  });

  test('values use the REST typed-value shapes', () {
    final f = toFirestoreFields(full);
    expect(f['name'], {'stringValue': 'Buy milk'});
    expect(f['reminder'], {'booleanValue': true});
    expect(f['people'], {
      'arrayValue': {
        'values': [
          {'stringValue': 'Ann'},
          {'stringValue': 'Bo'}
        ]
      }
    });
    expect(f['doneAt'], {'timestampValue': '2026-10-15T12:00:00.000Z'});
    expect(toFirestoreFields(Task(id: 'b', name: 'x', createdAt: t0, updatedAt: t0))['startDate'], {'nullValue': null});
  });

  test('an empty array has no "values" key, as the server sends it', () {
    final f = toFirestoreFields(Task(id: 'b', name: 'x', createdAt: t0, updatedAt: t0));
    expect(f['people'], {'arrayValue': <String, Object?>{}});
  });

  test('the id is the last segment of the document name', () {
    expect(fromFirestoreDoc({'name': 'projects/p/databases/(default)/documents/users/u/tasks/abc123', 'fields': toFirestoreFields(full)}).id, 'abc123');
  });

  test('a sparse document gets safe defaults and falls back to createTime/updateTime', () {
    final t = fromFirestoreDoc({
      'name': 'x/y/z',
      'fields': {
        'name': {'stringValue': 'bare'}
      },
      'createTime': '2026-10-01T00:00:00Z',
      'updateTime': '2026-10-02T00:00:00Z',
    });
    expect([t.id, t.name, t.notes, t.reminder, t.done], ['z', 'bare', '', false, false]);
    expect(t.people, isEmpty);
    expect(t.createdAt, DateTime.utc(2026, 10, 1));
    expect(t.updatedAt, DateTime.utc(2026, 10, 2));
  });
}
