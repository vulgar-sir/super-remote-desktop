// super远程桌面: device previews show the device's own desktop wallpaper, like the reference. Each Windows client
// uploads a small PNG of its wallpaper to super控制台 when it changes; the device page shows it to clients that
// are logged in to a console account and keeps the gradient otherwise.
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:http/http.dart' as http;

import 'superdesk.dart';

const _kWallpaperSig = 'sd-wallpaper-sig';

String _wallpaperPath() {
  final buf = malloc<Uint16>(520);
  try {
    final spi = DynamicLibrary.open('user32.dll').lookupFunction<
        Int32 Function(Uint32, Uint32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)>('SystemParametersInfoW');
    if (spi(0x0073 /* SPI_GETDESKWALLPAPER */, 520, buf.cast(), 0) == 0) return '';
    return buf.cast<Utf16>().toDartString();
  } finally {
    malloc.free(buf);
  }
}

/// Uploads this PC's wallpaper (480px wide PNG) unless the same file was already sent.
Future<void> sdUploadWallpaper(String api) async {
  if (!Platform.isWindows || bind.isOutgoingOnly()) return;
  try {
    final path = _wallpaperPath();
    if (path.isEmpty) return; // solid colour background
    final file = File(path);
    if (!await file.exists()) return;
    final st = await file.stat();
    final sig = '$path|${st.modified.millisecondsSinceEpoch}|${st.size}';
    if (bind.mainGetLocalOption(key: _kWallpaperSig) == sig) return;
    final codec = await ui.instantiateImageCodec(await file.readAsBytes(), targetWidth: 480);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (png == null) return;
    final id = await bind.mainGetMyId();
    final uuid = await bind.mainGetUuid();
    final resp = await http
        .post(
            Uri.parse('$api/api/superdesk/wallpaper?id=${Uri.encodeQueryComponent(id)}'
                '&uuid=${Uri.encodeQueryComponent(uuid)}'),
            headers: {'Content-Type': 'application/octet-stream'},
            body: png.buffer.asUint8List())
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 200) await bind.mainSetLocalOption(key: _kWallpaperSig, value: sig);
  } catch (e) {
    debugPrint('superdesk: wallpaper upload failed: $e');
  }
}

class SdWallpapers {
  // keyed by device + login, so logging in fetches again; a miss is kept for the session
  static final _cache = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> get(String id) {
    final token = bind.mainGetLocalOption(key: 'access_token');
    return _cache['$id|$token'] ??= _fetch(id, token);
  }

  static Future<Uint8List?> _fetch(String id, String token) async {
    if (token.isEmpty) return null;
    try {
      final api = await sdApiServer();
      if (api.isEmpty) return null;
      final resp = await http.get(Uri.parse('$api/api/superdesk/wallpaper/${Uri.encodeComponent(id)}'),
          headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200 && resp.bodyBytes.isNotEmpty ? resp.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}

/// The device's wallpaper filling the preview (greyed out while offline); nothing when there is none.
class SdWallpaper extends StatelessWidget {
  final String id;
  final bool online;
  const SdWallpaper({Key? key, required this.id, required this.online}) : super(key: key);

  static const _grey = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: SdWallpapers.get(id),
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null) return const SizedBox.shrink();
          Widget image = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
          if (!online) image = ColorFiltered(colorFilter: _grey, child: image);
          return Stack(fit: StackFit.expand, children: [
            image,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1],
                  colors: [Colors.transparent, Color(0x73000000)],
                ),
              ),
            ),
          ]);
        },
      );
}
