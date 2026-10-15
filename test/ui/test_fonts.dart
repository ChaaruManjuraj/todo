import 'dart:io';

import 'package:flutter/services.dart';

/// Widget tests draw every glyph as a solid block (the "Ahem" font) unless fonts are loaded. Load the real app font and
/// the Material icon font so screenshots and contrast checks see what users see.
Future<void> loadAppFonts() async {
  final figtree = FontLoader('Figtree')..addFont(rootBundle.load('assets/fonts/Figtree-Variable.ttf'));
  await figtree.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
  await loader.load();
}
