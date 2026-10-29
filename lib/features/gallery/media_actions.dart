import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/toast.dart';
import 'gallery_api.dart';

/// A file name with the right extension (fileNameFor in downloadMedia.js):
/// audio → .mp3, video → .mp4, images/docs keep their own.
String _fileNameFor(GalleryMedia item, String url) {
  final type = item.type;
  final raw = item.filename.isNotEmpty ? item.filename : '$type-${item.id ?? DateTime.now().millisecondsSinceEpoch}';
  var base = raw.replaceFirst(RegExp(r'\.[a-z0-9]{1,5}$', caseSensitive: false), '').trim();
  // Path separators would make the temp path point into a missing folder.
  base = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (base.isEmpty) base = '$type-${DateTime.now().millisecondsSinceEpoch}';
  final ext = switch (type) {
    'audio' => 'mp3',
    'video' => 'mp4',
    _ => () {
      final fromName = extensionOf(raw);
      if (fromName.isNotEmpty && fromName.length <= 5) return fromName;
      final fromUrl = extensionOf(url);
      if (fromUrl.isNotEmpty && fromUrl.length <= 5) return fromUrl;
      return type == 'image' ? 'jpg' : 'bin';
    }(),
  };
  return '$base.$ext';
}

/// Download a gallery item to the phone (port of downloadGalleryItem).
///
/// Pictures and clips go to the photo gallery. Audio and documents can't
/// live there, so they go out through the share sheet ("Save to Files" etc.)
/// — the phone's equivalent of the browser's download.
Future<void> downloadGalleryMedia(GalleryMedia item) async {
  final url = item.downloadUrl ?? item.src;
  if (url.isEmpty) {
    Toast.error('Nothing to download.');
    return;
  }
  Toast.info('Downloading…');
  try {
    final type = item.type;
    if (type == 'image') {
      final res = await Dio().get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final bytes = Uint8List.fromList(res.data ?? const []);
      if (bytes.isEmpty) throw Exception('empty file');
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(bytes, name: _fileNameFor(item, url).replaceFirst(RegExp(r'\.[^.]+$'), ''));
      Toast.success('Saved to your photo gallery');
      return;
    }
    final path = '${Directory.systemTemp.path}/${_fileNameFor(item, url)}';
    await Dio().download(url, path);
    if (type == 'video') {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putVideo(path);
      Toast.success('Saved to your photo gallery');
      unawaited(File(path).delete().catchError((_) => File(path)));
    } else {
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    }
  } catch (err) {
    // The web falls back to opening the file when a CDN blocks the fetch;
    // the browser is the same way out here.
    debugPrint('↩️ [gallery] download failed, opening instead: $err');
    Toast.error("Couldn't download that file — opening it instead.");
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

Future<void> copyMediaLink(GalleryMedia item) async {
  await Clipboard.setData(ClipboardData(text: item.src));
  Toast.success('Link copied to clipboard');
}

/// A document has no inline preview — the web opens it in a new tab.
Future<void> openMediaExternally(GalleryMedia item) async {
  final ok = await launchUrl(Uri.parse(item.src), mode: LaunchMode.externalApplication);
  if (!ok) Toast.error("Couldn't open that file.");
}
