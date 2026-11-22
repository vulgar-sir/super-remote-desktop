// super远程桌面: device data shared by the desktop and mobile layouts -- the merged device list
// (favourites, address book, recent sessions), online states, favourites and the info dialog.
// Everything goes through the existing peer models and FFI calls.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
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
