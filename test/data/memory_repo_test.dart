import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/domain/task.dart';

final t0 = DateTime.utc(2026, 10, 1);
Task mk(String id, [String name = 'x']) => Task(id: id, name: name, createdAt: t0, updatedAt: t0);

void main() {
  final clock = DateTime.utc(2026, 10, 15, 12);

  test('watch replays current state to a new listener', () async {
    final r = MemoryRepo([mk('a')]);
    expect((await r.watch().first).map((t) => t.id), ['a']);
  });

  test('upsert emits and stamps updatedAt', () async {
    final r = MemoryRepo([], () => clock);
    final events = <List<Task>>[];
    final sub = r.watch().listen(events.add);
    await Future<void>.delayed(Duration.zero);
    await r.upsert(mk('a'));
    await Future<void>.delayed(Duration.zero);
    expect(events.length, 2);
    expect(events[0], isEmpty);
    expect(events[1].single.updatedAt, clock);
    await sub.cancel();
  });

  test('upsert replaces the task with the same id', () async {
    final r = MemoryRepo([mk('a', 'old')]);
    await r.upsert(mk('a', 'new'));
    final l = await r.watch().first;
    expect(l.single.name, 'new');
  });

  test('delete emits without the task', () async {
    final r = MemoryRepo([mk('a'), mk('b')]);
    await r.delete('a');
    expect((await r.watch().first).map((t) => t.id), ['b']);
  });

  test('two listeners both get updates; a cancelled one does not', () async {
    final r = MemoryRepo();
    final a = <int>[], b = <int>[];
    final sa = r.watch().listen((l) => a.add(l.length));
    final sb = r.watch().listen((l) => b.add(l.length));
    await Future<void>.delayed(Duration.zero);
    await sb.cancel();
    await r.upsert(mk('x'));
    await Future<void>.delayed(Duration.zero);
    expect(a, [0, 1]);
    expect(b, [0]);
    await sa.cancel();
  });

  test('emitted lists are unmodifiable and pending is 0', () async {
    final r = MemoryRepo([mk('a')]);
    final l = await r.watch().first;
    expect(() => l.add(mk('b')), throwsUnsupportedError);
    expect(r.pending.value, 0);
  });
}
