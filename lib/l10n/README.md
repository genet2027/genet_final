# Localization (i18n) – Translation File Structure

This app uses **Flutter’s built-in localization** (`flutter_localizations` + ARB files).  
In Flutter there are no separate `en.json` / `he.json` files; the equivalent is:

| If you had (e.g. React) | In this Flutter app |
|-------------------------|----------------------|
| `en.json`               | `lib/l10n/app_en.arb` |
| `he.json`               | `lib/l10n/app_he.arb` |
| `ar.json`               | `lib/l10n/app_ar.arb` |

ARB (Application Resource Bundle) is key-value JSON. Add or edit keys in the `.arb` files, then run **`flutter gen-l10n`** to regenerate the Dart getters. Use `AppLocalizations.of(context)!.keyName` in code.

---

## File layout

```
lib/l10n/
├── README.md                 # This file
├── app_en.arb                # English (template) ← same role as en.json
├── app_he.arb                # Hebrew             ← same role as he.json
├── app_ar.arb                # Arabic
├── app_localizations.dart    # Generated (do not edit)
├── app_localizations_en.dart
├── app_localizations_he.dart
└── app_localizations_ar.dart
```

---

## Analysis of Home screen (before redesign)

- **Location:** `lib/screens/home_screen.dart`
- **Content:** Protection status, app title, subtitle, “Parent Dashboard” button.
- **Strings:** All moved to ARB: `appTitle`, `homeSubtitle`, `protectionActive`, `buttonParentDashboard`, plus nav labels and `lastUpdatedLabel`.
- **RTL:** Handled by `MaterialApp.locale` (no hardcoded `Directionality` on Home). When locale is Hebrew or Arabic, the layout mirrors (AppBar, bottom nav, icons).
- **Language switcher:** `LanguageSwitcher` in AppBar; dates/numbers via `LocaleFormatters.of(context)`.

---

## Keys used on Home and navigation

| Key | Usage |
|-----|--------|
| `appTitle` | App / home title |
| `homeSubtitle` | Home subtitle |
| `protectionActive` | Protection status badge |
| `buttonParentDashboard` | Parent dashboard button |
| `homeNavLabel` | Bottom nav: Home |
| `contentNavLabel` | Bottom nav: Content |
| `lastUpdatedLabel` | “Last updated” + locale-formatted date |
| `buttonSelectLanguage` / `chooseLanguage` / `language*` | Language switcher |

Other keys: `childHomeTitle`, `backToRoleSelect`, `scheduleTomorrow`, `blockedAppsAndTimes`, `contentLibraryTitle`, etc.

---

## Usage in code

- **Strings:** `AppLocalizations.of(context)!.homeSubtitle`
- **RTL:** Do not wrap screens in `Directionality`; use the app locale so menus and layout mirror for Hebrew/Arabic.
- **Dates/numbers:** `LocaleFormatters.of(context).formatDate(date)` etc. in `lib/utils/locale_formatters.dart`.
