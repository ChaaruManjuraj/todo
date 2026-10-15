// Runs on a device against the Firestore + Auth emulators, with the real firestore.rules.
//   firebase emulators:exec --only firestore,auth --project todo-ba12a \
//     "adb reverse tcp:8085 tcp:8085 && adb reverse tcp:9099 tcp:9099 && \
//      flutter test integration_test/firestore_repo_test.dart -d <device> --dart-define=EMULATOR_HOST=LOCALHOST"
// Why LOCALHOST: FlutterFire rewrites the exact string "localhost" to 10.0.2.2, which only exists inside the Android
// emulator. A different spelling skips the rewrite and resolves to the phone's loopback, which adb reverse tunnels
// to this machine. (A LAN address doesn't work: Android 17 blocks apps from local-network connections.)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:todo/data/firestore_repo.dart';
import 'package:todo/domain/task.dart';
import 'package:todo/firebase_options.dart';

Task mk(String id, {String name = 'Buy milk', bool done = false}) {
  final now = DateTime.now().toUtc();
  return Task(id: id, name: name, startDate: '2026-10-15', startTime: '10:00', people: ['Ann'], reminder: true, done: done, createdAt: now, updatedAt: now);
}

const emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String uid;
  late FirestoreRepo repo;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8085);
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    uid = (await FirebaseAuth.instance.signInAnonymously()).user!.uid;
    repo = FirestoreRepo(uid);
  });

  Future<List<Task>> next(bool Function(List<Task>) ready) => repo.watch().firstWhere(ready).timeout(const Duration(seconds: 10));

  testWidgets('upsert shows up in watch with every field intact', (t) async {
    await repo.upsert(mk('t1'));
    final got = (await next((l) => l.any((x) => x.id == 't1'))).firstWhere((x) => x.id == 't1');
    expect(got.name, 'Buy milk');
    expect([got.startDate, got.startTime], ['2026-10-15', '10:00']);
    expect(got.people, ['Ann']);
    expect(got.reminder, isTrue);
  });

  testWidgets('updatedAt is stamped by the server, createdAt is kept', (t) async {
    final local = mk('t2').copyWith(createdAt: DateTime.utc(2020, 1, 1), updatedAt: DateTime.utc(2020, 1, 1));
    await repo.upsert(local);
    final got = (await next((l) => l.any((x) => x.id == 't2'))).firstWhere((x) => x.id == 't2');
    expect(got.createdAt, DateTime.utc(2020, 1, 1));
    expect(got.updatedAt.isAfter(DateTime.utc(2025)), isTrue, reason: 'server time, not the 2020 value we sent');
  });

  testWidgets('upserting the same id replaces the task', (t) async {
    await repo.upsert(mk('t3', name: 'old'));
    await repo.upsert(mk('t3', name: 'new', done: true));
    final got = (await next((l) => l.any((x) => x.id == 't3' && x.name == 'new'))).firstWhere((x) => x.id == 't3');
    expect(got.done, isTrue);
  });

  testWidgets('delete removes the task', (t) async {
    await repo.upsert(mk('t4'));
    await next((l) => l.any((x) => x.id == 't4'));
    await repo.delete('t4');
    final after = await next((l) => !l.any((x) => x.id == 't4'));
    expect(after.any((x) => x.id == 't4'), isFalse);
  });

  testWidgets("the rules keep one user out of another user's tasks", (t) async {
    final other = FirebaseFirestore.instance.collection('users/someone-else/tasks');
    await expectLater(other.get(), throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied')));
  });

  testWidgets('the rules reject a malformed task', (t) async {
    await expectLater(repo.upsert(mk('bad', name: 'x' * 201)), throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied')));
  });
}
