# שלב 1 — מיפוי כפילויות (תיעוד)

## 1. מסכים (Screens)

| מסך | מיקום | בשימוש? | הערות |
|-----|--------|---------|--------|
| ContentLibraryScreen | screens/content_library_screen.dart | כן | parent_dashboard_tab, child_home_screen |
| ChildHomeScreen | screens/child_home_screen.dart | כן | role_select_screen |
| ParentShell | screens/parent_shell.dart | כן | ניווט אחרי PIN |
| ParentDashboardTab | screens/parent_dashboard_tab.dart | כן | בתוך ParentShell |
| NightModeSettingsScreen | screens/night_mode_settings_screen.dart | כן | settings_screen |
| SleepLockScreen | screens/sleep_lock_screen.dart | כן | parent_dashboard_tab ("שעות מס ושינה") |
| BlockedAppsScreen | screens/blocked_apps_screen.dart | כן | parent_dashboard_tab |
| BlockedAppsTimesScreen | screens/blocked_apps_times_screen.dart | כן | child_home_screen |
| ChildSettingsScreen | screens/child_settings_screen.dart | כן | parent_dashboard_tab |
| SettingsScreen | screens/settings_screen.dart | כן | ParentShell |
| BackupSupportScreen | screens/backup_support_screen.dart | כן | settings_screen |
| PinLoginScreen | screens/pin_login_screen.dart | כן | main / logout |
| RoleSelectScreen | screens/role_select_screen.dart | כן | main |
| ReportsTab | screens/reports_tab.dart | כן | ParentShell |
| וכו' | … | … | אין מסך כפול עם אותו שם |

**הערה:** SleepLockScreen ו־NightModeSettingsScreen עוסקים שניהם ב"מצב לילה/שינה" אבל נכנסים ממקומות שונים (דשבורד vs הגדרות) ומציגים UI שונה. **לא לאחד** בלי החלטה מפורשת — שניהם בשימוש.

---

## 2. Widgets כפולים

| Widget | מיקום 1 | מיקום 2 | הערות |
|--------|---------|---------|--------|
| **_RoundedCard** | settings_screen.dart | backup_support_screen.dart | **כפול.** דומה מאוד: כרטיס עם icon, title, subtitle, onTap. ב-settings יש גם שימוש עם `child` מותאם (יציאה). אפשר לאחד ל־lib/widgets/rounded_card.dart עם תמיכה ב־child אופציונלי. |

**Widgets פרטיים (_) שלא כפולים:**  
_GridCard (רק parent_dashboard_tab), _MenuCard (רק child_home_screen), _contentCard (רק content_library_screen), _YomiCard, _ManagementButton, _ChildSettingsButton — כולם בשימוש מקומי אחד.

---

## 3. Models

| Model | מיקום | בשימוש? |
|-------|--------|----------|
| ChildModel | models/child_model.dart | כן (child_settings_screen, content_library_screen, child_home_screen) |
| NightModeConfig | models/night_mode_config.dart | כן |
| ContentTopic, ContentSection, ContentCategoryItem | models/ | לא נמצא שימוש ב־import ב־lib (רק ב־Android?) — **לוודא לפני מחיקה** |

---

## 4. Services / Repositories

| שם | מיקום | בשימוש? |
|----|--------|----------|
| NightModeService | services/night_mode_service.dart | כן |
| NightModeRepository | repositories/night_mode_repository.dart | כן |
| MessagesRepository | repositories/messages_repository.dart | כן (backup_support_screen) |
| ContentRepository (ב־lib) | repositories/content_repository.dart | לא נמצא reference ב־lib — **לוודא** |

---

## 5. מפתחות / Constants כפולים

| קבוע | מופיע ב־ |
|------|-----------|
| genet_sleep_lock_enabled, _start, _end | genet_config, night_mode_repository, sleep_lock_screen, blocked_apps_times_screen |

**המלצה:** להשאיר כמו שזה (מפתחות SharedPreferences) — איחוד לקבוע מרכזי אפשרי אבל דורש החלפת מחרוזות בכל הקבצים. שלב נפרד.

---

## 6. Strings / Labels

- רוב הטקסטים בעברית/אנגלית מופיעים ב־l10n (app_he.arb, app_en.arb) או ישירות במסכים. לא זוהו כפילויות מחרוזות זהות בקבצים שונים שכדאי לאחד בשלב זה.

---

## סיכום לשלב 2 (איחוד בטוח)

1. **איחוד _RoundedCard:** ליצור `lib/widgets/rounded_card.dart` עם API שתומך ב־child אופציונלי (ואם אין child — icon/title/subtitle). לעדכן settings_screen ו־backup_support_screen ל־import מהמקום החדש ולהסיר את ההגדרה הכפולה.
2. **לא למחוק:** SleepLockScreen, NightModeSettingsScreen, content models/repos — עד שלא מאושר ש־ContentRepository וכו' לא בשימוש.
3. **לא לשנות:** שמות קבצים או העברת מסכים לתת־תיקיות (parent/child/content) עד לאחר איחוד ה־Widget ו־build ירוק.
