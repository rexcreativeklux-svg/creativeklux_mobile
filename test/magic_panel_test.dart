import 'package:creativeklux/core/storage/session_store.dart';
import 'package:creativeklux/core/theme/app_theme.dart';
import 'package:creativeklux/features/auth/auth_controller.dart';
import 'package:creativeklux/features/editor/magic_panel/magic_history_api.dart';
import 'package:creativeklux/features/editor/magic_panel/magic_media_panel.dart';
import 'package:creativeklux/features/editor/magic_panel/magic_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Payloads must match the web's MAGIC_STUDIO_CONFIGS[...].generate as the
/// editor's MagicToolTab drives it (no variations chip → 1, no Brand chip, no
/// description box).
void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  // Smoke test: every tab and every option chooser lays out in a 300px column
  // without overflow (the editor's side panel; the phone sheet is wider).
  testWidgets('panel renders every tab and chooser at 300px', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthController(SessionStore(await SharedPreferences.getInstance()));
    await tester.binding.setSurfaceSize(const Size(300, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MagicMediaPanel(
              onInsertImage: (_) async {},
              onInsertVideo: (_) async {},
              selectedImageSrc: () => null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (final tab in magicTabs) {
      final tabLabel = find.text(tab.label).first;
      await tester.ensureVisible(tabLabel);
      await tester.tap(tabLabel);
      await tester.pump();
      final tool = tab.tool;
      // Kept-alive tabs share labels ("Aspect ratio", "History"), so look only
      // inside the active one.
      Finder inTab(String text) =>
          find.descendant(of: find.byKey(ValueKey(tab.tool ?? tab.id)), matching: find.text(text));
      if (tool == null) {
        expect(inTab('Generate ${tab.noun}'), findsOneWidget);
        continue;
      }
      for (final option in magicToolConfigs[tool]!.optionRows) {
        final row = inTab(option.label);
        await tester.scrollUntilVisible(
          row,
          150,
          scrollable: find.descendant(of: find.byKey(ValueKey(tool)), matching: find.byType(Scrollable)).first,
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pump();
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pump();
      }
      // Back to the top — the Generate/History switch has scrolled out of the cache.
      await tester.drag(find.byKey(ValueKey(tool)), const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.tap(inTab('History'));
      await tester.pump();
      await tester.tap(inTab('Generate'));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });

  group('text_to_image payload', () {
    final cfg = magicToolConfigs['text_to_image']!;

    test('untouched composer: tool IS the purpose, colour omitted', () {
      final p = buildMagicPayload('text_to_image', input: '  A cat on a roof  ', values: cfg.seedValues());
      expect(p, {
        'tool': 'image-design',
        'visual_style': 'photorealistic',
        'ratio': '1:1',
        'purpose': 'image-design',
        'variations': 1,
        'prompt': 'A cat on a roof',
      });
    });

    test('picked purpose, style, colour and ratio', () {
      final v = cfg.seedValues()
        ..['purpose'] = 'ad-design'
        ..['style'] = '3d-render'
        ..['color'] = '#ef4444'
        ..['ratio'] = 'wide';
      final p = buildMagicPayload('text_to_image', input: 'Shoe', values: v);
      expect(p['tool'], 'ad-design');
      expect(p['purpose'], 'ad-design');
      expect(p['visual_style'], '3d-render');
      expect(p['color'], '#ef4444');
      expect(p['ratio'], '21:9');
      expect(p.containsKey('brand_name'), isFalse);
      expect(p.containsKey('logo_url'), isFalse);
    });

    test('validation', () {
      expect(validateMagicInput('text_to_image', input: '   ', values: cfg.seedValues()), 'Please enter a prompt.');
      expect(validateMagicInput('text_to_image', input: 'x', values: cfg.seedValues()), isNull);
    });
  });

  group('image_to_variations payload', () {
    final cfg = magicToolConfigs['image_to_variations']!;

    test('untouched composer', () {
      final p = buildMagicPayload('image_to_variations', input: 'https://cdn/x.png', values: cfg.seedValues());
      expect(p, {
        'tool': 'image_to_variations',
        'visual_style': 'photorealistic',
        'variations': 1,
        'image_url': 'https://cdn/x.png',
      });
    });

    test('legacy title-case style + colour + description', () {
      final v = cfg.seedValues()
        ..['style'] = 'Vintage Sepia'
        ..['color'] = '#111827'
        ..['description'] = '  keep the product  ';
      final p = buildMagicPayload('image_to_variations', input: 'u', values: v);
      expect(p['visual_style'], 'Vintage Sepia');
      expect(p['color'], '#111827');
      expect(p['description'], 'keep the product');
      expect(p.containsKey('ratio'), isFalse);
    });

    test('validation', () {
      expect(
        validateMagicInput('image_to_variations', input: null, values: cfg.seedValues()),
        'Please pick a source image first.',
      );
    });
  });

  group('persona_generator payload', () {
    final cfg = magicToolConfigs['persona_generator']!;

    test('content type is locked to image and hidden from the rows', () {
      expect(cfg.seedValues()['contentType'], 'image');
      expect(cfg.optionRows.map((o) => o.key), ['ratio']);
    });

    test('full payload', () {
      final v = cfg.seedValues()
        ..['personaName'] = ' Amara Osei '
        ..['personaAge'] = '25-34'
        ..['personaOccupation'] = 'Marketing Manager'
        ..['personaTone'] = 'Friendly'
        ..['ratio'] = 'portrait';
      expect(buildMagicPayload('persona_generator', values: v), {
        'tool': 'persona_generator',
        'name': 'Amara Osei',
        'age': '25-34',
        'occupation': 'Marketing Manager',
        'communication_tone': ['Friendly'],
        'content_type': 'image',
        'ratio': '9:16',
        'variations': 1,
      });
    });

    test('validation order', () {
      final v = cfg.seedValues();
      expect(validateMagicInput('persona_generator', values: v), 'Please enter a persona name.');
      v['personaName'] = 'A';
      expect(validateMagicInput('persona_generator', values: v), 'Please select or enter an age.');
      v['personaAge'] = '32';
      expect(validateMagicInput('persona_generator', values: v), 'Please enter an occupation.');
      v['personaOccupation'] = 'Teacher';
      expect(validateMagicInput('persona_generator', values: v), 'Please select a tone.');
      v['personaTone'] = 'Bold';
      expect(validateMagicInput('persona_generator', values: v), isNull);
    });
  });

  test('variations clamp (useMagicGenerate MAX_VARIATIONS)', () {
    expect(clampVariations(null), 1);
    expect(clampVariations(0), 1);
    expect(clampVariations(99), 30);
  });

  test('summarize + ratio strings + word count', () {
    final colour = magicToolConfigs['text_to_image']!.options.firstWhere((o) => o.key == 'color');
    expect(summarizeOption(colour, autoColor), 'No preference');
    expect(summarizeOption(colour, '#abcdef'), '#ABCDEF');
    expect(ratioString('landscape'), '16:9');
    expect(ratioString('4:5'), '4:5');
    expect(magicWordCount('  one two   three '), 3);
    expect(magicWordCount(''), 0);
    expect(notConnectedMessage('graphics'), startsWith("Graphics generation isn't"));
    expect(notConnectedMessage('3D'), startsWith("3D generation isn't"));
  });

  group('history parsing (expandMagicHistoryRecord)', () {
    test('a 4x batch fans out from meta.outputs', () {
      final items = expandMagicHistoryRecord({
        'id': 7,
        'status': 'completed',
        'prompt': 'p',
        'url': 'https://first',
        'meta': {
          'outputs': [
            {'key': 'creativeklux/a.webp'},
            {'url': 'https://b.png'},
          ],
        },
      });
      expect(items.map((i) => i.id), ['7:0', '7:1']);
      expect(items.first.url, '$magicCdnBase/creativeklux/a.webp');
      expect(items.every((i) => i.type == 'image'), isTrue);
    });

    test('video by extension, pending, text, failed', () {
      expect(expandMagicHistoryRecord({'id': 1, 'status': 'completed', 'url': 'https://x/v.mp4'}).single.type, 'video');
      final pending = expandMagicHistoryRecord({'id': 2, 'status': 'processing', 'created_at': '2026-01-01T00:00:00Z'});
      expect(pending.single.pending, isTrue);
      expect(pending.single.id, '2:pending');
      final text = expandMagicHistoryRecord({'id': 3, 'status': 'completed', 'url': '', 'content': 'Hello'});
      expect(text.single.type, 'text');
      expect(expandMagicHistoryRecord({'id': 4, 'status': 'failed', 'url': 'https://x'}), isEmpty);
    });

    test('pickHostedUrl reads the gallery `file` envelope first', () {
      expect(
        pickHostedUrl({
          'success': true,
          'file': {'s3_key': 'creativeklux/k.png'},
          'url': 'https://other',
        }),
        '$magicCdnBase/creativeklux/k.png',
      );
      expect(pickHostedUrl({'nothing': 1}), isNull);
    });

    test('poll schedule', () {
      expect(magicNextPollDelay(const Duration(seconds: 10)), const Duration(seconds: 3));
      expect(magicNextPollDelay(const Duration(minutes: 1)), const Duration(seconds: 5));
      expect(magicNextPollDelay(const Duration(minutes: 5)), const Duration(seconds: 10));
      expect(magicElapsedSince('garbage'), Duration.zero);
    });
  });
}
