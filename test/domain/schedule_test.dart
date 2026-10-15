import 'package:flutter_test/flutter_test.dart';
import 'package:todo/domain/schedule.dart';
import 'package:todo/domain/task.dart';

final t0 = DateTime.utc(2026, 10, 1);
final now = DateTime(2026, 10, 15, 12, 0);

Task mk(String id, {String? date, String? time, bool reminder = false, bool done = false, DateTime? doneAt, List<String> people = const []}) =>
    Task(id: id, name: id, startDate: date, startTime: time, reminder: reminder, done: done, doneAt: doneAt, people: people, createdAt: t0, updatedAt: t0);

void main() {
  group('validate', () {
    final base = mk('a');
    test('valid shapes', () {
      expect(validate(base), isNull);
      expect(validate(base.copyWith(startDate: '2026-10-15', startTime: '10:00', endTime: '11:00', reminder: true)), isNull);
      expect(validate(base.copyWith(startDate: '2026-10-15', endDate: '2026-10-16')), isNull);
    });
    test('name rules', () {
      expect(validate(base.copyWith(name: '  ')), isNotNull);
      expect(validate(base.copyWith(name: 'a' * 200)), isNull);
      expect(validate(base.copyWith(name: 'a' * 201)), isNotNull);
    });
    test('notes limit', () {
      expect(validate(base.copyWith(notes: 'a' * 5000)), isNull);
      expect(validate(base.copyWith(notes: 'a' * 5001)), isNotNull);
    });
    test('time, end and reminder need a start date', () {
      expect(validate(base.copyWith(startTime: '10:00')), isNotNull);
      expect(validate(base.copyWith(endDate: '2026-10-15')), isNotNull);
      expect(validate(base.copyWith(endTime: '10:00')), isNotNull);
      expect(validate(base.copyWith(reminder: true)), isNotNull);
    });
    test('end must be after start', () {
      final s = base.copyWith(startDate: '2026-10-15', startTime: '10:00');
      expect(validate(s.copyWith(endTime: '10:00')), isNotNull);
      expect(validate(s.copyWith(endTime: '09:00')), isNotNull);
      expect(validate(s.copyWith(endDate: '2026-10-14')), isNotNull);
      expect(validate(s.copyWith(endDate: '2026-10-16', endTime: '09:00')), isNull);
    });
    test('rejects malformed date/time', () {
      expect(validate(base.copyWith(startDate: '15/10/2026')), isNotNull);
      expect(validate(base.copyWith(startDate: '2026-10-15', startTime: '24:00')), isNotNull);
    });
  });

  test('clearStart drops time, end and reminder', () {
    final t = mk('a', date: '2026-10-15', time: '10:00', reminder: true).copyWith(endDate: '2026-10-16', endTime: '11:00');
    final c = clearStart(t);
    expect([c.startDate, c.startTime, c.endDate, c.endTime], everyElement(isNull));
    expect(c.reminder, isFalse);
  });

  test('sortKey orders by date then time', () {
    final ks = [mk('a', date: '2026-10-16'), mk('b', date: '2026-10-15', time: '10:00'), mk('c', date: '2026-10-15', time: '09:00')];
    ks.sort((x, y) => sortKey(x).compareTo(sortKey(y)));
    expect(ks.map((t) => t.id), ['c', 'b', 'a']);
  });

  group('group', () {
    List<Section> sections(List<Task> ts, {bool all = false}) => groupTasks(ts, now, showAllCompleted: all).keys.toList();
    Section? of(Task t) => groupTasks([t], now).keys.firstOrNull;

    test('section boundaries', () {
      expect(of(mk('a', date: '2026-10-14')), Section.past);
      expect(of(mk('a', date: '2026-10-15')), Section.today);
      expect(of(mk('a', date: '2026-10-16')), Section.tomorrow);
      expect(of(mk('a', date: '2026-10-17')), Section.later);
      expect(of(mk('a')), Section.noDate);
      // just after midnight is still "today"; the previous day is past, whatever the time
      expect(groupTasks([mk('a', date: '2026-10-15', time: '00:00')], DateTime(2026, 10, 15, 0, 0)).keys, [Section.today]);
      expect(groupTasks([mk('a', date: '2026-10-15', time: '23:59')], DateTime(2026, 10, 16, 0, 0)).keys, [Section.past]);
    });

    test('month rollover: tomorrow of Oct 31 is Nov 1', () {
      expect(groupTasks([mk('a', date: '2026-11-01')], DateTime(2026, 10, 31, 8)).keys, [Section.tomorrow]);
    });

    test('empty sections are omitted and order is fixed', () {
      final ts = [mk('n'), mk('l', date: '2026-12-01'), mk('p', date: '2026-10-01'), mk('t', date: '2026-10-15')];
      expect(sections(ts), [Section.past, Section.today, Section.later, Section.noDate]);
      expect(groupTasks([], now), isEmpty);
    });

    test('completed: 24h cutoff and show-all toggle', () {
      final recent = mk('r', done: true, doneAt: now.subtract(const Duration(hours: 23, minutes: 59)));
      final old = mk('o', done: true, doneAt: now.subtract(const Duration(hours: 24, minutes: 1)));
      expect(groupTasks([recent, old], now)[Section.completed]!.map((t) => t.id), ['r']);
      expect(groupTasks([recent, old], now, showAllCompleted: true)[Section.completed]!.map((t) => t.id), ['r', 'o']);
    });

    test('done tasks leave their date section', () {
      final t = mk('a', date: '2026-10-14', done: true, doneAt: now);
      expect(groupTasks([t], now).keys, [Section.completed]);
    });

    test('sorted by start date/time within a section', () {
      final ts = [mk('b', date: '2026-10-15', time: '15:00'), mk('a', date: '2026-10-15', time: '09:00')];
      expect(groupTasks(ts, now)[Section.today]!.map((t) => t.id), ['a', 'b']);
    });
  });

  group('startInstant / isDue', () {
    test('date + time, else 09:00', () {
      expect(startInstant(mk('a', date: '2026-10-15', time: '10:30')), DateTime(2026, 10, 15, 10, 30));
      expect(startInstant(mk('a', date: '2026-10-15')), DateTime(2026, 10, 15, 9));
      expect(startInstant(mk('a')), isNull);
    });
    test('due only once the instant has passed', () {
      final t = mk('a', date: '2026-10-15', time: '12:00', reminder: true);
      expect(isDue(t, DateTime(2026, 10, 15, 11, 59)), isFalse);
      expect(isDue(t, DateTime(2026, 10, 15, 12, 0)), isTrue);
      expect(isDue(t, DateTime(2026, 10, 16)), isTrue);
    });
    test('not due without reminder, when done, or without a date', () {
      expect(isDue(mk('a', date: '2026-10-01'), now), isFalse);
      expect(isDue(mk('a', date: '2026-10-01', reminder: true, done: true), now), isFalse);
      expect(isDue(mk('a', reminder: true), now), isFalse);
    });
    test('date-only reminder is due from 09:00', () {
      final t = mk('a', date: '2026-10-15', reminder: true);
      expect(isDue(t, DateTime(2026, 10, 15, 8, 59)), isFalse);
      expect(isDue(t, DateTime(2026, 10, 15, 9, 0)), isTrue);
    });
  });

  group('reminderInstants', () {
    test('start and next-day 09:00', () {
      final r = reminderInstants(mk('a', date: '2026-10-20', time: '10:00', reminder: true), now);
      expect(r.map((e) => e.at), [DateTime(2026, 10, 20, 10), DateTime(2026, 10, 21, 9)]);
      expect(r.map((e) => e.id), [notificationId('a', 0), notificationId('a', 1)]);
    });
    test('date-only reminder starts at 09:00', () {
      final r = reminderInstants(mk('a', date: '2026-10-20', reminder: true), now);
      expect(r.first.at, DateTime(2026, 10, 20, 9));
    });
    test('next day crosses month end', () {
      final r = reminderInstants(mk('a', date: '2026-10-31', time: '10:00', reminder: true), now);
      expect(r.last.at, DateTime(2026, 11, 1, 9));
    });
    test('past instants are skipped', () {
      final t = mk('a', date: '2026-10-15', time: '10:00', reminder: true); // start passed, next day ahead
      expect(reminderInstants(t, now).map((e) => e.at), [DateTime(2026, 10, 16, 9)]);
      expect(reminderInstants(mk('a', date: '2026-10-01', reminder: true), now), isEmpty);
    });
    test('nothing for done, reminder-off, or undated tasks', () {
      expect(reminderInstants(mk('a', date: '2026-10-20', reminder: true, done: true), now), isEmpty);
      expect(reminderInstants(mk('a', date: '2026-10-20'), now), isEmpty);
      expect(reminderInstants(mk('a', reminder: true), now), isEmpty);
    });
  });

  group('notification ids', () {
    test('FNV-1a is pinned to published test vectors', () {
      expect(fnv1a(''), 0x811c9dc5);
      expect(fnv1a('a'), 0xe40c292c);
      expect(fnv1a('foobar'), 0xbf9cf968);
    });
    test('id = hash*2 + slot, positive int32, slots differ', () {
      final a = notificationId('a', 0), b = notificationId('a', 1);
      expect(a, (0xe40c292c * 2) & 0x7FFFFFFF);
      expect(b, a + 1);
      expect(a, inInclusiveRange(0, 0x7FFFFFFF));
      expect(notificationId('some-long-firestore-id-123', 1), inInclusiveRange(0, 0x7FFFFFFF));
    });
  });

  test('knownPeople: distinct, most used first, ties alphabetical', () {
    final ts = [mk('1', people: ['Bo', 'Ann']), mk('2', people: ['Bo']), mk('3', people: ['Cy', 'Bo']), mk('4', people: ['Cy'])];
    expect(knownPeople(ts), ['Bo', 'Cy', 'Ann']);
    expect(knownPeople([]), isEmpty);
  });
}
