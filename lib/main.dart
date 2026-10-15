import 'package:flutter/material.dart';

import 'app.dart';
import 'data/memory_repo.dart';
import 'ui/clock.dart';
import 'ui/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(TodoApp(repo: MemoryRepo(), clock: Clock(), theme: await ThemeController.load()));
}
