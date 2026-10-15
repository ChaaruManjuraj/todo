import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/theme.dart';

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  for (final (name, theme) in [('light', lightTheme), ('dark', darkTheme)]) {
    final c = theme.colorScheme;

    // Text and icon pairs the UI actually draws: needs 4.5:1 (WCAG AA, normal text).
    final text = <String, (Color, Color)>{
      'body on page': (c.onSurface, c.surface),
      'body on panel': (c.onSurface, c.surfaceContainerLow),
      'muted on page': (c.onSurfaceVariant, c.surface),
      'muted on panel': (c.onSurfaceVariant, c.surfaceContainerLow),
      'muted on field': (c.onSurfaceVariant, theme.inputDecorationTheme.fillColor!),
      'muted on raised surface (menu, switch track)': (c.onSurfaceVariant, c.surfaceContainerHighest),
      'accent on page': (c.primary, c.surface),
      'accent on panel': (c.primary, c.surfaceContainerLow),
      'text on accent button': (c.onPrimary, c.primary),
      'Due pill': (c.onPrimaryContainer, c.primaryContainer),
      'people chip': (c.onSecondaryContainer, c.secondaryContainer),
      'error on page': (c.error, c.surface),
      'error on panel': (c.error, c.surfaceContainerLow),
      'error banner': (c.onErrorContainer, c.errorContainer),
      'snackbar text': (c.onInverseSurface, c.inverseSurface),
      'snackbar Undo': (c.inversePrimary, c.inverseSurface),
    };
    for (final e in text.entries) {
      test('$name: ${e.key} is at least 4.5:1', () {
        expect(contrast(e.value.$1, e.value.$2), greaterThanOrEqualTo(4.5));
      });
    }

    // Boundaries of controls (switch off-state outline, empty check circle) need 3:1 (WCAG 1.4.11).
    test('$name: control outlines are at least 3:1 against the page', () {
      expect(contrast(c.outline, c.surface), greaterThanOrEqualTo(3));
      expect(contrast(c.onSurfaceVariant, c.surface), greaterThanOrEqualTo(3)); // the empty check circle
    });

    test('$name: the filled check circle stands out from the page (3:1)', () {
      expect(contrast(c.primary, c.surface), greaterThanOrEqualTo(3));
    });
  }

  test('the two themes use the same type scale (sizes never change with brightness)', () {
    for (final s in ['bodyLarge', 'bodyMedium', 'bodySmall', 'titleLarge', 'labelSmall']) {
      double? size(ThemeData t) => {
            'bodyLarge': t.textTheme.bodyLarge,
            'bodyMedium': t.textTheme.bodyMedium,
            'bodySmall': t.textTheme.bodySmall,
            'titleLarge': t.textTheme.titleLarge,
            'labelSmall': t.textTheme.labelSmall,
          }[s]!.fontSize;
      expect(size(lightTheme), size(darkTheme), reason: s);
    }
  });

  test('nothing in the type scale is smaller than 12', () {
    final t = lightTheme.textTheme;
    for (final s in [t.bodySmall, t.bodyMedium, t.bodyLarge, t.labelSmall, t.labelMedium, t.labelLarge, t.titleSmall, t.titleMedium, t.titleLarge]) {
      expect(s!.fontSize, greaterThanOrEqualTo(12));
    }
  });
}
