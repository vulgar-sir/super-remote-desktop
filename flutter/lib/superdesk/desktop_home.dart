// super远程桌面: main-window layout in the UU-remote-like style -- grey sidebar ("我的设备" / "远程协助" /
// "设置"), title-bar widgets, and the pages: 远程协助 (this device's ID + verification code, connect to a
// partner), 全部设备, 收藏设备, device details, settings. Only the presentation is new: connections,
// passwords, favourites and settings all go through the existing models and FFI calls.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'devices.dart';
import 'superdesk.dart';
import 'theme.dart';

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

/// Right side of the main-window title bar (account + menu); null keeps the default.
Widget? sdTitleBarTail(BuildContext context) {
  if (bind.isIncomingOnly()) return null;
  final p = SdPalette(context);
  return Row(mainAxisSize: MainAxisSize.min, children: [
    if (!bind.isDisableAccount()) _accountButton(p),
    _menuButton(context, p),
    Container(width: 1, height: 18, color: p.divider, margin: const EdgeInsets.symmetric(horizontal: 6)),
  ]);
}

/// Asks the home page to show a settings tab (used by the title-bar menu).
final sdHomeSettingsRequest = Rxn<SettingsTabKey>();

Widget _accountButton(SdPalette p) => Obx(() {
      final name = gFFI.userModel.userName.value;
      if (name.isEmpty) {
        return sdIconButton(p, Icons.person_outline_rounded, '登录账号', () => loginDialog(), color: p.text, size: 21);
      }
      return PopupMenuButton<int>(
        tooltip: name,
        offset: const Offset(0, 40),
        icon: Icon(Icons.person_rounded, color: kSdAccent, size: 21),
        itemBuilder: (_) => [
          PopupMenuItem(enabled: false, child: Text(name, style: TextStyle(color: p.text, fontWeight: FontWeight.w600))),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 1, child: Text('退出登录')),
        ],
        onSelected: (v) {
          if (v == 1) gFFI.userModel.logOut();
        },
      );
    });

Widget _menuButton(BuildContext context, SdPalette p) => PopupMenuButton<int>(
      tooltip: '菜单',
      offset: const Offset(0, 40),
      icon: Icon(Icons.menu_rounded, color: p.text, size: 21),
      itemBuilder: (_) => [
        _menuItem(1, Icons.download_for_offline_outlined, '下载中心'),
        _menuItem(2, Icons.help_outline_rounded, '如何添加设备'),
        _menuItem(3, Icons.info_outline_rounded, '关于'),
        const PopupMenuDivider(),
        _menuItem(4, Icons.upgrade_rounded, '检查更新'),
      ],
      onSelected: (v) async {
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
      },
    );

PopupMenuItem<int> _menuItem(int v, IconData icon, String label) => PopupMenuItem(
      value: v,
      height: 40,
      child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Text(label)]),
    );

void _howToAddDialog() {
  gFFI.dialogManager.show((setState, close, context) => CustomAlertDialog(
        title: const Text('如何添加设备'),
        content: const Text('1. 在要远程的电脑或手机上安装 super远程桌面（菜单 → 下载中心）。\n'
            '2. 在对方设备上查看“本设备ID”和验证码，在“远程协助”页输入后点击连接。\n'
            '3. 连接过的设备会出现在“全部设备”；点设备右侧的 › 可收藏或设置备注名。\n'
            '4. 登录账号后，通讯录中的设备也会出现在这里。'),
        actions: [dialogButton('OK', onPressed: close)],
        onCancel: close,
        onSubmit: close,
      ));
}

// ------------------------------------------------------------------------------------------ home

enum _Page { assist, all, fav, device, settings }

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
        // Built only while shown: the settings page registers global controllers.
        return DesktopSettingPage(key: ValueKey(_settingsTab), initialTabkey: _settingsTab, sdTopTabs: true);
    }
  }

  Widget _sidebar(SdPalette p) {
    return Column(children: [
      Expanded(
        child: AnimatedBuilder(animation: sdPeersListenable, builder: (context, _) {
          return Obx(() {
            gFFI.userModel.userName.value; // address-book devices depend on the login
            final peers = sdAllPeers();
            SdOnline.want(peers.map((x) => x.id).toList());
            final online = SdOnline.ids.toSet();
            final mine = peers.take(6).toList();
            return ListView(padding: const EdgeInsets.only(top: 6), children: [
              _section(p, Icons.devices_outlined, '我的设备', _myOpen, () => setState(() => _myOpen = !_myOpen)),
              if (_myOpen) ...[
                ...mine.map((x) => _item(
                      p,
                      selected: _page == _Page.device && _deviceId == x.id,
                      leading: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: online.contains(x.id) ? kSdOnline : Colors.transparent,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        sdPlatformTile(x.platform, size: 22, online: online.contains(x.id)),
                      ]),
                      label: sdPeerName(x),
                      dim: !online.contains(x.id),
                      onTap: () => _go(_Page.device, device: x.id),
                    )),
                _item(p,
                    selected: _page == _Page.all,
                    leading: const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Icon(Icons.apps_rounded, color: kSdAccent, size: 22)),
                    label: '全部设备',
                    onTap: () => _go(_Page.all)),
              ],
              _section(p, Icons.screen_share_outlined, '远程协助', _assistOpen,
                  () => setState(() => _assistOpen = !_assistOpen)),
              if (_assistOpen) ...[
                _item(p,
                    selected: _page == _Page.assist,
                    leading: const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Icon(Icons.connected_tv_rounded, color: kSdAccent, size: 22)),
                    label: '开始协助',
                    onTap: () => _go(_Page.assist)),
                _item(p,
                    selected: _page == _Page.fav,
                    leading: const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Icon(Icons.bookmark_rounded, color: kSdAccent, size: 22)),
                    label: '收藏设备',
                    onTap: () => _go(_Page.fav)),
              ],
            ]);
          });
        }),
      ),
      if (!bind.isDisableSettings()) ...[
        Divider(height: 1, color: p.dark ? p.line : const Color(0xFFE1E6E8)),
        const SizedBox(height: 6),
        _item(p,
            selected: _page == _Page.settings,
            leading: Icon(Icons.settings_outlined, color: p.text, size: 20),
            label: '设置',
            onTap: () => _go(_Page.settings)),
        const SizedBox(height: 6),
      ],
    ]);
  }

  Widget _section(SdPalette p, IconData icon, String label, bool open, VoidCallback toggle) {
    return InkWell(
      onTap: toggle,
      child: SizedBox(
        height: 44,
        child: Row(children: [
          const SizedBox(width: 18),
          Icon(icon, size: 19, color: p.text),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: p.text))),
          Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 20, color: p.muted),
          const SizedBox(width: 18),
        ]),
      ),
    );
  }

  Widget _item(SdPalette p,
      {required bool selected,
      required Widget leading,
      required String label,
      required VoidCallback onTap,
      bool dim = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: selected ? p.soft : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          hoverColor: p.soft.withOpacity(0.6),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Stack(children: [
              if (selected)
                Positioned(
                  left: 0,
                  top: 11,
                  bottom: 11,
                  child: Container(
                      width: 3,
                      decoration: BoxDecoration(color: kSdAccent, borderRadius: BorderRadius.circular(2))),
                ),
              Row(children: [
                const SizedBox(width: 14),
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: dim ? p.muted : p.text)),
                ),
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
            height: 64,
            child: Row(children: [
              const SizedBox(width: 20),
              Text('本设备', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text)),
              const Spacer(),
              Text('允许他人远程协助', style: TextStyle(fontSize: 14, color: p.text)),
              const SizedBox(width: 6),
              Obx(() => sdSwitch(p, !svcStopped.value, (v) => start_service(v), caption: false)),
              const SizedBox(width: 12),
            ]),
          ),
          Divider(height: 1, color: p.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('本设备ID', style: TextStyle(fontSize: 13, color: p.muted)),
                  const SizedBox(height: 8),
                  Text(model.serverId.text,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: p.text,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ),
              Expanded(
                flex: 7,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('验证方式：', style: TextStyle(fontSize: 13, color: p.muted)),
                    click
                        ? Text('需本机点击接受', style: TextStyle(fontSize: 13, color: p.muted))
                        : _methodMenu(p, model, method),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 6, children: [
                    Obx(() => Text(
                          click
                              ? '对方连接时在弹窗中接受'
                              : (showOneTime
                                  ? (_showCode.value ? model.serverPasswd.text : '••••••••')
                                  : '已设置固定密码'),
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: showOneTime ? 24 : 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: showOneTime ? 1.5 : 0,
                              color: p.text),
                        )),
                    const SizedBox(width: 8),
                    if (showOneTime)
                      Obx(() => sdIconButton(
                          p,
                          _showCode.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          _showCode.value ? '隐藏验证码' : '查看验证码',
                          () => _showCode.toggle(),
                          color: p.text)),
                    if (showOneTime)
                      sdIconButton(p, Icons.refresh_rounded, '更换验证码', () => bind.mainUpdateTemporaryPassword(),
                          color: p.text),
                    if (!bind.isDisableSettings())
                      sdIconButton(p, Icons.settings_outlined, '安全设置', widget.onSecurity, color: p.text),
                    const SizedBox(width: 8),
                    sdOutlineButton(p, '复制并分享', () {
                      final id = trimID(model.serverId.text);
                      sdCopy(showOneTime
                          ? '请用 super远程桌面 远程协助我：\n设备ID：$id\n验证码：${model.serverPasswd.text}'
                          : '请用 super远程桌面 远程协助我：\n设备ID：$id');
                    }),
                  ]),
                  if (showOneTime)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('每次远控后自动刷新', style: TextStyle(fontSize: 12, color: p.hint)),
                    ),
                ]),
              ),
            ]),
          ),
        ]);
      }),
    );
  }

  Widget _methodMenu(SdPalette p, ServerModel model, String method) {
    const labels = {
      kUseTemporaryPassword: '仅使用临时验证码',
      kUsePermanentPassword: '仅使用固定密码',
      kUseBothPasswords: '临时验证码和固定密码',
    };
    return PopupMenuButton<String>(
      tooltip: '修改验证方式',
      initialValue: method,
      offset: const Offset(0, 28),
      onSelected: (v) async {
        await model.setVerificationMethod(v);
        await model.updatePasswordModel();
      },
      itemBuilder: (_) =>
          labels.entries.map((e) => PopupMenuItem(value: e.key, height: 38, child: Text(e.value))).toList(),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(labels[method] ?? '', style: TextStyle(fontSize: 13, color: p.muted)),
        Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: p.muted),
      ]),
    );
  }

  Widget _partner(SdPalette p) {
    return sdCard(
      p,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('远控伙伴设备', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 6),
            Text('通过其他设备的【设备ID】及【设备验证码】启动远程控制', style: TextStyle(fontSize: 13, color: p.muted)),
          ]),
        ),
        Divider(height: 1, color: p.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('伙伴的设备ID', style: TextStyle(fontSize: 13, color: p.muted)),
            const SizedBox(height: 10),
            Row(children: [
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _idCtrl,
                  inputFormatters: [IDTextInputFormatter()],
                  onSubmitted: (_) => _connect(),
                  style: TextStyle(fontSize: 15, color: p.text),
                  decoration: sdInputDecoration(p, '请输入设备ID'),
                ),
              ),
              const SizedBox(width: 16),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _idCtrl,
                builder: (context, v, _) =>
                    sdPrimaryButton(p, '连接', v.text.trim().isEmpty ? null : _connect, height: 38, minWidth: 140),
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
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: p.card,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: self ? null : () => onOpen(x.id),
        onDoubleTap: self ? null : () => connect(Get.context!, x.id),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line)),
          child: Row(children: [
            sdPlatformTile(x.platform, size: 34, online: self || online),
            const SizedBox(width: 16),
            Flexible(
              child: Text(sdPeerName(x),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: p.text)),
            ),
            if (self)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: p.badge, borderRadius: BorderRadius.circular(3)),
                child: const Text('本机', style: TextStyle(fontSize: 11.5, color: kSdAccent)),
              ),
            if (!self && online)
              Container(
                  margin: const EdgeInsets.only(left: 8),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(color: kSdOnline, shape: BoxShape.circle)),
            const Spacer(),
            sdIconButton(p, Icons.info_outline_rounded, '设备信息', () => sdPeerInfoDialog(x), color: p.text),
            SizedBox(
              width: 34,
              child: self ? null : Icon(Icons.chevron_right_rounded, color: p.text, size: 22),
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
                content: '在其他电脑或手机上安装 super远程桌面，连接过、收藏或加入通讯录的设备会显示在这里。',
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
                  Icon(Icons.inventory_2_rounded, size: 96, color: kSdAccent.withOpacity(0.32)),
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
          _preview(p, x, online),
          const SizedBox(height: 22),
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

  Widget _preview(SdPalette p, Peer x, bool online) {
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
          onTap: () => connect(context, x.id),
          child: Container(
            height: 300,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Stack(children: [
              Positioned(
                right: 120,
                top: 70,
                child: sdPlatformIcon(x.platform, size: 150, color: Colors.white.withOpacity(0.28)),
              ),
              const Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('进入桌面', style: TextStyle(fontSize: 18, color: Colors.white)),
                  SizedBox(width: 12),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 22),
                ]),
              ),
            ]),
          ),
        ),
        Container(
          color: p.card,
          child: Row(children: [
            action(Icons.drive_folder_upload_outlined, '文件传输', () => connect(context, x.id, isFileTransfer: true)),
            sep(),
            action(Icons.videocam_outlined, '远程摄像头', () => connect(context, x.id, isViewCamera: true)),
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
                  if (x.platform.toLowerCase().contains('windows'))
                    const PopupMenuItem(value: 1, child: Text('RDP 远程桌面')),
                  const PopupMenuItem(value: 2, child: Text('复制设备ID')),
                ],
                onSelected: (v) {
                  if (v == 1) connect(context, x.id, isRDP: true);
                  if (v == 2) sdCopy(x.id);
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
