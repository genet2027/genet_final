import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/language_provider.dart';

/// Reusable language switcher: an icon button that opens a bottom sheet
/// to choose English, Hebrew, or Arabic. Use in AppBar actions or anywhere.
class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({
    super.key,
    this.icon,
    this.tooltip,
  });

  final IconData? icon;
  final String? tooltip;

  static void showPicker(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final languageProvider = context.read<LanguageProvider>();

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.chooseLanguage,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(l10n.languageEnglish),
              onTap: () {
                languageProvider.setLocale(const Locale('en'));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(l10n.languageHebrew),
              onTap: () {
                languageProvider.setLocale(const Locale('he'));
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(l10n.languageArabic),
              onTap: () {
                languageProvider.setLocale(const Locale('ar'));
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      icon: Icon(icon ?? Icons.language),
      tooltip: tooltip ?? l10n.buttonSelectLanguage,
      onPressed: () => showPicker(context),
    );
  }
}
