import 'package:flutter_test/flutter_test.dart';
import 'package:todo/domain/task.dart';

final t0 = DateTime.utc(2026, 10, 1);
Task mk({String id = 'a', String name = 'x'}) => Task(id: id, name: name, createdAt: t0, updatedAt: t0);

void main() {
  test('json round-trip keeps every field', () {
    final t = mk().copyWith(
      startDate: '2026-10-15',
      startTime: '10:00',
      endDate: '2026-10-15',
      endTime: '11:00',
      people: ['Ann', 'Bo'],
      notes: 'n',
      reminder: true,
      done: true,
      doneAt: DateTime.utc(2026, 10, 15, 12),
    );
    expect(Task.fromJson(t.toJson()), t);
  });

  test('fromJson tolerates missing optional fields', () {
    final t = Task.fromJson({'id': 'a', 'name': 'x', 'createdAt': t0.toIso8601String(), 'updatedAt': t0.toIso8601String()});
    expect(t.people, isEmpty);
    expect(t.reminder, isFalse);
    expect(t.startDate, isNull);
  });

  test('copyWith can clear nullable fields and leaves others alone', () {
    final t = mk().copyWith(startDate: '2026-10-15', startTime: '10:00');
    final c = t.copyWith(startTime: null);
    expect(c.startTime, isNull);
    expect(c.startDate, '2026-10-15');
    expect(t.copyWith(name: 'y').startTime, '10:00');
  });
}
