import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/app.dart';
import 'package:todo/auth/auth_service.dart';
import 'package:todo/data/memory_repo.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/ui/clock.dart';
import 'package:todo/ui/theme_controller.dart';

class FakeAuth implements AuthService {
  final _c = StreamController<String?>.broadcast();
  Object? failWith;
  int signIns = 0, signOuts = 0;

  void emit(String? uid) => _c.add(uid);

  @override
  Stream<String?> uid() => _c.stream;

  @override
  Future<void> signIn() async {
    signIns++;
    if (failWith != null) throw failWith!;
    emit('alice');
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    emit(null);
  }
}

final t0 = DateTime.utc(2026, 10, 1);

void main() {
  late FakeAuth auth;
  late Map<String, MemoryRepo> repos;

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    repos = {
      'alice': MemoryRepo([Task(id: 'a', name: "alice's task", createdAt: t0, updatedAt: t0)]),
      'bob': MemoryRepo([Task(id: 'b', name: "bob's task", createdAt: t0, updatedAt: t0)]),
    };
    auth = FakeAuth();
    await tester.pumpWidget(TodoApp(
      clock: Clock(now: () => DateTime(2026, 10, 15), tick: null),
      theme: await ThemeController.load(),
      auth: auth,
      repoFor: (uid) => repos[uid]!,
    ));
  }

  testWidgets('shows a spinner until auth state is known, then the sign-in screen', (tester) async {
    await pump(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    auth.emit(null);
    await tester.pump();
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Tasks'), findsNothing);
  });

  testWidgets('signing in shows that user\'s tasks', (tester) async {
    await pump(tester);
    auth.emit(null);
    await tester.pump();
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(auth.signIns, 1);
    expect(find.text("alice's task"), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);
  });

  testWidgets('an already signed-in user skips the sign-in screen', (tester) async {
    await pump(tester);
    auth.emit('bob');
    await tester.pumpAndSettle();
    expect(find.text("bob's task"), findsOneWidget);
    expect(find.text("alice's task"), findsNothing);
  });

  testWidgets('a failed sign-in shows the error and lets you retry', (tester) async {
    await pump(tester);
    auth.emit(null);
    await tester.pump();
    auth.failWith = 'network down';
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(find.textContaining('network down'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton)).onPressed, isNotNull);
  });

  testWidgets('Sign out in the menu returns to the sign-in screen', (tester) async {
    await pump(tester);
    auth.emit('alice');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<Object>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOuts, 1);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('switching accounts shows the new user\'s data, never the old one\'s', (tester) async {
    await pump(tester);
    auth.emit('alice');
    await tester.pumpAndSettle();
    expect(find.text("alice's task"), findsOneWidget);
    auth.emit('bob');
    await tester.pumpAndSettle();
    expect(find.text("bob's task"), findsOneWidget);
    expect(find.text("alice's task"), findsNothing);
  });
}
