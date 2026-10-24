import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light / System / Dark — the sidebar's THEME segmented control on the web
/// (`appearance/ThemeSegmented.jsx`). Persisted across launches.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) : _mode = _read(_prefs);

  static const _key = 'ck:theme';

  final SharedPreferences _prefs;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  static ThemeMode _read(SharedPreferences prefs) => switch (prefs.getString(_key)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  void setMode(ThemeMode mode) {
    if (mode == _mode) return;
    _mode = mode;
    _prefs.setString(_key, mode.name);
    notifyListeners();
  }
}
