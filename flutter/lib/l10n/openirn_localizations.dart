import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OpenIrnLanguage {
  fr('fr', 'Français'),
  en('en', 'English'),
  es('es', 'Español'),
  de('de', 'Deutsch');

  final String code;
  final String label;

  const OpenIrnLanguage(this.code, this.label);

  static OpenIrnLanguage fromCode(String code) {
    return OpenIrnLanguage.values.firstWhere(
      (language) => language.code == code,
      orElse: () => OpenIrnLanguage.fr,
    );
  }
}

class OpenIrnLocalizations extends ChangeNotifier {
  static const _preferenceKey = 'openirn.interface_language';
  static final OpenIrnLocalizations instance = OpenIrnLocalizations._();

  OpenIrnLanguage _language = OpenIrnLanguage.fr;
  Map<String, String> _messages = const <String, String>{};
  Map<String, String> _frenchMessages = const <String, String>{};
  Map<String, String> _frenchTextToKey = const <String, String>{};
  final Map<OpenIrnLanguage, Map<String, String>> _catalogCache = {};

  OpenIrnLocalizations._();

  OpenIrnLanguage get language => _language;
  String get languageCode => _language.code;

  Future<void> initialize() async {
    _frenchMessages = await _loadLanguage(OpenIrnLanguage.fr);
    _frenchTextToKey = _buildReverseIndex(_frenchMessages);
    await Future.wait(
      OpenIrnLanguage.values
          .where((language) => language != OpenIrnLanguage.fr)
          .map(_loadLanguage),
    );

    final preferences = await SharedPreferences.getInstance();
    final storedCode =
        preferences.getString(_preferenceKey) ?? OpenIrnLanguage.fr.code;
    await setLanguage(OpenIrnLanguage.fromCode(storedCode), persist: false);
  }

  Future<void> setLanguage(
    OpenIrnLanguage language, {
    bool persist = true,
  }) async {
    final messages = language == OpenIrnLanguage.fr
        ? _frenchMessages
        : _catalogCache[language] ?? await _loadLanguage(language);
    _language = language;
    _messages = messages;
    notifyListeners();

    if (persist) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_preferenceKey, language.code);
    }
  }

  Future<void> toggleLanguage() async {
    final languages = OpenIrnLanguage.values;
    final nextLanguage =
        languages[(languages.indexOf(_language) + 1) % languages.length];
    await setLanguage(nextLanguage);
  }

  String tr(
    String key, {
    String? fallback,
    Map<String, Object?> values = const <String, Object?>{},
  }) {
    var result = _messages[key] ?? _frenchMessages[key] ?? fallback ?? key;
    values.forEach((name, value) {
      result = result.replaceAll('{$name}', value?.toString() ?? '');
    });
    return result;
  }

  /// Transitional helper used while the legacy UI is migrated screen by screen.
  ///
  /// The JSON files keep stable IDs, but this method lets existing widgets pass
  /// their current French literal and still receive a translated value when an
  /// ID already exists for that text. New code should prefer [tr].
  String text(String frenchText) {
    final key = _frenchTextToKey[frenchText.trim()];
    if (key == null) {
      return frenchText;
    }
    return tr(key, fallback: frenchText);
  }

  Future<Map<String, String>> _loadLanguage(OpenIrnLanguage language) async {
    final cached = _catalogCache[language];
    if (cached != null) {
      return cached;
    }
    final raw = await rootBundle.loadString(
      'assets/i18n/${language.code}.json',
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final messages = Map<String, String>.unmodifiable(
      decoded.map((key, value) => MapEntry(key, value?.toString() ?? '')),
    );
    _catalogCache[language] = messages;
    return messages;
  }

  Map<String, String> _buildReverseIndex(Map<String, String> messages) {
    final result = <String, String>{};
    for (final entry in messages.entries) {
      final value = entry.value.trim();
      if (value.isEmpty || result.containsKey(value)) {
        continue;
      }
      result[value] = entry.key;
    }
    return Map.unmodifiable(result);
  }

  static OpenIrnLocalizations of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<OpenIrnLocalizationScope>();
    return scope?.controller ?? OpenIrnLocalizations.instance;
  }
}

class OpenIrnLocalizationScope extends InheritedNotifier<OpenIrnLocalizations> {
  final OpenIrnLocalizations controller;

  const OpenIrnLocalizationScope({
    required this.controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  @override
  bool updateShouldNotify(OpenIrnLocalizationScope oldWidget) {
    return oldWidget.controller != controller;
  }
}

extension OpenIrnLocalizationContext on BuildContext {
  OpenIrnLocalizations get i18n => OpenIrnLocalizations.of(this);

  String tr(
    String key, {
    String? fallback,
    Map<String, Object?> values = const <String, Object?>{},
  }) {
    return i18n.tr(key, fallback: fallback, values: values);
  }

  String trText(String frenchText) => i18n.text(frenchText);
}
