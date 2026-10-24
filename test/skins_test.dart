import 'package:creativeklux/core/theme/app_colors.dart';
import 'package:creativeklux/core/theme/skins.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every skin from skins.js has both palettes and some art', () {
    expect(skinSpecs.first.id, defaultSkinId);
    expect(skinSpecs.length, 19);
    for (final s in skinSpecs.skip(1)) {
      expect(s.light, isNotNull, reason: s.id);
      expect(s.dark, isNotNull, reason: s.id);
      expect(s.light!.layers, isNotEmpty, reason: s.id);
      expect(s.light!.base.a, 1.0, reason: '${s.id} base must be opaque');
    }
  });

  test('oklab mix hits its ends and stays between them', () {
    const a = Color(0xFF101828), b = Color(0xFFFFFFFF);
    expect(mixOklab(a, b, 1).toARGB32(), a.toARGB32());
    expect(mixOklab(a, b, 0).toARGB32(), b.toARGB32());
    final mid = mixOklab(a, b, 0.5);
    expect(mid.r, inExclusiveRange(a.r, b.r));
  });

  test('a skin ramp darkens toward ink, like skins.css', () {
    final p = skinById('nebula').light!;
    final c = appColorsForSkin(p, dark: false);
    double lum(Color x) => x.computeLuminance();
    expect(lum(c.gray50), greaterThan(lum(c.gray300)));
    expect(lum(c.gray300), greaterThan(lum(c.gray600)));
    expect(lum(c.gray600), greaterThan(lum(c.gray900)));
    expect(c.page, p.page);
  });

  test('accent follows applyAccent and resets', () {
    AppColors.applyAccent(accent: const Color(0xFF0D8F66), soft: const Color(0xFF2FAE87));
    expect(AppColors.blue600, const Color(0xFF0D8F66));
    AppColors.applyAccent();
    expect(AppColors.blue600, const Color(0xFF155DFC));
  });
}
