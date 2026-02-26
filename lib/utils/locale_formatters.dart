import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Format dates and numbers according to the current locale.
/// Use [LocaleFormatters.of(context)] for locale-aware formatting.
class LocaleFormatters {
  LocaleFormatters._();

  static LocaleFormatters of(BuildContext context) {
    return LocaleFormatters._();
  }

  /// Format a [DateTime] using the locale from [context].
  String formatDate(BuildContext context, DateTime date) {
    final locale = Localizations.localeOf(context);
    final tag = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    return DateFormat.yMMMd(tag).format(date);
  }

  /// Format a time (hour:minute) using the locale from [context].
  String formatTime(BuildContext context, DateTime time) {
    final locale = Localizations.localeOf(context);
    final tag = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    return DateFormat.Hm(tag).format(time);
  }

  /// Format a number using the locale from [context].
  String formatNumber(BuildContext context, num value) {
    final locale = Localizations.localeOf(context);
    final tag = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    return NumberFormat.decimalPattern(tag).format(value);
  }
}
