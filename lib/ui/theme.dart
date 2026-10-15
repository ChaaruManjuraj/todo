import 'package:flutter/material.dart';

ThemeData _build(Brightness b) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6B5C), brightness: b),
    );

final lightTheme = _build(Brightness.light);
final darkTheme = _build(Brightness.dark);
