import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/session_store.dart';
import 'core/theme/skins.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // Restore runs in the background; the router shows the splash until it
  // settles, then redirects to /login or home.
  final auth = AuthController(SessionStore(prefs))..restore();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => ThemeController(prefs)),
        ChangeNotifierProvider(create: (_) => SkinController(prefs)),
      ],
      child: const CreativeKluxApp(),
    ),
  );
}
