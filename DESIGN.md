# Design

Visual system for the TODO app. The strategy, users and principles live in [PRODUCT.md](PRODUCT.md); this file is how it looks. The tokens are implemented in `lib/ui/theme.dart` and checked by `test/ui/theme_contrast_test.dart`.

## Visual theme

Mood: a Sunday-morning kitchen table: a clay mug, soft daylight, a short handwritten list.

Color strategy: **restrained**. One clay accent (OKLCH hue 34) on near-neutral surfaces. Warmth comes from the accent and the typeface, not from a tinted page (no cream or sand backgrounds). Light is the daylight desk; dark is the evening lamp, a warm near-black rather than pure black. Both follow the system setting by default.

## Color

Accent is used for the primary action, the checked state, the quick-add `+`, focus rings and the Due pill. Never for decoration and never at full strength on inactive things.

| Role | Light | Dark | Used for |
|---|---|---|---|
| surface (page) | `#FFFFFF` | `#161211` | app background |
| surfaceContainerLow (panel) | `#FBF5F4` | `#1B1615` | detail panel, bottom sheet, dialogs |
| field fill | `#FFFFFF` | `#201A19` | text fields |
| outlineVariant | `#DED5D3` | `#433B39` | hairlines, field borders |
| onSurface (ink) | `#27201E` | `#EDE6E4` | text |
| onSurfaceVariant (muted) | `#625856` | `#B5ABA9` | metadata, section headers, hints |
| primary (clay) | `#BC452B` | `#F3947E` | accent |
| onPrimary | `#FFFFFF` | `#250F09` | text on accent |
| primaryContainer | `#FFDFD7` | `#58271C` | Due pill, empty-state mark |
| secondaryContainer | `#F3E8E6` | `#342C2A` | people chips |
| error | `#B7191C` | `#FF958A` | validation, Delete |
| inverseSurface / inversePrimary | `#27201E` / `#F3947E` | `#EDE6E4` / `#A9371D` | snackbar and its Undo |

Every text pair is at least 4.5:1 (lowest: accent on the warm panel, 4.84:1). Control boundaries are at least 3:1. Do not reduce contrast with opacity; a done task is shown with a strikethrough and the muted color, not by fading.

## Typography

One family: **Figtree** (SIL OFL, bundled in `assets/fonts`, variable `wght` axis), so every platform renders the same. A fixed scale, no fluid sizing.

| Style | Size / weight | Use |
|---|---|---|
| displaySmall | 28 / 650 | sign-in headline |
| titleLarge | 22 / 650 | app bar title |
| titleMedium | 16 / 600 | empty-state title |
| titleSmall | 14 / 650 | section headers (sentence case, muted) |
| bodyLarge | 16 / 480 | task names, fields |
| bodyMedium | 14 / 450 | supporting text |
| bodySmall | 13 / 450 | task metadata (date, time) |
| labelLarge | 14 / 600 | buttons |
| labelSmall | 12 / 600 | Due pill, people chips (the minimum size) |

## Shape, space, layout

- Radius 12 for fields, buttons, menus; 28 for the quick-add pill; full pill for chips and the Due label; 20 on the bottom sheet's top corners.
- No cards. A task is a row: round check circle, name, quiet metadata. Hover and press show a soft rounded area, not a border.
- The list and quick-add stop growing at 680dp so rows stay easy to scan. Section headers align with the check circles (28dp).
- Below 720dp the detail view is a bottom sheet; at or above it, a 380dp side panel on the soft panel surface that fills the height.
- Minimum touch target 48dp everywhere. The whole people chip removes the person.

## Components

- **Check circle**: a standard checkbox with a circular shape; clay when checked.
- **Due pill**: `primaryContainer` with `onPrimaryContainer` text; appears only when a reminder's time has passed.
- **People chip**: `secondaryContainer`, small, quiet.
- **Quick-add**: a bordered pill with a clay `+`; Enter adds, `N` focuses it.
- **Snackbar**: floating, inverse colors, Undo in the inverse accent.
- **Empty state**: a clay-tinted circle with a check, a short title, and one line that teaches how to add a task (mentions `N` only where there is a keyboard).
- **Offline chip**: "offline · N pending", shown only after 3 seconds of waiting.

## Motion

Motion explains a change and nothing else. 200ms, ease-out-quart. Rows fade and expand in when added, and fade and collapse out when removed or moved to another section. The check circle uses the standard checkbox animation. With the system's reduce-motion setting on, every duration is zero and changes apply in one frame (`motion()` in `lib/ui/animated_task_list.dart`). No page-load choreography.

## Do / don't

- Do keep one accent. Do keep section headers sentence case and muted.
- Don't add cards, side-stripe borders, gradient text, or uppercase tracked labels.
- Don't use opacity to de-emphasize text; use the muted color.
- Don't shrink a touch target below 48dp to fit more in.
- Don't tint the page background toward cream.
