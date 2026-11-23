// super远程桌面: main-window layout in the UU-remote-like style -- grey sidebar ("我的设备" / "远程协助" /
// "设置"), title-bar widgets, and the pages: 远程协助 (this device's ID + verification code, connect to a
// partner), 全部设备, 收藏设备, device details, settings. Only the presentation is new: connections,
// passwords, favourites and settings all go through the existing models and FFI calls.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/consts.dart' show kPeerPlatformWindows;
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_settings.dart';
import 'devices.dart';
import 'extend_screen.dart';
import 'notices.dart';
import 'quick_apps.dart';
import 'superdesk.dart';
import 'theme.dart';
import 'wallpaper.dart';

export 'theme.dart';

// --------------------------------------------------------------------------------------------- banner

/// Notice banner (install / update / permissions / errors): light panel, info icon, bold title.
Widget sdBanner(BuildContext context,
    {required String title,
    required String content,
    String? button,
    GestureTapCallback? onPressed,
    VoidCallback? onClose,
    String? help,
    String? link}) {
  final p = SdPalette(context);
  final btn = button == null ? null : sdOutlineButton(p, button, onPressed, minWidth: 0);
  return LayoutBuilder(builder: (context, box) {
    final narrow = box.maxWidth < 420; // the compact helper window
    return Container(
      margin: narrow ? const EdgeInsets.fromLTRB(16, 12, 16, 0) : const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: p.dark ? p.card : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.dark ? p.line : const Color(0xFFE8E9EA)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
            padding: EdgeInsets.only(top: 1), child: Icon(Icons.info_rounded, color: kSdAccent, size: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title.isNotEmpty)
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: p.text, fontSize: 14.5)),
            if (content.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: title.isEmpty ? 0 : 4),
                child: Text(content, style: TextStyle(color: p.text, fontSize: 13)),
              ),
            if (help != null && link != null)
              InkWell(
                onTap: () => launchUrl(Uri.parse(link)),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(help, style: const TextStyle(color: kSdAccent, fontSize: 13)),
                ),
              ),
            if (btn != null) Padding(padding: const EdgeInsets.only(top: 10), child: btn),
          ]),
        ),
        onClose != null ? sdIconButton(p, Icons.close_rounded, '关闭', onClose, color: p.text) : const SizedBox(width: 8),
      ]),
    );
  });
}

// ---------------------------------------------------------------------------------- helper (incoming)

final _incomingShowCode = false.obs;

/// Compact "device ID + verification code" card for the employee helper (incoming-only) window.
Widget sdIncomingDeviceCard(BuildContext context) {
  final p = SdPalette(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: sdCard(
      p,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      child: Consumer<ServerModel>(builder: (context, model, _) {
        final showOneTime = model.approveMode != 'click' && model.verificationMethod != kUsePermanentPassword;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('本设备ID', style: TextStyle(fontSize: 13, color: p.muted))),
              if (!bind.isDisableSettings())
                sdIconButton(p, Icons.settings_outlined, translate('Settings'), DesktopTabPage.onAddSetting),
            ]),
            Row(children: [
              Flexible(
                child: Text(model.serverId.text,
                    maxLines: 1,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: 1, color: p.text)),
              ),
              sdIconButton(p, Icons.copy_rounded, '复制设备ID', () => sdCopy(trimID(model.serverId.text))),
            ]),
            Padding(padding: const EdgeInsets.fromLTRB(0, 8, 10, 8), child: Divider(height: 1, color: p.divider)),
            Text(showOneTime ? '验证码' : '验证方式', style: TextStyle(fontSize: 13, color: p.muted)),
            if (showOneTime)
              Obx(() => Row(children: [
                    Flexible(
                      child: Text(_incomingShowCode.value ? model.serverPasswd.text : '••••••',
                          maxLines: 1,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 1, color: p.text)),
                    ),
                    sdIconButton(p, _incomingShowCode.value ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        _incomingShowCode.value ? '隐藏验证码' : '查看验证码', () => _incomingShowCode.toggle()),
                    sdIconButton(p, Icons.copy_rounded, '复制验证码', () => sdCopy(model.serverPasswd.text)),
                    sdIconButton(p, Icons.refresh_rounded, '更换验证码', () => bind.mainUpdateTemporaryPassword()),
                  ]))
            else
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(model.approveMode == 'click' ? 'IT 连接时请在弹窗中点击“接受”' : '已设置固定密码',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text)),
              ),
          ],
        );
      }),
    ),
  );
}

// ------------------------------------------------------------------------------------------ title bar

const double sdTitleBarHeight = 48;

/// The full client's main window is never smaller than the sidebar layout needs (also enlarges a
/// smaller size saved by an older version). The helper keeps its own compact window.
Future<void> sdEnsureMainWindowSize() async {
  if (bind.isIncomingOnly()) return;
  const min = Size(940, 660);
  await windowManager.setMinimumSize(min);
  final s = await windowManager.getSize();
  if (s.width < min.width || s.height < min.height) {
    await windowManager.setSize(Size(s.width < min.width ? min.width : s.width,
        s.height < min.height ? min.height : s.height));
  }
}

Color sdTitleBarColor(BuildContext context) => SdPalette(context).side;

/// Like UU: minimise + close only on the full client (the window still resizes by its edges).
bool get sdTitleBarShowMaximize => bind.isIncomingOnly();

/// Left side of the main-window title bar: logo + product name.
Widget sdTitleBarLeading(BuildContext context) {
  final p = SdPalette(context);
  final name = superdeskOption('superdesk-display-name');
  return Row(mainAxisSize: MainAxisSize.min, children: [
    const SizedBox(width: 12),
    loadIcon(22),
    const SizedBox(width: 8),
    Text(name.isEmpty ? 'super远程桌面' : name, style: TextStyle(fontSize: 13.5, color: p.text)),
  ]);
}

/// The full client draws its own minimise / close at the end of [sdTitleBarTail], in the same style as
/// the other title-bar buttons (compatible UI mode keeps the system title bar and its buttons).
bool get sdTitleBarOwnControls => !bind.isIncomingOnly() && !kUseCompatibleUiMode && !isMacOS;

/// Right side of the main-window title bar (account + menu + window buttons); null keeps the default.
Widget? sdTitleBarTail(BuildContext context) {
  if (bind.isIncomingOnly()) return null;
  final p = SdPalette(context);
  return Row(mainAxisSize: MainAxisSize.min, children: [
    SdBarButton(SdGlyph.barScreens, '无线副屏', (_) => _extendScreenHelp()),
    sdNoticeBell(p),
    if (!bind.isDisableAccount()) _accountButton(p),
    SdBarButton(SdGlyph.barMenu, '菜单', _openMenu),
    if (sdTitleBarOwnControls) ...[
      Container(width: 1, height: 20, color: p.divider, margin: const EdgeInsets.symmetric(horizontal: 8)),
      SdBarButton(SdGlyph.barMinimize, '最小化', (_) => windowManager.minimize()),
      SdBarButton(SdGlyph.barClose, '关闭', (_) => Future.delayed(Duration.zero, () => windowManager.close()),
          danger: true),
      const SizedBox(width: 4),
    ] else
      Container(width: 1, height: 18, color: p.divider, margin: const EdgeInsets.symmetric(horizontal: 6)),
  ]);
}

/// Asks the home page to show a settings tab (used by the title-bar menu).
final sdHomeSettingsRequest = Rxn<SettingsTabKey>();

Widget _accountButton(SdPalette p) => Obx(() {
      final name = gFFI.userModel.userName.value;
      if (name.isEmpty) return SdBarButton(SdGlyph.barUser, '登录账号', (_) => loginDialog());
      return SdBarButton(SdGlyph.barUser, gFFI.userModel.displayNameOrUserName, _openAccountMenu);
    });

Future<void> _openAccountMenu(BuildContext context) async {
  final p = SdPalette(context);
  final user = gFFI.userModel;
  final shown = user.displayNameOrUserName;
  final v = await sdBarMenu<int>(context, [
    PopupMenuItem<int>(
      enabled: false,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: kSdAccent, shape: BoxShape.circle),
          child: Text(shown.isEmpty ? '?' : shown.characters.first.toUpperCase(),
              style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(shown,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: p.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(shown == user.userName.value ? '已登录' : '账号：${user.userName.value}',
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
        ),
      ]),
    ),
    const PopupMenuDivider(height: 9),
    sdBarMenuItem(p, 1, Icons.logout_rounded, '退出登录'),
  ]);
  if (v == 1) user.logOut();
}

Future<void> _openMenu(BuildContext context) async {
  final p = SdPalette(context);
  final v = await sdBarMenu<int>(context, [
    sdBarMenuItem(p, 1, Icons.file_download_outlined, '下载中心'),
    sdBarMenuItem(p, 2, Icons.add_circle_outline_rounded, '如何添加设备'),
    sdBarMenuItem(p, 3, Icons.info_outline_rounded, '关于'),
    const PopupMenuDivider(height: 9),
    sdBarMenuItem(p, 4, Icons.arrow_circle_up_rounded, '检查更新'),
  ]);
  switch (v) {
    case 1:
      final api = await sdApiServer();
      if (api.isNotEmpty) launchUrl(Uri.parse('$api/download/'));
      break;
    case 2:
      _howToAddDialog();
      break;
    case 3:
      sdHomeSettingsRequest.value = SettingsTabKey.about;
      break;
    case 4:
      final u = await superdeskCheckUpdate();
      if (u == null) {
        showToast('已是最新版本');
      } else {
        superdeskOpenUpdate(u);
      }
      break;
  }
}

void _extendScreenHelp() {
  gFFI.dialogManager.show((setState, close, context) => CustomAlertDialog(
        title: const Text('无线副屏'),
        content: const Text('把手机、平板或另一台电脑当作这台电脑的扩展屏：\n\n'
            '1. 这台电脑需要安装 super远程桌面（以服务方式运行），系统为 Windows 10 2004 或更新版本；\n'
            '2. 在那台设备的 super远程桌面 里打开这台电脑的设备页，点“更多 → 无线副屏”；\n'
            '3. 连接后会自动新增一块虚拟显示器并只显示它，断开后自动移除。'),
        actions: [dialogButton('OK', onPressed: close)],
        onSubmit: close,
        onCancel: close,
      ));
}

void _howToAddDialog() {
  gFFI.dialogManager.show((setState, close, context) => CustomAlertDialog(
        title: const Text('如何添加设备'),
        content: const Text('1. 在要远程的电脑或手机上安装 super远程桌面（菜单 → 下载中心）。\n'
            '2. 在对方设备上查看“本设备ID”和验证码，在“远程协助”页输入后点击连接。\n'
            '3. 连接过的设备会出现在“全部设备”；点设备右侧的 › 可收藏或设置备注名。\n'
            '4. 在各台设备上登录同一账号，它们会自动出现在“我的设备”；通讯录中的设备也会出现在这里。'),
        actions: [dialogButton('OK', onPressed: close)],
        onCancel: close,
        onSubmit: close,
      ));
}

// ------------------------------------------------------------------------------------------ home

enum _Page { assist, all, fav, device, settings, settingsMore }

class SuperdeskDesktopHome extends StatefulWidget {
  /// Install / update / system-error cards from DesktopHomePage.
  final Widget helpCards;
  const SuperdeskDesktopHome({Key? key, required this.helpCards}) : super(key: key);

  @override
  State<SuperdeskDesktopHome> createState() => _SuperdeskDesktopHomeState();
}

class _SuperdeskDesktopHomeState extends State<SuperdeskDesktopHome> {
  _Page _page = _Page.assist;
  String _deviceId = '';
  bool _myOpen = true;
  bool _assistOpen = true;
  SettingsTabKey _settingsTab = SettingsTabKey.general;
  Worker? _settingsWorker;

  @override
  void initState() {
    super.initState();
    SdOnline.start();
    SdSessions.start();
    SdIncoming.start();
    SdNotices.start();
    bind.mainLoadRecentPeers();
    bind.mainLoadFavPeers();
    _settingsWorker = ever<SettingsTabKey?>(sdHomeSettingsRequest, (tab) {
      if (tab != null && mounted) {
        _go(_Page.settings, tab: tab);
        sdHomeSettingsRequest.value = null;
      }
    });
  }

  @override
  void dispose() {
    _settingsWorker?.dispose();
    super.dispose();
  }

  void _go(_Page page, {String device = '', SettingsTabKey tab = SettingsTabKey.general}) {
    if (page == _Page.settings && sdSettingsTabOf(tab) == null) page = _Page.settingsMore;
    setState(() {
      _page = page;
      _deviceId = device;
      _settingsTab = tab;
    });
    if (page == _Page.all || page == _Page.fav) {
      bind.mainLoadRecentPeers();
      bind.mainLoadFavPeers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.recentPeersModel),
        ChangeNotifierProvider.value(value: gFFI.serverModel),
      ],
      child: Container(
        color: p.side,
        child: Row(children: [
          SizedBox(width: 240, child: _sidebar(p)),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: p.page,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
                border: Border.all(color: p.dark ? p.line : const Color(0xFFE6ECEF)),
              ),
              child: _body(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    switch (_page) {
      case _Page.assist:
        return _AssistPage(
            helpCards: widget.helpCards, onSecurity: () => _go(_Page.settings, tab: SettingsTabKey.safety));
      case _Page.all:
        return _AllDevicesPage(onOpen: (id) => _go(_Page.device, device: id));
      case _Page.fav:
        return _FavPage(onOpen: (id) => _go(_Page.device, device: id));
      case _Page.device:
        return _DevicePage(key: ValueKey(_deviceId), id: _deviceId, onRemoved: () => _go(_Page.all));
      case _Page.settings:
        return SdSettingsPage(
            key: ValueKey(_settingsTab),
            initialTab: sdSettingsTabOf(_settingsTab) ?? SdSettingsTab.general,
            onMore: (tab) => _go(_Page.settingsMore, tab: tab));
      case _Page.settingsMore:
        // RustDesk's full settings page. Built only while shown: it registers global controllers.
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 12, 0, 0),
            child: TextButton.icon(
              onPressed: () => _go(_Page.settings, tab: _settingsTab),
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              label: const Text('返回常用设置', style: TextStyle(fontSize: 14)),
            ),
          ),
          Expanded(
              child: DesktopSettingPage(key: ValueKey(_settingsTab), initialTabkey: _settingsTab, sdTopTabs: true)),
        ]);
    }
  }

  Widget _sidebar(SdPalette p) {
    return Column(children: [
      Obx(() => SdIncoming.count.value > 0 ? _incomingCard(SdIncoming.count.value) : const SizedBox.shrink()),
      Expanded(
        child: AnimatedBuilder(animation: sdPeersListenable, builder: (context, _) {
          return Obx(() {
            gFFI.userModel.userName.value; // address-book devices depend on the login
            final peers = sdAllPeers();
            SdOnline.want(peers.map((x) => x.id).toList());
            final online = SdOnline.ids.toSet();
            final active = SdSessions.peers.keys.toSet();
            final mine = [
              ...peers.where((x) => online.contains(x.id)),
              ...peers.where((x) => !online.contains(x.id)),
            ].take(6).toList();
            return ListView(padding: const EdgeInsets.only(top: 8), children: [
              _section(p, SdGlyph.devices, '我的设备', _myOpen, () => setState(() => _myOpen = !_myOpen)),
              if (_myOpen) ...[
                ...mine.map((x) => _item(
                      p,
                      selected: _page == _Page.device && _deviceId == x.id,
                      leading: Row(mainAxisSize: MainAxisSize.min, children: [
                        const SizedBox(width: 8),
                        Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: online.contains(x.id) ? kSdOnline : Colors.transparent,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        sdPlatformTile(x.platform, size: 20, online: online.contains(x.id)),
                      ]),
                      label: sdPeerName(x),
                      dim: !online.contains(x.id),
                      trailing: active.contains(x.id) ? _sessionBadge() : null,
                      onTap: () => _go(_Page.device, device: x.id),
                    )),
                _item(p,
                    selected: _page == _Page.all,
                    leading: _entryIcon(SdGlyph.allDevices),
                    label: '全部设备',
                    onTap: () => _go(_Page.all)),
              ],
              _section(p, SdGlyph.assist, '远程协助', _assistOpen, () => setState(() => _assistOpen = !_assistOpen)),
              if (_assistOpen) ...[
                _item(p,
                    selected: _page == _Page.assist,
                    leading: _entryIcon(SdGlyph.startAssist),
                    label: '开始协助',
                    onTap: () => _go(_Page.assist)),
                _item(p,
                    selected: _page == _Page.fav,
                    leading: _entryIcon(SdGlyph.favorites),
                    label: '收藏设备',
                    onTap: () => _go(_Page.fav)),
              ],
            ]);
          });
        }),
      ),
      if (!bind.isDisableSettings()) ...[
        Divider(height: 1, color: p.dark ? p.line : const Color(0xFFE1E6E8)),
        const SizedBox(height: 8),
        _item(p,
            selected: _page == _Page.settings || _page == _Page.settingsMore,
            leading: Padding(
                padding: const EdgeInsets.only(left: 0.5),
                child: Icon(Icons.settings_outlined, color: p.text, size: 19)),
            gap: 7,
            label: '设置',
            onTap: () => _go(_Page.settings)),
        const SizedBox(height: 8),
      ],
    ]);
  }

  /// "本机被控中" card on top of the sidebar while another device controls this one (like the reference);
  /// opens the connection-manager window.
  Widget _incomingCard(int n) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
        child: Material(
          color: const Color(0xFF3183FF),
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: SdIncoming.showWindow,
            hoverColor: Colors.white.withOpacity(0.08),
            highlightColor: Colors.white.withOpacity(0.12),
            splashColor: Colors.white24,
            child: SizedBox(
              height: 96,
              child: Stack(children: [
                Positioned(
                  right: 14,
                  bottom: -12,
                  child: Icon(Icons.connected_tv_outlined, size: 86, color: Colors.white.withOpacity(0.13)),
                ),
                const Positioned(
                  right: 10,
                  top: 10,
                  child: Tooltip(
                      message: '显示被控窗口', child: Icon(Icons.open_in_full_rounded, size: 16, color: Colors.white)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('本机被控中',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 6),
                        Text('当前有 $n 台设备正在控制此电脑',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.92))),
                      ]),
                ),
              ]),
            ),
          ),
        ),
      );

  /// "open session" badge next to a device: screen glyph + count, like the reference.
  Widget _sessionBadge() => Container(
        margin: const EdgeInsets.only(left: 6, right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
            border: Border.all(color: kSdAccent, width: 1), borderRadius: BorderRadius.circular(4)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.connected_tv_outlined, size: 12, color: kSdAccent),
          SizedBox(width: 2),
          Text('1', style: TextStyle(fontSize: 11, color: kSdAccent, height: 1.2)),
        ]),
      );

  Widget _entryIcon(SdGlyph g) => Padding(padding: const EdgeInsets.only(left: 24), child: SdIcon(g, size: 20));

  Widget _section(SdPalette p, SdGlyph glyph, String label, bool open, VoidCallback toggle) {
    return InkWell(
      onTap: toggle,
      hoverColor: Colors.transparent,
      child: SizedBox(
        height: 40,
        child: Row(children: [
          const SizedBox(width: 18),
          SdIcon(glyph, size: 19, color: p.text),
          const SizedBox(width: 7),
          Expanded(child: Text(label, style: TextStyle(fontSize: 15.5, color: p.text))),
          Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 18, color: p.muted),
          const SizedBox(width: 20),
        ]),
      ),
    );
  }

  Widget _item(SdPalette p,
      {required bool selected,
      required Widget leading,
      required String label,
      required VoidCallback onTap,
      double gap = 12,
      Widget? trailing,
      bool dim = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: selected ? p.soft : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          hoverColor: p.soft.withOpacity(0.55),
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Stack(alignment: AlignmentDirectional.centerStart, children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  child: Container(
                      width: 3,
                      decoration: BoxDecoration(color: kSdAccent, borderRadius: BorderRadius.circular(2))),
                ),
              Row(children: [
                const SizedBox(width: 14),
                leading,
                SizedBox(width: gap),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15.5, color: dim ? p.hint : p.text)),
                ),
                if (trailing != null) trailing,
                const SizedBox(width: 8),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------ page helpers

Widget _pageTitle(SdPalette p, String title, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(children: [
        Text(title, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text)),
        const Spacer(),
        if (trailing != null) trailing,
      ]),
    );

EdgeInsets get _pagePadding => const EdgeInsets.fromLTRB(40, 26, 40, 28);

// ---------------------------------------------------------------------------------- 远程协助 page

class _AssistPage extends StatefulWidget {
  final Widget helpCards;
  final VoidCallback onSecurity;
  const _AssistPage({required this.helpCards, required this.onSecurity});

  @override
  State<_AssistPage> createState() => _AssistPageState();
}

class _AssistPageState extends State<_AssistPage> {
  final _idCtrl = IDTextEditingController();
  final _showCode = false.obs;

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  void _connect() {
    final id = _idCtrl.id;
    if (id.isNotEmpty) connect(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return SingleChildScrollView(
      padding: _pagePadding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _pageTitle(p, '远程协助'),
        widget.helpCards,
        _thisDevice(p),
        const SizedBox(height: 20),
        _partner(p),
      ]),
    );
  }

  Widget _thisDevice(SdPalette p) {
    final svcStopped = Get.find<RxBool>(tag: 'stop-service');
    return sdCard(
      p,
      padding: EdgeInsets.zero,
      child: Consumer<ServerModel>(builder: (context, model, _) {
        final method = model.verificationMethod;
        final click = model.approveMode == 'click';
        final showOneTime = !click && method != kUsePermanentPassword;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 68,
            child: Row(children: [
              const SizedBox(width: 16),
              Text('本设备', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600, color: p.text)),
              const Spacer(),
              Text('允许他人远程协助', style: TextStyle(fontSize: 14.5, color: p.text)),
              const SizedBox(width: 12),
              Obx(() => SdToggle(value: !svcStopped.value, onChanged: (v) => start_service(v))),
              const SizedBox(width: 16),
            ]),
          ),
          Divider(height: 1, color: p.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 32,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('本设备ID', style: TextStyle(fontSize: 13, color: p.muted)),
                  const SizedBox(height: 10),
                  Text(model.serverId.text,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 27,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: p.text,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ),
              Expanded(
                flex: 68,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    height: 18,
                    child: Row(children: [
                      Text('验证方式：', style: TextStyle(fontSize: 13, color: p.muted)),
                      click
                          ? Text('需本机点击接受', style: TextStyle(fontSize: 13, color: p.muted))
                          : _methodMenu(p, model, method),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 36,
                    child: Row(children: [
                      Expanded(
                        child: Obx(() => Text(
                              click
                                  ? '对方连接时在弹窗中接受'
                                  : (showOneTime
                                      ? (_showCode.value ? model.serverPasswd.text : '••••••••')
                                      : '已设置固定密码'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: showOneTime ? (_showCode.value ? 26 : 22) : 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: showOneTime ? (_showCode.value ? 1.5 : 3.5) : 0,
                                  color: p.text),
                            )),
                      ),
                      if (showOneTime)
                        Obx(() => _plainIcon(
                            p,
                            _showCode.value
                                ? Icon(Icons.visibility_outlined, size: 20, color: p.text)
                                : SdClosedEye(size: 22, color: p.text),
                            _showCode.value ? '隐藏验证码' : '查看验证码',
                            () => _showCode.toggle())),
                      if (!bind.isDisableSettings())
                        _plainIcon(p, Icon(Icons.settings_outlined, size: 20, color: p.text), '安全设置',
                            widget.onSecurity),
                      const SizedBox(width: 12),
                      sdOutlineButton(p, '复制并分享', () {
                        final id = trimID(model.serverId.text);
                        sdCopy(showOneTime
                            ? '请用 super远程桌面 远程协助我：\n设备ID：$id\n验证码：${model.serverPasswd.text}'
                            : '请用 super远程桌面 远程协助我：\n设备ID：$id');
                      }, minWidth: 124),
                    ]),
                  ),
                  SizedBox(
                    height: 18,
                    child: showOneTime
                        ? Text('每次远控后自动刷新', style: TextStyle(fontSize: 12, color: p.hint))
                        : null,
                  ),
                ]),
              ),
            ]),
          ),
        ]);
      }),
    );
  }

  Widget _plainIcon(SdPalette p, Widget icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(width: 36, height: 32, child: Center(child: icon)),
        ),
      );

  Widget _methodMenu(SdPalette p, ServerModel model, String method) {
    const labels = {
      kUseTemporaryPassword: '仅使用临时验证码',
      kUsePermanentPassword: '仅使用固定密码',
      kUseBothPasswords: '临时验证码和固定密码',
    };
    return PopupMenuButton<String>(
      tooltip: '修改验证方式',
      initialValue: method,
      offset: const Offset(0, 24),
      onSelected: (v) async {
        if (v == '_refresh') {
          bind.mainUpdateTemporaryPassword();
          return;
        }
        await model.setVerificationMethod(v);
        await model.updatePasswordModel();
      },
      itemBuilder: (_) => [
        ...labels.entries.map((e) => PopupMenuItem(value: e.key, height: 36, child: Text(e.value))),
        if (method != kUsePermanentPassword) const PopupMenuDivider(),
        if (method != kUsePermanentPassword)
          const PopupMenuItem(value: '_refresh', height: 36, child: Text('立即更换验证码')),
      ],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(labels[method] ?? '', style: TextStyle(fontSize: 13, color: p.muted)),
        const SizedBox(width: 2),
        Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: p.muted),
      ]),
    );
  }

  Widget _partner(SdPalette p) {
    return sdCard(
      p,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('远控伙伴设备', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 4),
            Text('通过其他设备的【设备ID】及【设备验证码】启动远程控制', style: TextStyle(fontSize: 13, color: p.muted)),
          ]),
        ),
        Divider(height: 1, color: p.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 26),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('伙伴的设备ID', style: TextStyle(fontSize: 13, color: p.muted)),
            const SizedBox(height: 12),
            Row(children: [
              SdTextBox(
                controller: _idCtrl,
                hint: '请输入设备ID',
                width: 170,
                inputFormatters: [IDTextInputFormatter()],
                onSubmitted: (_) => _connect(),
              ),
              const SizedBox(width: 13),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _idCtrl,
                builder: (context, v, _) =>
                    sdPrimaryButton(p, '连接', v.text.trim().isEmpty ? null : _connect, height: 32, minWidth: 124),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------- device rows

Widget _deviceRow(SdPalette p, Peer x,
    {required bool online, bool self = false, required void Function(String id) onOpen}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: p.card,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        hoverColor: p.soft.withOpacity(0.35),
        onTap: self ? null : () => onOpen(x.id),
        onDoubleTap: self ? null : () => connect(Get.context!, x.id),
        child: Container(
          height: 54,
          padding: const EdgeInsets.only(left: 16, right: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line)),
          child: Row(children: [
            sdPlatformTile(x.platform, size: 32, online: self || online),
            const SizedBox(width: 13),
            Flexible(
              child: Text(sdPeerName(x),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, color: p.text)),
            ),
            if (self)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: p.badge, borderRadius: BorderRadius.circular(2)),
                child: const Text('本机', style: TextStyle(fontSize: 11, color: kSdAccent, height: 1.3)),
              ),
            if (!self && online)
              Container(
                  margin: const EdgeInsets.only(left: 8),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: kSdOnline, shape: BoxShape.circle)),
            const Spacer(),
            sdIconButton(p, Icons.info_outline, '设备信息', () => sdPeerInfoDialog(x), color: p.text, size: 20),
            SizedBox(
              width: 44,
              child: self ? null : Icon(Icons.chevron_right, color: p.text, size: 20),
            ),
          ]),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------------- 全部设备 page

class _AllDevicesPage extends StatefulWidget {
  final void Function(String id) onOpen;
  const _AllDevicesPage({required this.onOpen});

  @override
  State<_AllDevicesPage> createState() => _AllDevicesPageState();
}

class _AllDevicesPageState extends State<_AllDevicesPage> {
  bool _pcOpen = true;
  bool _mobileOpen = true;
  bool _tip = bind.mainGetLocalOption(key: 'sd-hide-add-device-tip') != 'Y';

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return AnimatedBuilder(animation: sdPeersListenable, builder: (context, _) {
      return Obx(() {
        gFFI.userModel.userName.value;
        final online = SdOnline.ids.toSet();
        final self = sdSelfPeer();
        final peers = sdAllPeers().where((x) => x.id != self.id).toList();
        final pcs = [self, ...peers.where((x) => !sdIsMobilePlatform(x.platform))];
        final mobiles = peers.where((x) => sdIsMobilePlatform(x.platform)).toList();
        return ListView(padding: _pagePadding, children: [
          _pageTitle(p, '全部设备'),
          if (_tip)
            sdBanner(context,
                title: '添加你的其他设备',
                content: '在其他电脑或手机上安装 super远程桌面并登录同一账号，设备会自动显示在这里；连接过、收藏或加入通讯录的设备也会显示。',
                button: '如何添加设备',
                onPressed: _howToAddDialog, onClose: () {
              bind.mainSetLocalOption(key: 'sd-hide-add-device-tip', value: 'Y');
              setState(() => _tip = false);
            }),
          _group(p, '电脑', pcs.length, _pcOpen, () => setState(() => _pcOpen = !_pcOpen)),
          if (_pcOpen)
            ...pcs.map((x) => _deviceRow(p, x,
                online: online.contains(x.id), self: identical(x, self), onOpen: widget.onOpen)),
          if (mobiles.isNotEmpty) ...[
            _group(p, '手机/平板', mobiles.length, _mobileOpen, () => setState(() => _mobileOpen = !_mobileOpen)),
            if (_mobileOpen)
              ...mobiles.map((x) => _deviceRow(p, x, online: online.contains(x.id), onOpen: widget.onOpen)),
          ],
        ]);
      });
    });
  }

  Widget _group(SdPalette p, String label, int n, bool open, VoidCallback toggle) => InkWell(
        onTap: toggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
          child: Row(children: [
            Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                size: 20, color: p.text),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 15, color: p.text)),
            const SizedBox(width: 6),
            Text('$n', style: TextStyle(fontSize: 15, color: p.muted)),
          ]),
        ),
      );
}

// ---------------------------------------------------------------------------------- 收藏设备 page

class _FavPage extends StatelessWidget {
  final void Function(String id) onOpen;
  const _FavPage({required this.onOpen});

  void _addDialog() {
    final ctrl = IDTextEditingController();
    gFFI.dialogManager.show((setState, close, context) {
      submit() async {
        final id = ctrl.id;
        if (id.isEmpty) return;
        await sdSetFav(id, true);
        close();
      }

      return CustomAlertDialog(
        title: const Text('添加收藏设备'),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            inputFormatters: [IDTextInputFormatter()],
            decoration: sdInputDecoration(SdPalette(context), '请输入设备ID'),
            onSubmitted: (_) => submit(),
          ),
        ),
        actions: [dialogButton('Cancel', onPressed: close, isOutline: true), dialogButton('OK', onPressed: submit)],
        onCancel: close,
        onSubmit: submit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return ChangeNotifierProvider.value(
      value: gFFI.favoritePeersModel,
      child: Consumer<Peers>(builder: (context, model, _) {
        return Obx(() {
          final online = SdOnline.ids.toSet();
          final favs = model.peers;
          return ListView(padding: _pagePadding, children: [
            _pageTitle(p, '收藏设备', trailing: sdOutlineButton(p, '添加收藏设备', _addDialog)),
            if (favs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 120),
                child: Column(children: [
                  const SdIcon(SdGlyph.emptyBox, size: 104),
                  const SizedBox(height: 14),
                  Text('暂无收藏', style: TextStyle(fontSize: 15, color: p.text)),
                ]),
              )
            else
              ...favs.map((x) => _deviceRow(p, x, online: online.contains(x.id), onOpen: onOpen)),
          ]);
        });
      }),
    );
  }
}

// ---------------------------------------------------------------------------------- device page

class _DevicePage extends StatefulWidget {
  final String id;
  final VoidCallback onRemoved;
  const _DevicePage({Key? key, required this.id, required this.onRemoved}) : super(key: key);

  @override
  State<_DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<_DevicePage> {
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    sdIsFav(widget.id).then((v) {
      if (mounted) setState(() => _fav = v);
    });
  }

  Peer get _peer =>
      sdAllPeers().firstWhereOrNull((x) => x.id == widget.id) ?? Peer.fromJson({'id': widget.id});

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return AnimatedBuilder(animation: sdPeersListenable, builder: (context, _) {
      return Obx(() {
        final x = _peer;
        final online = SdOnline.ids.contains(x.id);
        return ListView(padding: _pagePadding, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: online ? const Color(0xFF191919) : p.soft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (online)
                    Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: const BoxDecoration(color: kSdOnline, shape: BoxShape.circle)),
                  Text(online ? '在线' : '离线',
                      style: TextStyle(fontSize: 12.5, color: online ? Colors.white : p.muted)),
                ]),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(sdPeerName(x),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text)),
              ),
              _moreMenu(p, x),
            ]),
          ),
          if (SdSessions.peers.containsKey(x.id)) _sessionBanner(p, x),
          _preview(p, x, online, connected: SdSessions.peers.containsKey(x.id)),
          const SizedBox(height: 22),
          if (x.platform == kPeerPlatformWindows) SdQuickLaunchSection(key: ValueKey(x.id), peerId: x.id),
          if (x.platform != kPeerPlatformWindows) ...[
          Text('设备信息', style: TextStyle(fontSize: 15, color: p.text)),
          const SizedBox(height: 10),
          sdCard(
            p,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(children: [
              _info(p, '设备ID', formatID(x.id)),
              if (x.hostname.isNotEmpty) _info(p, '设备名称', x.hostname),
              if (x.username.isNotEmpty) _info(p, '用户名', x.username),
              if (x.platform.isNotEmpty) _info(p, '系统', x.platform),
            ]),
          ),
          ],
        ]);
      });
    });
  }

  Widget _info(SdPalette p, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 90, child: Text(k, style: TextStyle(fontSize: 13.5, color: p.muted))),
          Expanded(child: SelectableText(v, style: TextStyle(fontSize: 13.5, color: p.text))),
        ]),
      );

  /// Shown while this device has an open session window (light blue bar, like the reference).
  Widget _sessionBanner(SdPalette p, Peer x) => Container(
        height: 46,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: BoxDecoration(
          color: p.dark ? const Color(0xFF1D2B45) : const Color(0xFFE6F0FF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(children: [
          const Icon(Icons.connected_tv_outlined, size: 20, color: kSdAccent),
          const SizedBox(width: 8),
          const Text('被控中', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kSdAccent)),
          Container(width: 1, height: 14, color: kSdAccent.withOpacity(0.35), margin: const EdgeInsets.symmetric(horizontal: 12)),
          const Expanded(
              child: Text('本机正在控制此电脑', style: TextStyle(fontSize: 14, color: kSdAccent))),
          sdOutlineButton(p, '断开所有远控', () => SdSessions.close(x.id), minWidth: 0, height: 28),
          const SizedBox(width: 6),
          sdIconButton(p, Icons.keyboard_arrow_down, '显示远控窗口', () => SdSessions.show(x.id),
              color: kSdAccent, size: 20),
        ]),
      );

  Widget _preview(SdPalette p, Peer x, bool online, {bool connected = false}) {
    final colors = online
        ? const [Color(0xFF00A2FF), Color(0xFF0057D9), Color(0xFF00328A)]
        : const [Color(0xFF9AA3AE), Color(0xFF6E7781), Color(0xFF4F565E)];
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 19, color: p.text),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 15, color: p.text)),
              ]),
            ),
          ),
        );
    Widget sep() => Container(width: 1, height: 22, color: p.divider);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line)),
      child: Column(children: [
        InkWell(
          onTap: connected ? () => SdSessions.show(x.id) : () => sdConnectMode(context, x.id, viewOnly: false),
          child: Container(
            height: 240,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Stack(children: [
              Positioned(
                right: 150,
                top: 46,
                child: sdPlatformIcon(x.platform, size: 140, color: Colors.white.withOpacity(0.3)),
              ),
              Positioned.fill(child: SdWallpaper(id: x.id, online: online)),
              if (!connected && !online) Center(child: sdWakeButton(x.id)),
              if (!connected && online)
                const Align(
                  alignment: Alignment(0, 0.58),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('进入桌面', style: TextStyle(fontSize: 17, color: Colors.white)),
                    SizedBox(width: 12),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                  ]),
                )
              else if (connected) ...[
                Positioned.fill(child: Container(color: Colors.black.withOpacity(0.38))),
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.connected_tv_outlined, size: 54, color: Colors.white),
                    const SizedBox(height: 8),
                    const Text('已建立远程连接', style: TextStyle(fontSize: 14.5, color: Colors.white)),
                    const SizedBox(height: 14),
                    sdPrimaryButton(p, '显示远控窗口', () => SdSessions.show(x.id), height: 32, minWidth: 124),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        Container(
          color: p.card,
          child: Row(children: [
            action(Icons.drive_folder_upload_outlined, '文件传输', () => connect(context, x.id, isFileTransfer: true)),
            sep(),
            action(Icons.smart_display_outlined, '观看模式', () => sdConnectMode(context, x.id, viewOnly: true)),
            sep(),
            action(Icons.terminal_rounded, '终端', () => connect(context, x.id, isTerminal: true)),
            sep(),
            action(Icons.compare_arrows_rounded, '端口映射', () => connect(context, x.id, isTcpTunneling: true)),
            sep(),
            SizedBox(
              width: 64,
              child: PopupMenuButton<int>(
                tooltip: '更多',
                icon: Icon(Icons.grid_view_rounded, color: p.text, size: 20),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 3, child: Text('远程摄像头')),
                  if (x.platform.toLowerCase().contains('windows'))
                    const PopupMenuItem(value: 1, child: Text('RDP 远程桌面')),
                  if (x.platform == kPeerPlatformWindows) const PopupMenuItem(value: 4, child: Text('无线副屏')),
                  const PopupMenuItem(value: 2, child: Text('复制设备ID')),
                ],
                onSelected: (v) {
                  if (v == 4) sdStartExtendScreen(context, x.id);
                  if (v == 1) connect(context, x.id, isRDP: true);
                  if (v == 2) sdCopy(x.id);
                  if (v == 3) connect(context, x.id, isViewCamera: true);
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _moreMenu(SdPalette p, Peer x) => PopupMenuButton<int>(
        tooltip: '更多操作',
        icon: Icon(Icons.more_vert_rounded, color: p.text),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 1, child: Text('修改备注名')),
          PopupMenuItem(value: 2, child: Text(_fav ? '取消收藏' : '收藏')),
          const PopupMenuItem(value: 3, child: Text('复制设备ID')),
          const PopupMenuItem(value: 4, child: Text('删除连接记录', style: TextStyle(color: Colors.red))),
        ],
        onSelected: (v) async {
          switch (v) {
            case 1:
              renameDialog(
                  oldName: x.alias,
                  onSubmit: (name) async {
                    await bind.mainSetPeerAlias(id: x.id, alias: name);
                    bind.mainLoadRecentPeers();
                    bind.mainLoadFavPeers();
                  });
              break;
            case 2:
              await sdSetFav(x.id, !_fav);
              if (mounted) setState(() => _fav = !_fav);
              break;
            case 3:
              sdCopy(x.id);
              break;
            case 4:
              await bind.mainRemovePeer(id: x.id);
              await sdSetFav(x.id, false);
              bind.mainLoadRecentPeers();
              widget.onRemoved();
              break;
          }
        },
      );
}
