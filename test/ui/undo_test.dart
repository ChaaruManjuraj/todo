import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/app.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/ui/animated_task_list.dart';
import 'package:todo/ui/clock.dart';
import 'package:todo/ui/theme_controller.dart';

final t0 = DateTime.utc(2026, 10, 1);
final fakeNow = DateTime(2026, 10, 15, 11, 0);

class SpyRepo extends MemoryRepo {
  SpyRepo(super.initial);
  int deletes = 0;
  @override
  Future<void> delete(String id) {
    deletes++;
    return super.delete(id);
  }
}

Task mk(String id, {bool done = false}) => Task(
    id: id, name: 'task $id', startDate: done ? null : '2026-10-15', done: done, doneAt: done ? fakeNow : null, createdAt: t0, updatedAt: t0);

Future<SpyRepo> pumpHome(WidgetTester tester, List<Task> tasks, {Size size = const Size(1200, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final repo = SpyRepo(tasks);
  await tester.pumpWidget(TodoApp(repo: repo, clock: Clock(now: () => fakeNow, tick: null), theme: await ThemeController.load()));
  await tester.pump();
  return repo;
}

Future<void> deleteViaPanel(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
}

Future<void> expireSnackbar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  group('completing', () {
    testWidgets('moves the task to Completed, and Undo moves it back', (tester) async {
      await pumpHome(tester, [mk('a')]);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Completed'), findsNothing);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      expect(find.text('Completed "task a"'), findsOneWidget); // the snackbar

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Completed'), findsNothing);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('stays completed once the snackbar expires', (tester) async {
      final repo = await pumpHome(tester, [mk('a')]);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await expireSnackbar(tester);
      expect(find.text('Completed'), findsOneWidget);
      expect((await repo.watch().first).single.done, isTrue);
      expect(repo.deletes, 0);
    });

    testWidgets('unchecking a completed task restores it without a snackbar', (tester) async {
      await pumpHome(tester, [mk('c', done: true)]);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('Completed'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('deleting', () {
    testWidgets('hides the row at once and Undo brings it back without deleting', (tester) async {
      final repo = await pumpHome(tester, [mk('a')]);
      await deleteViaPanel(tester, 'task a');
      expect(find.text('task a'), findsNothing);
      expect(find.text('Deleted "task a"'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('task a'), findsOneWidget);
      await expireSnackbar(tester);
      expect(repo.deletes, 0);
      expect(find.text('task a'), findsOneWidget);
    });

    testWidgets('is deleted once, when the snackbar times out', (tester) async {
      final repo = await pumpHome(tester, [mk('a')]);
      await deleteViaPanel(tester, 'task a');
      expect(repo.deletes, 0);
      await expireSnackbar(tester);
      expect(repo.deletes, 1);
      expect(find.text('Nothing to do'), findsOneWidget);
    });

    testWidgets('a second delete commits the first one', (tester) async {
      final repo = await pumpHome(tester, [mk('a'), mk('b')]);
      await deleteViaPanel(tester, 'task a');
      await deleteViaPanel(tester, 'task b');
      expect(repo.deletes, 1);
      await expireSnackbar(tester);
      expect(repo.deletes, 2);
    });
  });

  group('AnimatedTaskList', () {
    Widget list(List<String> keys) => MaterialApp(
          home: Scaffold(
            body: AnimatedTaskList(entries: [for (final k in keys) ListEntry(k, SizedBox(key: Key('box-$k'), height: 50, child: Text(k)))]),
          ),
        );
    double h(WidgetTester t, String k) => t.getSize(find.byKey(Key('box-$k'))).height;

    testWidgets('removed rows stay while they collapse, then go', (tester) async {
      await tester.pumpWidget(list(['A', 'B']));
      await tester.pumpWidget(list(['B']));
      await tester.pump();
      expect(find.text('A'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('new rows grow in', (tester) async {
      await tester.pumpWidget(list(['A']));
      await tester.pumpWidget(list(['A', 'B']));
      await tester.pump(const Duration(milliseconds: 50));
      final mid = tester.getSize(find.ancestor(of: find.byKey(const Key('box-B')), matching: find.byType(SizeTransition)).first).height;
      expect(mid, inExclusiveRange(0, 50));
      await tester.pumpAndSettle();
      expect(h(tester, 'B'), 50);
    });

    testWidgets('a removed row keeps its place between its neighbours', (tester) async {
      await tester.pumpWidget(list(['A', 'B', 'C']));
      await tester.pumpWidget(list(['A', 'C']));
      await tester.pump(const Duration(milliseconds: 50));
      final ys = [for (final k in ['A', 'B', 'C']) tester.getTopLeft(find.text(k)).dy];
      expect(ys, orderedEquals([...ys]..sort()));
    });

    testWidgets('with reduce-motion on, changes apply in a single frame', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(list(['A', 'B']));
      await tester.pumpWidget(list(['B', 'C']));
      await tester.pump();
      expect(find.text('A'), findsNothing);
      expect(h(tester, 'C'), 50);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
