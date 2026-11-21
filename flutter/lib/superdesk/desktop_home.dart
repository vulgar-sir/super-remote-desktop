// super远程桌面: main-window layout -- sidebar navigation + "device code / verification code" card,
// "control a partner device" card and recent connections. Only the presentation changes:
// DesktopHomePage keeps all its non-visual logic and renders this widget in build().

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

export 'theme.dart';

/// Notice banner (install / update / permissions / errors) in the main-window style.
Widget sdBanner(BuildContext context,
    {required String title,
    required String content,
    String? button,
    GestureTapCallback? onPressed,
    VoidCallback? onClose,
    String? help,
    String? link}) {
  final p = SdPalette(context);
  final btn = button == null
      ? null
      : ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: kSdAccent,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          child: Text(button),
        );
  return LayoutBuilder(builder: (context, box) {
    final narrow = box.maxWidth < 420; // the compact helper window
    final texts = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: p.text, fontSize: 13.5)),
              if (content.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: title.isEmpty ? 0 : 2),
                  child: Text(content, style: TextStyle(color: p.text.withOpacity(0.85), fontSize: 13)),
                ),
              if (help != null && link != null)
                InkWell(
                  onTap: () => launchUrl(Uri.parse(link)),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(help, style: const TextStyle(color: kSdAccent, fontSize: 12.5)),
                  ),
                ),
            ],
          );
    final close = onClose != null ? sdIconButton(p, Icons.close_rounded, '关闭', onClose) : const SizedBox(width: 8);
    return Container(
      margin: narrow ? const EdgeInsets.fromLTRB(16, 12, 16, 0) : const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
      decoration: BoxDecoration(
        color: p.soft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSdAccent.withOpacity(0.25)),
      ),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.campaign_outlined, color: kSdAccent, size: 20)),
                const SizedBox(width: 10),
                Expanded(child: texts),
                close,
              ]),
              if (btn != null) Padding(padding: const EdgeInsets.fromLTRB(30, 10, 10, 2), child: btn),
            ])
          : Row(children: [
              const Icon(Icons.campaign_outlined, color: kSdAccent, size: 22),
              const SizedBox(width: 12),
              Expanded(child: texts),
              if (btn != null) ...[const SizedBox(width: 12), btn],
              close,
            ]),
    );
  });
}

final _incomingShowCode = false.obs;

/// Compact "device code + verification code" card for the employee helper (incoming-only) window.
Widget sdIncomingDeviceCard(BuildContext context) {
  final p = SdPalette(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
    child: sdCard(
      p,
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
      child: Consumer<ServerModel>(builder: (context, model, _) {
        final showOneTime = model.approveMode != 'click' && model.verificationMethod != kUsePermanentPassword;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('本机设备代码', style: TextStyle(fontSize: 13, color: p.muted))),
              if (!bind.isDisableSettings())
                sdIconButton(p, Icons.settings_outlined, translate('Settings'), DesktopTabPage.onAddSetting),
            ]),
            Row(children: [
              Flexible(
                child: Text(model.serverId.text,
                    maxLines: 1,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: 1, color: p.text)),
              ),
              sdIconButton(p, Icons.copy_rounded, '复制设备代码', () => sdCopy(trimID(model.serverId.text))),
            ]),
            Padding(padding: const EdgeInsets.fromLTRB(0, 8, 10, 8), child: Divider(height: 1, color: p.line)),
            Text(showOneTime ? '验证码' : '验证方式', style: TextStyle(fontSize: 13, color: p.muted)),
            if (showOneTime)
              Obx(() => Row(children: [
                    Flexible(
                      child: Text(_incomingShowCode.value ? model.serverPasswd.text : '••••••',
                          maxLines: 1,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 1, color: p.text)),
                    ),
                    sdIconButton(p, _incomingShowCode.value ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        _incomingShowCode.value ? '隐藏验证码' : '显示验证码', () => _incomingShowCode.toggle()),
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

class SuperdeskDesktopHome extends StatefulWidget {
  /// Install / update / system-error cards from DesktopHomePage.
  final Widget helpCards;
  const SuperdeskDesktopHome({Key? key, required this.helpCards}) : super(key: key);

  @override
  State<SuperdeskDesktopHome> createState() => _SuperdeskDesktopHomeState();
}

class _SuperdeskDesktopHomeState extends State<SuperdeskDesktopHome> {
  int _nav = 0;
  SettingsTabKey _settingsTab = SettingsTabKey.general;

  void _go(int i, {SettingsTabKey tab = SettingsTabKey.general}) {
    setState(() {
      _nav = i;
      _settingsTab = tab;
    });
    if (i == 0) bind.mainLoadRecentPeers();
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return Container(
      color: p.page,
      child: Row(
        children: [
          _sidebar(p),
          Container(width: 1, color: p.line),
          Expanded(
            child: _nav == 2
                // Built only while shown: the settings page registers global controllers.
                ? DesktopSettingPage(key: ValueKey(_settingsTab), initialTabkey: _settingsTab)
                : IndexedStack(
                    index: _nav,
                    children: [
                      _RemotePage(
                        helpCards: widget.helpCards,
                        onAllDevices: () => _go(1),
                        onEditPassword: () => _go(2, tab: SettingsTabKey.safety),
                      ),
                      const _DevicesPage(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sidebar(SdPalette p) {
    return Container(
      width: 184,
      color: p.side,
      child: Column(
        children: [
          const SizedBox(height: 14),
          _navItem(p, 0, Icons.screen_share_outlined, '远程控制'),
          _navItem(p, 1, Icons.devices_other_outlined, '设备列表'),
          if (!bind.isDisableSettings()) _navItem(p, 2, Icons.settings_outlined, '设置'),
          const Spacer(),
          _account(p),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: loadPowered(context)),
        ],
      ),
    );
  }

  Widget _navItem(SdPalette p, int i, IconData icon, String label) {
    final sel = _nav == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: sel ? p.soft : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: kSdAccent.withOpacity(0.06),
          highlightColor: kSdAccent.withOpacity(0.08),
          onTap: () => _go(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: sel ? kSdAccent : p.muted),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                        color: sel ? kSdAccent : p.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _account(SdPalette p) {
    if (bind.isDisableAccount()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Obx(() {
        final name = gFFI.userModel.userName.value;
        if (name.isEmpty) {
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => loginDialog(),
              icon: const Icon(Icons.person_outline, size: 18),
              label: const Text('登录账号'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kSdAccent,
                side: BorderSide(color: p.line),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          decoration: BoxDecoration(color: p.page, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: kSdAccent,
                child: Text(name.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.text, fontWeight: FontWeight.w500))),
              sdIconButton(p, Icons.logout_rounded, '退出登录', () => gFFI.userModel.logOut()),
            ],
          ),
        );
      }),
    );
  }
}

class _RemotePage extends StatefulWidget {
  final Widget helpCards;
  final VoidCallback onAllDevices;
  final VoidCallback onEditPassword;
  const _RemotePage({required this.helpCards, required this.onAllDevices, required this.onEditPassword});

  @override
  State<_RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<_RemotePage> {
  final _idCtrl = IDTextEditingController();
  final _showCode = false.obs;

  @override
  void initState() {
    super.initState();
    bind.mainLoadRecentPeers();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  void _connect({bool file = false}) {
    final id = _idCtrl.id;
    if (id.isEmpty) {
      showToast('请输入伙伴的设备代码');
      return;
    }
    connect(context, id, isFileTransfer: file);
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.helpCards,
          const SizedBox(height: 6),
          _thisDevice(p),
          const SizedBox(height: 16),
          _controlCard(p),
          const SizedBox(height: 24),
          _recent(p),
        ],
      ),
    );
  }

  Widget _thisDevice(SdPalette p) {
    return sdCard(
      p,
      child: ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(builder: (context, model, _) {
          final showOneTime =
              model.approveMode != 'click' && model.verificationMethod != kUsePermanentPassword;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.desktop_windows_rounded, size: 18, color: kSdAccent),
                  const SizedBox(width: 8),
                  Text('本机设备',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
                  const Spacer(),
                  const OnlineStatusWidget(),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: sdCodeField(p, label: '设备代码', value: model.serverId.text, actions: [
                      sdIconButton(p, Icons.copy_rounded, '复制设备代码', () => sdCopy(trimID(model.serverId.text))),
                    ]),
                  ),
                  Container(width: 1, height: 62, color: p.line, margin: const EdgeInsets.symmetric(horizontal: 24)),
                  Expanded(
                    child: showOneTime
                        ? Obx(() => sdCodeField(p,
                                label: '验证码',
                                value: _showCode.value ? model.serverPasswd.text : '••••••',
                                actions: [
                                  sdIconButton(
                                      p,
                                      _showCode.value ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      _showCode.value ? '隐藏验证码' : '显示验证码',
                                      () => _showCode.toggle()),
                                  sdIconButton(p, Icons.copy_rounded, '复制验证码', () => sdCopy(model.serverPasswd.text)),
                                  sdIconButton(p, Icons.refresh_rounded, '更换验证码', () => bind.mainUpdateTemporaryPassword()),
                                ]))
                        : sdCodeField(p,
                            label: '验证方式',
                            size: 18,
                            value: model.approveMode == 'click' ? '需在本机点击“接受”' : '已设置固定密码',
                            actions: [
                              if (!bind.isDisableSettings())
                                TextButton(onPressed: widget.onEditPassword, child: const Text('修改')),
                            ]),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: p.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('把设备代码和验证码告诉对方，对方即可远程协助本机。',
                        style: TextStyle(fontSize: 12.5, color: p.muted)),
                  ),
                  if (showOneTime && !bind.isDisableSettings())
                    TextButton(
                        onPressed: widget.onEditPassword,
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: const Text('设置固定密码', style: TextStyle(fontSize: 12.5))),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _controlCard(SdPalette p) {
    final btnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    return sdCard(
      p,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.connected_tv_rounded, size: 18, color: kSdAccent),
            const SizedBox(width: 8),
            Text('远程控制伙伴设备', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
          ]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _idCtrl,
                  inputFormatters: [IDTextInputFormatter()],
                  onSubmitted: (_) => _connect(),
                  style: TextStyle(fontSize: 18, letterSpacing: 1, color: p.text),
                  decoration: InputDecoration(
                    hintText: '输入伙伴的设备代码',
                    hintStyle: TextStyle(color: p.muted, fontSize: 15, letterSpacing: 0),
                    filled: true,
                    fillColor: p.field,
                    isDense: true,
                    prefixIcon: Icon(Icons.computer_rounded, color: p.muted, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: kSdAccent, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _connect,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kSdAccent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      shape: btnShape),
                  child: const Text('远程控制', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: () => _connect(file: true),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: p.text,
                      backgroundColor: p.card,
                      side: BorderSide(color: p.line),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: btnShape),
                  child: const Text('传文件', style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _recent(SdPalette p) {
    return ChangeNotifierProvider.value(
      value: gFFI.recentPeersModel,
      child: Consumer<Peers>(builder: (context, model, _) {
        final peers = model.peers.take(8).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('最近连接', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
                const Spacer(),
                TextButton(onPressed: widget.onAllDevices, child: const Text('全部设备 ›')),
              ],
            ),
            const SizedBox(height: 8),
            if (peers.isEmpty)
              sdCard(p,
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                  child: Center(
                    child: Text('还没有连接记录，输入伙伴的设备代码开始第一次远程吧',
                        style: TextStyle(color: p.muted, fontSize: 13)),
                  ))
            else
              Wrap(spacing: 12, runSpacing: 12, children: peers.map((x) => _peerCard(p, x)).toList()),
          ],
        );
      }),
    );
  }

  Widget _peerCard(SdPalette p, Peer peer) {
    final name = peer.alias.isNotEmpty ? peer.alias : (peer.hostname.isNotEmpty ? peer.hostname : formatID(peer.id));
    return SizedBox(
      width: 214,
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => connect(context, peer.id),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line)),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF2F6BFF), Color(0xFF00B8E0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: getPlatformImage(peer.platform, size: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600, color: p.text)),
                      const SizedBox(height: 2),
                      Text(formatID(peer.id), style: TextStyle(fontSize: 12, color: p.muted)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: p.muted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DevicesPage extends StatelessWidget {
  const _DevicesPage();

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设备列表', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.text)),
          const SizedBox(height: 4),
          Text('最近连接、收藏、局域网设备；登录账号后还有通讯录和团队设备。',
              style: TextStyle(fontSize: 13, color: p.muted)),
          const SizedBox(height: 12),
          const Expanded(child: PeerTabPage()),
        ],
      ),
    );
  }
}
