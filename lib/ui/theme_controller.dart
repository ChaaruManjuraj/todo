import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'themeMode';

/// Defaults to following the system.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController._(this._prefs, super.mode);

  final SharedPreferences _prefs;

  static Future<ThemeController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    return ThemeController._(prefs, ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system));
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    await _prefs.setString(_key, mode.name);
  }
}
