import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

/// Per-creative theming of the chat page (`CREATIVE_CONFIG` in ai-chat-page).
class CreativeConfig {
  const CreativeConfig(this.key, this.label, this.color, this.icon, this.greeting, this.placeholder);
  final String key;
  final String label;
  final Color color;
  final IconData icon;
  final String greeting;
  final String placeholder;
}

const creativeConfigs = {
  'general': CreativeConfig(
    'general',
    'Creative Studio',
    Color(0xFF003DDA),
    LucideIcons.sparkles,
    "Hi! I'm **CreativeKlux AI** ✦\n\nWhat would you like to make today?",
    "Describe what you'd like to create…",
  ),
  'ads_creative': CreativeConfig(
    'ads_creative',
    'Ads Creative',
    Color(0xFF60A5FA),
    LucideIcons.tv,
    "Hi! I'm your **Ads Creative** assistant ✦\n\nTell me about the ad you want to create — platform, audience, "
        "product — and I'll craft something that converts.",
    'e.g. Create a Meta ad for my skincare brand…',
  ),
  'social_creative': CreativeConfig(
    'social_creative',
    'Social Creative',
    Color(0xFF34D399),
    LucideIcons.share2,
    "Hey! I'm your **Social Creative** assistant ✦\n\nWhat kind of social content are we making today?",
    'e.g. Design an Instagram carousel…',
  ),
  'designer_creative': CreativeConfig(
    'designer_creative',
    'Designer',
    Color(0xFFC084FC),
    LucideIcons.palette,
    "Hello! I'm your **Designer** assistant ✦\n\nWhat are we designing today? Tell me the vibe, purpose, or brand.",
    'e.g. Design a minimalist logo…',
  ),
  'magic_studio': CreativeConfig(
    'magic_studio',
    'Magic Studio',
    Color(0xFFFB7185),
    LucideIcons.wand,
    "Welcome to **Magic Studio** ✦\n\nWhat would you like to generate? Images, video, audio — just describe your vision.",
    'e.g. Generate a futuristic city at dusk…',
  ),
};

CreativeConfig configFor(String? key) => creativeConfigs[key] ?? creativeConfigs['general']!;

class ChatMessage {
  ChatMessage({required this.fromUser, required this.content, this.images = const [], this.imageUrl, DateTime? time})
    : time = time ?? DateTime.now();

  final bool fromUser;
  final String content;
  final List<String> images;

  /// Optional generated image the reply carries (`data.image_url`).
  final String? imageUrl;
  final DateTime time;

  /// Port of `normalizeSessionMessage` (studio/chatSessions.js) — saved
  /// threads use several key spellings. Returns null for empty messages.
  static ChatMessage? fromSaved(dynamic raw) {
    if (raw is! Map) return null;
    bool fromUser;
    if (raw['is_user'] is bool) {
      fromUser = raw['is_user'] as bool;
    } else if (raw['from_user'] is bool) {
      fromUser = raw['from_user'] as bool;
    } else {
      final role = '${raw['role'] ?? raw['sender'] ?? raw['author'] ?? raw['type'] ?? ''}'.toLowerCase();
      fromUser = !const {'assistant', 'ai', 'bot', 'system', 'klux'}.contains(role);
    }

    var content = raw['content'] ?? raw['message'] ?? raw['text'] ?? raw['reply'] ?? raw['body'];
    if (content is Map) content = content['reply'] ?? content['message'] ?? content['content'] ?? content['text'];
    final text = content == null ? '' : '$content'.trim();

    final rawImages = raw['images'] ?? raw['attachments'] ?? raw['image_urls'];
    final images = <String>[
      if (rawImages is List)
        for (final i in rawImages)
          if (i is String) i else if (i is Map && (i['url'] ?? i['src']) != null) '${i['url'] ?? i['src']}',
    ];
    if (text.isEmpty && images.isEmpty) return null;
    return ChatMessage(
      fromUser: fromUser,
      content: text,
      images: images,
      time: DateTime.tryParse('${raw['created_at'] ?? raw['timestamp'] ?? raw['time']}')?.toLocal(),
    );
  }
}

/// Rotating progress lines, shared by the typing indicator, banner and tiles.
const progressLines = {
  'designs': [
    'Creating your designs…',
    'Working through your brand details…',
    'Writing headlines and copy…',
    'Laying out the artwork…',
    'Applying your colours and logo…',
  ],
  'magic': [
    'Generating your design…',
    'Composing the scene…',
    'Working in your brand colour…',
    'Adding your headline and logo…',
    'Still going — this can take a few minutes…',
  ],
};

/// A small markdown renderer for assistant replies: **bold** (in the theme
/// colour), *italic*, `- ` / `* ` / `1. ` lists, [links](url), and single
/// newlines as hard breaks (remark-breaks on the web). Replies don't use more.
class MiniMarkdown extends StatelessWidget {
  const MiniMarkdown(this.text, {super.key, required this.style, required this.accent});

  final String text;
  final TextStyle style;
  final Color accent;

  static final _inline = RegExp(r'\*\*(.+?)\*\*|(?<!\*)\*(?!\s)(.+?)\*|\[([^\]]+)\]\(([^)]+)\)');

  List<InlineSpan> _spans(String line) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inline.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start)));
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: TextStyle(fontWeight: FontWeight.w700, color: accent),
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        final url = m.group(4)!;
        spans.add(
          TextSpan(
            text: m.group(3),
            style: TextStyle(color: accent, decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()
              ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        );
      }
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final blocks = <Widget>[];
    for (final para in text.split(RegExp(r'\n\s*\n'))) {
      final lines = para.split('\n');
      final bullet = RegExp(r'^\s*([-*•]|\d+\.)\s+');
      final children = <Widget>[];
      for (final line in lines) {
        final m = bullet.firstMatch(line);
        if (m != null) {
          final marker = m.group(1)!;
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 18, child: Text(RegExp(r'\d').hasMatch(marker) ? marker : '•', style: style)),
                  Expanded(
                    child: Text.rich(TextSpan(style: style, children: _spans(line.substring(m.end)))),
                  ),
                ],
              ),
            ),
          );
        } else if (line.trim().isNotEmpty) {
          children.add(Text.rich(TextSpan(style: style, children: _spans(line))));
        }
      }
      if (children.isNotEmpty) {
        blocks.add(Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, b) in blocks.indexed) ...[if (i > 0) const SizedBox(height: 8), b],
      ],
    );
  }
}
