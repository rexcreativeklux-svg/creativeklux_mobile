import 'package:flutter/material.dart';

import 'brand.dart';

/// A brand's logo, or its initial on its primary colour when there's no logo
/// or it fails to load — same fallback as the web header and brand picker.
class BrandAvatar extends StatelessWidget {
  const BrandAvatar({super.key, required this.brand, this.size = 24});

  final Brand brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: brand.color, shape: BoxShape.circle),
      child: Text(
        brand.initial,
        style: TextStyle(color: Colors.white, fontSize: size * 0.5, fontWeight: FontWeight.w600, height: 1),
      ),
    );

    final url = brand.logoUrl;
    if (url == null) return fallback;
    return ClipOval(
      child: Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}
