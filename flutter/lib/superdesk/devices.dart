// super远程桌面: device data shared by the desktop and mobile layouts -- the merged device list
// (favourites, address book, recent sessions), online states, favourites and the info dialog.
// Everything goes through the existing peer models and FFI calls.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:get/get.dart';

/// Online state of the listed devices, refreshed while a device list is shown.
class SdOnline {
  static final ids = <String>{}.obs;
  static Timer? _timer;
  static List<String> _want = const [];

  static void start() {
    platformFFI.registerEventHandler('callback_query_onlines', 'SdDevices', (evt) async {
      final on = '${evt['onlines'] ?? ''}'.split(',').where((x) => x.isNotEmpty);
      final off = '${evt['offlines'] ?? ''}'.split(',').where((x) => x.isNotEmpty);
      ids.addAll(on);
      ids.removeAll(off);
    });
    _timer ??= Timer.periodic(const Duration(seconds: 15), (_) => _query());
  }

  static void want(List<String> list) {
    final changed = list.length != _want.length || list.any((x) => !_want.contains(x));
    _want = list;
    if (changed) Future.delayed(const Duration(milliseconds: 300), _query);
  }

  static void _query() {
    if (_want.isNotEmpty) bind.queryOnlines(ids: _want.take(60).toList());
  }
}

/// Fires when the recent or favourite device lists change.
Listenable get sdPeersListenable => Listenable.merge([gFFI.recentPeersModel, gFFI.favoritePeersModel]);

/// Favourites first, then address book, then recent sessions (deduplicated).
List<Peer> sdAllPeers() {
  final seen = <String>{};
  final out = <Peer>[];
  void add(Iterable<Peer> list) {
    for (final x in list) {
      if (x.id.isNotEmpty && seen.add(x.id)) out.add(x);
    }
  }

  add(gFFI.favoritePeersModel.peers);
  if (gFFI.userModel.userName.value.isNotEmpty) add(gFFI.abModel.currentAbPeers);
  add(gFFI.recentPeersModel.peers);
  return out;
}

String sdPeerName(Peer x) =>
    x.alias.isNotEmpty ? x.alias : (x.hostname.isNotEmpty ? x.hostname : formatID(x.id));

Peer sdSelfPeer() => Peer.fromJson({
      'id': trimID(gFFI.serverModel.serverId.text),
      'hostname': Platform.localHostname,
      'platform': Platform.isWindows
          ? 'Windows'
          : (Platform.isMacOS ? 'Mac OS' : (Platform.isAndroid ? 'Android' : 'Linux')),
    });

Future<bool> sdIsFav(String id) async => (await bind.mainGetFav()).contains(id);

Future<void> sdSetFav(String id, bool fav) async {
  final favs = (await bind.mainGetFav()).toList();
  if (fav && !favs.contains(id)) favs.add(id);
  if (!fav) favs.remove(id);
  await bind.mainStoreFav(favs: favs);
  bind.mainLoadFavPeers();
}

void sdPeerInfoDialog(Peer x) {
  final rows = <List<String>>[
    ['设备ID', formatID(x.id)],
    if (x.alias.isNotEmpty) ['备注名', x.alias],
    if (x.hostname.isNotEmpty) ['设备名称', x.hostname],
    if (x.username.isNotEmpty) ['用户名', x.username],
    if (x.platform.isNotEmpty) ['系统', x.platform],
  ];
  gFFI.dialogManager.show((setState, close, context) => CustomAlertDialog(
        title: const Text('设备信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows
              .map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 72, child: Text(r[0], style: const TextStyle(color: Color(0xFF656565)))),
                      Expanded(child: SelectableText(r[1])),
                    ]),
                  ))
              .toList(),
        ),
        actions: [dialogButton('OK', onPressed: close)],
        onCancel: close,
        onSubmit: close,
      ));
}

/// 观看模式 / 进入桌面 on the device page: the wanted mode rides on a one-shot peer option and is
/// applied with the toolbar's own view-mode toggle once the session has its peer info.
const kSdViewModeOption = 'sd-view-mode';

Future<void> sdConnectMode(BuildContext context, String id, {required bool viewOnly}) async {
  await bind.mainSetPeerOption(id: id, key: kSdViewModeOption, value: viewOnly ? 'Y' : 'N');
  if (context.mounted) connect(context, id);
}

Future<void> sdApplyViewMode(FfiModel ffiModel, String peerId) async {
  final sessionId = ffiModel.sessionId;
  final want = await bind.sessionGetOption(sessionId: sessionId, arg: kSdViewModeOption);
  if (want == null || want.isEmpty) return;
  await bind.sessionPeerOption(sessionId: sessionId, name: kSdViewModeOption, value: '');
  final on = want == 'Y';
  if (bind.sessionGetToggleOptionSync(sessionId: sessionId, arg: kOptionToggleViewOnly) != on) {
    await bind.sessionToggleOption(sessionId: sessionId, value: kOptionToggleViewOnly);
    ffiModel.setViewOnly(peerId, on);
  }
}

/// Asks a session window to close the tab of a peer ("断开所有远控" on the device page).
const kSdWindowEventClosePeer = 'sd_close_peer';

/// Peers that have an open remote session tab, polled from the session windows: peer id -> window.
class SdSessions {
  static final peers = <String, int>{}.obs;
  static Timer? _timer;

  static void start() {
    if (!isDesktop) return;
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _poll();
  }

  static Future<void> _poll() async {
    final found = <String, int>{};
    try {
      for (final w in await rustDeskWinManager.getAllSubWindowIds()) {
        try {
          final r = await DesktopMultiWindow.invokeMethod(w, kWindowEventGetRemoteList, null);
          if (r is String) {
            for (final id in r.split(',')) {
              if (id.isNotEmpty) found[id] = w;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
    if (!mapEquals(found, Map<String, int>.from(peers))) peers.assignAll(found);
  }

  static Future<void> show(String id) async {
    final w = peers[id];
    if (w != null) await DesktopMultiWindow.invokeMethod(w, kWindowEventActiveSession, id);
  }

  static Future<void> close(String id) async {
    final w = peers[id];
    if (w != null) await DesktopMultiWindow.invokeMethod(w, kSdWindowEventClosePeer, id);
    await _poll();
  }
}

/// Remote-control sessions *into* this machine ("本机被控中"). The server keeps the count; the
/// connection manager showing them is a separate process, so its window is raised by title.
class SdIncoming {
  static final count = 0.obs;
  static Timer? _timer;

  static void start() {
    if (!isDesktop || bind.isOutgoingOnly()) return;
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    _poll();
  }

  static Future<void> _poll() async {
    try {
      final s = jsonDecode(await bind.mainGetConnectStatus());
      final n = s is Map ? s['video_conn_count'] : null;
      count.value = n is int ? n : 0;
    } catch (_) {}
  }

  /// Brings the connection-manager window forward. It lives in its own process and retitles itself after
  /// the selected client ("<peer> - <app>", server_page.dart), so look for a Flutter runner window of
  /// another process titled "<app> - Connection Manager" or "<label> - <app>" (session windows of this
  /// process are "<id> - Remote Desktop - <app>" and the like).
  static void showWindow() {
    if (!Platform.isWindows) return;
    final app = bind.mainGetAppNameSync();
    final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final buf = malloc<Uint16>(512).cast<Utf16>();
    final procId = malloc<Uint32>();
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final findWindowEx = user32.lookupFunction<IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>),
          int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>('FindWindowExW');
      final getText = user32.lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, int)>('GetWindowTextW');
      final getPid = user32.lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>(
          'GetWindowThreadProcessId');
      final showWindow =
          user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('ShowWindow');
      final setForeground =
          user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow');
      var hwnd = 0;
      while ((hwnd = findWindowEx(0, hwnd, cls, nullptr)) != 0) {
        getPid(hwnd, procId);
        if (procId.value == pid) continue;
        getText(hwnd, buf, 512);
        final title = buf.toDartString();
        final suffix = ' - $app';
        final isCm = title == '$app - Connection Manager' ||
            (title.endsWith(suffix) && !title.substring(0, title.length - suffix.length).contains(' - '));
        if (isCm) {
          showWindow(hwnd, 9); // SW_RESTORE
          setForeground(hwnd);
          return;
        }
      }
    } catch (e) {
      debugPrint('superdesk: raise cm window failed: $e');
    } finally {
      malloc.free(cls);
      malloc.free(buf);
      malloc.free(procId);
    }
  }
}
