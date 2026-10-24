import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/ui/toast.dart';

/// Read a message aloud with the phone's own voice — the web's `speak()` in
/// ChatMessage.jsx, which uses the browser's speechSynthesis.
///
/// One engine for the whole app, so starting a message cancels the one
/// already playing (the web calls `synth.cancel()` first). Tapping the
/// message that is CURRENTLY being read stops it instead — on a phone the
/// button is the only way to make it stop.
class ReadAloud {
  ReadAloud._();

  static final _tts = FlutterTts();
  static bool _ready = false;

  /// The text being read, or null — lets a button show its "stop" state.
  static final speaking = ValueNotifier<String?>(null);

  static Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    await _tts.awaitSpeakCompletion(false);
    _tts.setCompletionHandler(() => speaking.value = null);
    _tts.setCancelHandler(() => speaking.value = null);
    _tts.setErrorHandler((_) => speaking.value = null);
  }

  static Future<void> toggle(String text) async {
    await _init();
    if (speaking.value == text) {
      await _tts.stop();
      speaking.value = null;
      return;
    }
    await _tts.stop();
    final plain = _plain(text);
    if (plain.isEmpty) return;
    speaking.value = text;
    final result = await _tts.speak(plain);
    // 1 = started. Anything else: no voice engine on this phone.
    if (result != 1) {
      speaking.value = null;
      Toast.error("This phone can't read messages aloud.");
    }
  }

  static Future<void> stop() async {
    if (!_ready) return;
    await _tts.stop();
    speaking.value = null;
  }

  /// Markdown punctuation read aloud is noise ("asterisk asterisk").
  static String _plain(String md) => md
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[*_`#>~]'), '')
      .replaceAll(RegExp(r'^\s*[-+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
