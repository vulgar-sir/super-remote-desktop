// super远程桌面 快速启动 (like the reference's quick launch): the remote window asks the controlled PC for its
// Start-menu apps and opens one there; apps pinned for a device show on its device page, where a click
// connects and opens the app. Pins live in the peer config (peer option `sd-quick-apps`), so the main
// window and the session windows see the same list. Messages go through Session::toggle_option
// ("sd-quick-apps" / "sd-launch-app:<id>"); replies arrive as the `sd_quick_apps` session event.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import 'devices.dart';
import 'theme.dart';

const _kPins = 'sd-quick-apps';
const _kLaunchOnConnect = 'sd-launch-on-connect';
const _kOpenOnConnect = 'sd-open-quick-apps';
const kSdWindowEventLaunchApp = 'sd_launch_app';
const kSdWindowEventOpenQuickApps = 'sd_open_quick_apps';

class SdQuickApp {
  final String id;
  final String name;
  final Uint8List? icon;
  SdQuickApp(this.id, this.name, this.icon);

  factory SdQuickApp.fromJson(Map m) {
    Uint8List? icon;
    final s = '${m['icon'] ?? ''}';
    if (s.isNotEmpty) {
      try {
        icon = base64Decode(s);
      } catch (_) {}
    }
    return SdQuickApp('${m['id'] ?? ''}', '${m['name'] ?? ''}', icon);
  }

  Map<String, String> toJson() => {'id': id, 'name': name, 'icon': icon == null ? '' : base64Encode(icon!)};
}

// ------------------------------------------------------------------------------------------ pins

List<SdQuickApp> sdQuickAppPins(String peerId) {
  try {
    final v = jsonDecode(bind.mainGetPeerOptionSync(id: peerId, key: _kPins));
    if (v is List) return v.whereType<Map>().map(SdQuickApp.fromJson).where((a) => a.id.isNotEmpty).toList();
  } catch (_) {}
  return [];
}

Future<void> _savePins(String peerId, List<SdQuickApp> pins) =>
    bind.mainSetPeerOption(id: peerId, key: _kPins, value: jsonEncode(pins.map((a) => a.toJson()).toList()));

Future<void> sdTogglePin(String peerId, SdQuickApp app) async {
  final pins = sdQuickAppPins(peerId);
  if (pins.any((a) => a.id == app.id)) {
    pins.removeWhere((a) => a.id == app.id);
  } else {
    pins.add(app);
  }
  await _savePins(peerId, pins);
}

Widget sdAppIcon(SdQuickApp app, double size) {
  if (app.icon != null && app.icon!.isNotEmpty) {
    return Image.memory(app.icon!, width: size, height: size, filterQuality: FilterQuality.medium, gaplessPlayback: true);
  }
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: kSdTile, borderRadius: BorderRadius.circular(size * 0.22)),
    child: Text(app.name.isEmpty ? '?' : app.name.characters.first,
        style: TextStyle(color: Colors.white, fontSize: size * 0.45, fontWeight: FontWeight.w600)),
  );
}

// ------------------------------------------------------------------------- remote (session) side

class _PeerApps {
  final apps = <SdQuickApp>[].obs;
  final loading = false.obs;
  final error = ''.obs;
  Timer? timeout;
}

final _peerApps = <String, _PeerApps>{};
_PeerApps _stateOf(String peerId) => _peerApps.putIfAbsent(peerId, () => _PeerApps());

/// `sd_quick_apps` session event (model.dart).
void sdOnQuickAppsEvent(String peerId, String data) {
  Map m;
  try {
    m = jsonDecode(data);
  } catch (_) {
    return;
  }
  final launched = '${m['launch'] ?? ''}';
  final error = '${m['error'] ?? ''}';
  if (launched.isNotEmpty) {
    showToast(error.isEmpty ? '已在对方电脑上打开' : '打开失败：$error');
    return;
  }
  final st = _stateOf(peerId);
  st.timeout?.cancel();
  st.loading.value = false;
  st.error.value = error;
  st.apps.assignAll((m['apps'] as List? ?? []).whereType<Map>().map(SdQuickApp.fromJson));
}

void _request(FFI ffi, String peerId) {
  final st = _stateOf(peerId);
  st.loading.value = true;
  st.error.value = '';
  st.timeout?.cancel();
  st.timeout = Timer(const Duration(seconds: 15), () {
    if (st.loading.value) {
      st.loading.value = false;
      st.error.value = '对方没有响应。快速启动需要对方也升级到最新版，并允许控制键盘鼠标。';
    }
  });
  bind.sessionToggleOption(sessionId: ffi.sessionId, value: 'sd-quick-apps');
}

void sdLaunchQuickApp(FFI ffi, String appId) =>
    bind.sessionToggleOption(sessionId: ffi.sessionId, value: 'sd-launch-app:$appId');

/// App picker in the remote window: click an app to open it on the remote PC, ☆ to pin it.
void sdShowQuickAppsPanel(FFI ffi, String peerId) {
  final st = _stateOf(peerId);
  if (st.apps.isEmpty && !st.loading.value) _request(ffi, peerId);
  final query = ''.obs;
  final pinned = sdQuickAppPins(peerId).map((a) => a.id).toSet().obs;
  ffi.dialogManager.show((setState, close, context) {
    final p = SdPalette(context);
    final width = math.min(600.0, MediaQuery.of(context).size.width - 72);
    Widget tile(SdQuickApp app) {
      final isPinned = pinned.contains(app.id);
      return SizedBox(
        width: 96,
        height: 98,
        child: Stack(children: [
          Positioned.fill(
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              hoverColor: p.soft.withOpacity(0.5),
              onTap: () {
                sdLaunchQuickApp(ffi, app.id);
                close();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                child: Column(children: [
                  sdAppIcon(app, 40),
                  const SizedBox(height: 8),
                  Text(app.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.25, color: p.text)),
                ]),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              tooltip: isPinned ? '从设备页的快速启动移除' : '固定到设备页的快速启动',
              splashRadius: 14,
              iconSize: 16,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              icon: Icon(isPinned ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isPinned ? const Color(0xFFFFB020) : p.hint),
              onPressed: () async {
                await sdTogglePin(peerId, app);
                pinned.assignAll(sdQuickAppPins(peerId).map((a) => a.id));
              },
            ),
          ),
        ]),
      );
    }

    return CustomAlertDialog(
      title: Row(children: [
        const Text('快速启动'),
        const Spacer(),
        IconButton(
          tooltip: '刷新',
          splashRadius: 16,
          icon: Icon(Icons.refresh_rounded, size: 20, color: p.muted),
          onPressed: () => _request(ffi, peerId),
        ),
      ]),
      contentBoxConstraints: BoxConstraints(minWidth: width, maxWidth: width),
      content: SizedBox(
        height: math.min(440.0, MediaQuery.of(context).size.height - 260),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            autofocus: true,
            onChanged: (v) => query.value = v.trim().toLowerCase(),
            decoration: sdInputDecoration(p, '搜索对方电脑上的应用').copyWith(
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: p.hint),
                prefixIconConstraints: const BoxConstraints(minWidth: 36)),
          ),
          const SizedBox(height: 6),
          Text('点击应用即在对方电脑上打开；点 ☆ 可固定到设备页的“快速启动”。',
              style: TextStyle(fontSize: 12, color: p.hint)),
          const SizedBox(height: 8),
          Expanded(
            child: Obx(() {
              if (st.loading.value) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    const SizedBox(height: 12),
                    Text('正在获取对方电脑上的应用…', style: TextStyle(fontSize: 13, color: p.hint)),
                  ]),
                );
              }
              if (st.error.value.isNotEmpty && st.apps.isEmpty) {
                return Center(
                    child: Text(st.error.value,
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.hint)));
              }
              pinned.length; // rebuild on pin changes
              final q = query.value;
              final list = st.apps.where((a) => q.isEmpty || a.name.toLowerCase().contains(q)).toList();
              return SingleChildScrollView(child: Wrap(children: list.map(tile).toList()));
            }),
          ),
        ]),
      ),
      actions: [dialogButton('Close', onPressed: close)],
      onCancel: close,
    );
  }, clickMaskDismiss: true);
}

/// Called once the remote session is up (model.dart): carry out what the device page asked for.
void sdQuickAppsOnConnected(FfiModel model, String peerId) {
  final ffi = model.parent.target;
  if (ffi == null) return;
  final launch = bind.mainGetPeerOptionSync(id: peerId, key: _kLaunchOnConnect);
  final open = bind.mainGetPeerOptionSync(id: peerId, key: _kOpenOnConnect) == 'Y';
  if (launch.isEmpty && !open) return;
  bind.mainSetPeerOption(id: peerId, key: _kLaunchOnConnect, value: '');
  bind.mainSetPeerOption(id: peerId, key: _kOpenOnConnect, value: '');
  // give the session a moment to finish logging in before the first request
  Future.delayed(const Duration(milliseconds: 1500), () {
    if (launch.isNotEmpty) sdLaunchQuickApp(ffi, launch);
    if (open) sdShowQuickAppsPanel(ffi, peerId);
  });
}

/// Requests from the main window (remote_tab_page.dart); true when handled.
bool sdQuickAppsWindowCall(String method, dynamic arguments) {
  if (method != kSdWindowEventLaunchApp && method != kSdWindowEventOpenQuickApps) return false;
  try {
    final args = jsonDecode('$arguments') as Map;
    final peerId = '${args['id']}';
    final ffi = Get.find<FFI>(tag: peerId);
    if (method == kSdWindowEventLaunchApp) {
      sdLaunchQuickApp(ffi, '${args['app']}');
    } else {
      sdShowQuickAppsPanel(ffi, peerId);
    }
  } catch (e) {
    debugPrint('superdesk: quick apps window call failed: $e');
  }
  return true;
}

/// Toolbar button of the remote window.
class SdQuickAppsToolbarButton extends StatefulWidget {
  final String id;
  final FFI ffi;
  const SdQuickAppsToolbarButton({Key? key, required this.id, required this.ffi}) : super(key: key);

  @override
  State<SdQuickAppsToolbarButton> createState() => _SdQuickAppsToolbarButtonState();
}

class _SdQuickAppsToolbarButtonState extends State<SdQuickAppsToolbarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
        message: '快速启动',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: () => sdShowQuickAppsPanel(widget.ffi, widget.id),
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              decoration: BoxDecoration(
                color: _hover ? (dark ? const Color(0xFF2A3442) : kSdToolbarHover) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.apps_rounded,
                  size: 21, color: _hover ? kSdAccent : (dark ? const Color(0xFFE8EAEE) : kSdToolbarIcon)),
            ),
          ),
        ),
      );
  }
}

const kSdToolbarIcon = Color(0xFF3A3F45);
const kSdToolbarHover = Color(0xFFE8F0FE);

// --------------------------------------------------------------------------------- device page

/// "快速启动" on the device page: pinned apps, "添加", "应用管理".
class SdQuickLaunchSection extends StatefulWidget {
  final String peerId;
  final bool mobile;
  const SdQuickLaunchSection({Key? key, required this.peerId, this.mobile = false}) : super(key: key);

  @override
  State<SdQuickLaunchSection> createState() => _SdQuickLaunchSectionState();
}

class _SdQuickLaunchSectionState extends State<SdQuickLaunchSection> {
  List<SdQuickApp> _pins = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pins = sdQuickAppPins(widget.peerId);
    // pins are added from the session window; pick them up while this page is open
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reload() {
    final pins = sdQuickAppPins(widget.peerId);
    if (jsonEncode(pins.map((a) => a.id).toList()) != jsonEncode(_pins.map((a) => a.id).toList()) && mounted) {
      setState(() => _pins = pins);
    }
  }

  Future<void> _sessionCall(String method, Map<String, String> args) async {
    final w = SdSessions.peers[widget.peerId];
    if (w == null) return;
    await DesktopMultiWindow.invokeMethod(w, method, jsonEncode(args));
    await SdSessions.show(widget.peerId);
  }

  Future<void> _open(SdQuickApp app) async {
    if (SdSessions.peers.containsKey(widget.peerId)) {
      await _sessionCall(kSdWindowEventLaunchApp, {'id': widget.peerId, 'app': app.id});
      return;
    }
    await bind.mainSetPeerOption(id: widget.peerId, key: _kLaunchOnConnect, value: app.id);
    if (mounted) connect(context, widget.peerId);
  }

  void _add() {
    gFFI.dialogManager.show((setState, close, context) {
      Future<void> go() async {
        close();
        if (SdSessions.peers.containsKey(widget.peerId)) {
          await _sessionCall(kSdWindowEventOpenQuickApps, {'id': widget.peerId});
          return;
        }
        await bind.mainSetPeerOption(id: widget.peerId, key: _kOpenOnConnect, value: 'Y');
        if (mounted) connect(this.context, widget.peerId);
      }

      return CustomAlertDialog(
        title: const Text('添加快速启动应用'),
        content: const Text('使用此功能需要连接并访问被控端以获取应用。super远程桌面不会上传应用信息。'),
        actions: [
          dialogButton('Cancel', onPressed: close, isOutline: true),
          dialogButton('OK', onPressed: go),
        ],
        onSubmit: go,
        onCancel: close,
      );
    });
  }

  void _manage() {
    gFFI.dialogManager.show((setState, close, context) {
      final p = SdPalette(context);
      final pins = sdQuickAppPins(widget.peerId);
      final width = math.min(420.0, MediaQuery.of(context).size.width - 72);
      return CustomAlertDialog(
        title: const Text('应用管理'),
        contentBoxConstraints: BoxConstraints(minWidth: width, maxWidth: width),
        content: pins.isEmpty
            ? Text('还没有固定的应用', style: TextStyle(color: p.hint))
            : SizedBox(
                height: 320,
                child: ListView(
                  children: pins
                      .map((a) => ListTile(
                            dense: true,
                            leading: sdAppIcon(a, 28),
                            title: Text(a.name, style: TextStyle(fontSize: 14, color: p.text)),
                            trailing: IconButton(
                              tooltip: '移除',
                              icon: Icon(Icons.remove_circle_outline_rounded, color: p.muted, size: 20),
                              onPressed: () async {
                                await sdTogglePin(widget.peerId, a);
                                _reload();
                                setState(() {});
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
        actions: [dialogButton('Close', onPressed: close)],
        onCancel: close,
      );
    });
  }

  /// Phone layout (like the reference app): bold title, "应用管理" pill, four columns, "添加应用".
  Widget _buildMobile(BuildContext context, SdPalette p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('快速启动', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        const Spacer(),
        if (_pins.isNotEmpty)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _manage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: p.dark ? p.soft : const Color(0xFFE6EAED), borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.apps_rounded, size: 15, color: p.text),
                const SizedBox(width: 4),
                Text('应用管理', style: TextStyle(fontSize: 13, color: p.text)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / 4;
        Widget cell(Widget icon, String label, VoidCallback onTap) => SizedBox(
              width: w,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    icon,
                    const SizedBox(height: 8),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.text)),
                  ]),
                ),
              ),
            );
        return Wrap(children: [
          ..._pins.map((a) => cell(sdAppIcon(a, 46), a.name, () => _open(a))),
          cell(
              Container(
                width: 46,
                height: 46,
                decoration:
                    BoxDecoration(color: p.dark ? p.soft : const Color(0xFFE6EAED), shape: BoxShape.circle),
                child: Icon(Icons.add_rounded, size: 24, color: p.muted),
              ),
              '添加应用',
              _add),
        ]);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    if (widget.mobile) return _buildMobile(context, p);
    Widget appTile(SdQuickApp app) => SizedBox(
          width: 92,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            hoverColor: p.soft.withOpacity(0.5),
            onTap: () => _open(app),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                sdAppIcon(app, 44),
                const SizedBox(height: 8),
                Text(app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: p.text)),
              ]),
            ),
          ),
        );
    final add = SizedBox(
      width: 92,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        hoverColor: p.soft.withOpacity(0.5),
        onTap: _add,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: p.dark ? p.soft : const Color(0xFFEEF1F3), shape: BoxShape.circle),
              child: Icon(Icons.add_rounded, size: 28, color: p.muted),
            ),
            const SizedBox(height: 6),
            Text('添加', style: TextStyle(fontSize: 12.5, color: p.text)),
          ]),
        ),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 34,
        child: Row(children: [
          Text('快速启动', style: TextStyle(fontSize: 14.5, color: p.muted)),
          const Spacer(),
          if (_pins.isNotEmpty)
            TextButton.icon(
              onPressed: _manage,
              icon: Icon(Icons.grid_view_rounded, size: 16, color: p.muted),
              label: Text('应用管理', style: TextStyle(fontSize: 13.5, color: p.muted)),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      CustomPaint(
        painter: _DashedRRect(color: p.dark ? p.line : const Color(0xFFDADCDD)),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 200),
          padding: const EdgeInsets.all(20),
          alignment: _pins.isEmpty ? Alignment.center : Alignment.topLeft,
          child: Wrap(spacing: 16, runSpacing: 12, children: [..._pins.map(appTile), add]),
        ),
      ),
    ]);
  }
}

class _DashedRRect extends CustomPainter {
  final Color color;
  _DashedRRect({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)).deflate(0.5));
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color;
}
