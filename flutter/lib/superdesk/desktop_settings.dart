// super远程桌面: settings in the UU-remote-like layout -- tabs 常规 / 安全 / 网络, one card per setting with an
// icon, a title, a grey description and a switch / drop-down / button on the right. Every value is read and
// written through the same option and ServerModel calls as RustDesk's own settings page, which stays reachable
// in full under "更多设置". Security and network items keep RustDesk's lock for installed builds.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart' show setPasswordDialog;
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'superdesk.dart';
import 'theme.dart';

enum SdSettingsTab { general, safety, network }

/// The tab of this page that shows [k], or null when only the full RustDesk page has it.
SdSettingsTab? sdSettingsTabOf(SettingsTabKey k) {
  switch (k) {
    case SettingsTabKey.general:
      return SdSettingsTab.general;
    case SettingsTabKey.safety:
      return SdSettingsTab.safety;
    case SettingsTabKey.network:
      return SdSettingsTab.network;
    default:
      return null;
  }
}

class SdSettingsPage extends StatefulWidget {
  final SdSettingsTab initialTab;
  final ValueChanged<SettingsTabKey> onMore;
  const SdSettingsPage({Key? key, this.initialTab = SdSettingsTab.general, required this.onMore})
      : super(key: key);

  @override
  State<SdSettingsPage> createState() => _SdSettingsPageState();
}

class _SdSettingsPageState extends State<SdSettingsPage> {
  late SdSettingsTab _tab = widget.initialTab;
  bool _locked = bind.mainIsInstalled();

  static const _tabs = {SdSettingsTab.general: '常规', SdSettingsTab.safety: '安全', SdSettingsTab.network: '网络'};

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    final List<Widget> cards;
    switch (_tab) {
      case SdSettingsTab.general:
        cards = _general(p);
        break;
      case SdSettingsTab.safety:
        cards = _safety(p);
        break;
      case SdSettingsTab.network:
        cards = _network(p);
        break;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(40, 26, 40, 0),
        child: Text('设置', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 40, 0),
        child: Row(
            children: _tabs.entries.map((e) {
          final selected = e.key == _tab;
          return InkWell(
            onTap: () => setState(() => _tab = e.key),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(e.value,
                    style: TextStyle(
                        fontSize: 15.5,
                        color: selected ? p.text : p.muted,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                const SizedBox(height: 7),
                Container(
                    width: 18,
                    height: 3,
                    decoration: BoxDecoration(
                        color: selected ? kSdAccent : Colors.transparent, borderRadius: BorderRadius.circular(2))),
              ]),
            ),
          );
        }).toList()),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(40, 18, 40, 28),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(children: [if (_locked) _lockCard(p), ...cards]),
            ),
          ),
        ),
      ),
    ]);
  }

  // ------------------------------------------------------------------------------------------- tabs

  List<Widget> _general(SdPalette p) {
    final theme = MyTheme.getThemeModePreference().toShortString();
    return [
      _card(p, [
        _row(p,
            icon: Icons.palette_outlined,
            title: '外观',
            desc: '浅色、深色或跟随系统设置',
            trailing: _dropdown(p, theme, const {'system': '跟随系统', 'light': '浅色', 'dark': '深色'},
                isOptionFixed(kCommConfKeyTheme)
                    ? null
                    : (v) async {
                        await MyTheme.changeDarkMode(MyTheme.themeModeFromString(v));
                        _refresh();
                      })),
      ]),
      _card(p, [
        if (!bind.isOutgoingOnly())
          _row(p,
              icon: Icons.wb_sunny_outlined,
              title: '防止电脑休眠',
              desc: '被远程协助期间保持唤醒，休眠将导致电脑无法被远程控制',
              trailing: _optSwitch(p, kOptionKeepAwakeDuringIncomingSessions, locked: _locked)),
        if (!bind.isIncomingOnly())
          _row(p,
              icon: bind.isOutgoingOnly() ? Icons.wb_sunny_outlined : null,
              title: '远控其他设备时防止本机休眠',
              trailing: _optSwitch(p, kOptionKeepAwakeDuringOutgoingSessions, local: true)),
      ]),
      if (!bind.isIncomingOnly())
        _card(p, [
          _row(p,
              icon: Icons.videocam_outlined,
              title: '自动录制远控会话',
              desc: '控制其他设备时自动录屏，保存位置可在“更多常规设置”中修改',
              trailing: _optSwitch(p, kOptionAllowAutoRecordOutgoing, local: true)),
        ]),
      _card(p, [
        _row(p,
            icon: Icons.system_update_alt_rounded,
            title: '软件更新',
            desc: '当前版本 ${superdeskOption('superdesk-build')}，启动时自动检查新版本',
            trailing: sdOutlineButton(p, '检查更新', _checkUpdate)),
      ]),
      _moreCard(p, SettingsTabKey.general, '更多常规设置', '语言、录屏目录、硬件编解码等 RustDesk 完整设置'),
    ];
  }

  List<Widget> _safety(SdPalette p) {
    final access = bind.mainGetOptionSync(key: kOptionAccessMode);
    final bool? fake = access == 'full' ? true : (access == 'view' ? false : null);
    final accessKey = access == 'full' || access == 'view' ? access : '$defaultOptionAccessMode';
    return [
      if (!bind.isOutgoingOnly())
        Builder(builder: (context) {
          final svcStopped = Get.find<RxBool>(tag: 'stop-service');
          return _card(p, [
            _row(p,
                icon: Icons.screen_share_outlined,
                title: '允许他人远程协助',
                desc: '关闭后，其他设备无法远程连接本机',
                trailing: Obx(() => sdSwitch(p, !svcStopped.value, (v) => start_service(v)))),
          ]);
        }),
      Consumer<ServerModel>(builder: (context, model, _) {
        final click = model.approveMode == 'click';
        final modes = {'password': '验证码连接', 'click': '本机点击接受', '$defaultOptionApproveMode': '验证码或点击接受'};
        final mode = modes.containsKey(model.approveMode) ? model.approveMode : '$defaultOptionApproveMode';
        return _card(p, [
          _row(p,
              icon: Icons.verified_user_outlined,
              title: '远程协助连接本设备的方式',
              desc: '通过本机【设备ID】和【设备验证码】即可发起远程协助',
              trailing: _dropdown(p, mode, modes,
                  _locked || isOptionFixed(kOptionApproveMode) ? null : (v) => model.setApproveMode(v))),
          if (!click)
            _row(p,
                title: '验证码连接',
                trailing: _dropdown(
                    p,
                    model.verificationMethod,
                    const {
                      kUseTemporaryPassword: '仅使用临时验证码',
                      kUsePermanentPassword: '仅使用固定密码',
                      kUseBothPasswords: '临时验证码和固定密码',
                    },
                    _locked ? null : (v) => _setVerificationMethod(model, v),
                    width: 196)),
          if (!click && model.verificationMethod != kUsePermanentPassword)
            _row(p,
                title: '临时验证码长度',
                trailing: _dropdown(p, model.temporaryPasswordLength, const {'6': '6 位', '8': '8 位', '10': '10 位'},
                    _locked
                        ? null
                        : (v) async {
                            await model.setTemporaryPasswordLength(v);
                            await model.updatePasswordModel();
                          })),
          if (!click && model.verificationMethod != kUseTemporaryPassword && !isChangePermanentPasswordDisabled())
            _row(p,
                title: '固定密码',
                desc: '设置后可用固定密码连接本机，无需每次查看验证码',
                trailing: sdOutlineButton(p, '设置固定密码', _locked ? null : () => setPasswordDialog())),
        ]);
      }),
      _card(p, [
        _row(p,
            icon: Icons.drive_file_move_outlined,
            title: '被远程协助时允许文件互传',
            desc: '开启后，可通过复制粘贴、拖拽与主控端双向传输文件',
            trailing: _optSwitch(p, kOptionEnableFileTransfer, locked: _locked, fake: fake)),
      ]),
      _card(p, [
        _row(p,
            icon: Icons.admin_panel_settings_outlined,
            title: '被控权限',
            desc: '对方连接本机后可以使用的功能',
            trailing: _dropdown(p, accessKey, {'$defaultOptionAccessMode': '自定义', 'full': '完全控制', 'view': '仅共享屏幕'},
                _locked || isOptionFixed(kOptionAccessMode)
                    ? null
                    : (v) async {
                        await bind.mainSetOption(key: kOptionAccessMode, value: v);
                        _refresh();
                      })),
        _permission(p, '允许控制键盘鼠标', kOptionEnableKeyboard, fake),
        _permission(p, '允许同步剪贴板', kOptionEnableClipboard, fake),
        _permission(p, '允许传输声音', kOptionEnableAudio, fake),
        _permission(p, '允许查看摄像头', kOptionEnableCamera, fake),
        _permission(p, '允许使用终端', kOptionEnableTerminal, fake),
        _permission(p, '允许端口映射', kOptionEnableTunnel, fake),
        _permission(p, '允许远程重启', kOptionEnableRemoteRestart, fake),
        _permission(p, '允许录制会话', kOptionEnableRecordSession, fake),
        if (isWindows) _permission(p, '允许远程打印', kOptionEnableRemotePrinter, fake),
      ]),
      if (bind.mainIsInstalled() && !isUnlockPinDisabled())
        _card(p, [
          _row(p,
              icon: Icons.lock_outline_rounded,
              title: '客户端锁定',
              desc: '设置解锁 PIN，修改安全设置前需先输入 PIN',
              trailing: sdSwitch(
                  p,
                  bind.mainGetUnlockPin().isNotEmpty,
                  _locked || isOptionFixed(kOptionWhitelist)
                      ? null
                      : (_) => changeUnlockPinDialog(bind.mainGetUnlockPin(), _refresh))),
        ]),
      _card(p, [
        _row(p,
            icon: Icons.playlist_add_check_rounded,
            title: 'IP 白名单',
            desc: whitelistNotEmpty() ? '已启用：只允许名单内的 IP 连接本机' : '只允许名单内的 IP 连接本机',
            trailing: sdOutlineButton(p, '设置',
                _locked || isOptionFixed(kOptionWhitelist) ? null : () => changeWhiteList(callback: _refresh))),
      ]),
      _moreCard(p, SettingsTabKey.safety, '更多安全设置', '双重认证、ID 白名单、自动断开、隐私模式等'),
    ];
  }

  List<Widget> _network(SdPalette p) {
    final port = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    return [
      Consumer<ServerModel>(builder: (context, model, _) {
        final s = model.connectStatus;
        return _card(p, [
          _row(p,
              icon: Icons.dns_outlined,
              title: '服务器',
              desc: '由管理员统一配置，无需手动填写',
              trailing: _statusPill(s > 0 ? '已连接' : (s == 0 ? '连接中' : '未连接'), s > 0 ? kSdOnline : p.hint)),
        ]);
      }),
      if (!bind.isOutgoingOnly())
        _card(p, [
          _row(p,
              icon: Icons.lan_outlined,
              title: '局域网发现',
              desc: '允许同一局域网内的设备发现本机',
              trailing: _optSwitch(p, kOptionEnableLanDiscovery, locked: _locked)),
          _row(p,
              title: '直接 IP 访问',
              desc: '局域网内可直接输入本机 IP 连接（端口 ${port.isEmpty ? '21118' : port}）',
              trailing: _optSwitch(p, kOptionDirectServer, locked: _locked)),
        ]),
      _card(p, [
        _row(p,
            icon: Icons.vpn_lock_outlined,
            title: '代理',
            desc: '通过 Socks5 / HTTP 代理连接服务器',
            trailing: sdOutlineButton(p, '设置', _locked ? null : changeSocks5Proxy)),
      ]),
      _moreCard(p, SettingsTabKey.network, '更多网络设置', 'ID / 中继服务器、WebSocket、UDP 等'),
    ];
  }

  // ---------------------------------------------------------------------------------------- actions

  Future<void> _unlock() async {
    final pin = bind.mainGetUnlockPin();
    if (pin.isEmpty || isUnlockPinDisabled()) {
      if (await callMainCheckSuperUserPermission()) setState(() => _locked = false);
    } else {
      checkUnlockPinDialog(pin, () => setState(() => _locked = false));
    }
  }

  Future<void> _setVerificationMethod(ServerModel model, String v) async {
    Future<void> apply() async {
      await model.setVerificationMethod(v);
      await model.updatePasswordModel();
    }

    if (v == kUsePermanentPassword &&
        !isChangePermanentPasswordDisabled() &&
        (await bind.mainGetCommon(key: 'permanent-password-set')) != 'true') {
      setPasswordDialog(notEmptyCallback: apply);
    } else {
      await apply();
    }
  }

  Future<void> _checkUpdate() async {
    final u = await superdeskCheckUpdate();
    if (!mounted) return;
    if (u == null) {
      showToast('已是最新版本');
    } else {
      superdeskOpenUpdate(u);
    }
  }

  // ----------------------------------------------------------------------------------------- pieces

  Widget _card(SdPalette p, List<Widget> rows) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        decoration:
            BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line)),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: p.divider),
            rows[i],
          ],
        ]),
      );

  /// Icon column, title + optional grey line, control on the right (88px like the reference; 56 for
  /// the plain permission rows).
  Widget _row(SdPalette p,
      {IconData? icon,
      required String title,
      String? desc,
      Widget? trailing,
      VoidCallback? onTap,
      bool compact = false}) {
    final row = InkWell(
      onTap: onTap,
      hoverColor: p.soft.withOpacity(0.4),
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 56 : 88),
        padding: EdgeInsets.fromLTRB(24, compact ? 8 : 14, 18, compact ? 8 : 14),
        child: Row(children: [
          SizedBox(
            width: 50,
            child: icon == null ? null : Align(alignment: Alignment.centerLeft, child: Icon(icon, size: 25, color: p.text)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: TextStyle(fontSize: compact ? 15 : 16, color: p.text)),
              if (desc != null) ...[
                const SizedBox(height: 5),
                Text(desc, style: TextStyle(fontSize: 13, color: p.hint)),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing],
        ]),
      ),
    );
    return onTap == null ? row : Material(type: MaterialType.transparency, child: row);
  }

  Widget _permission(SdPalette p, String title, String key, bool? fake) =>
      _row(p, title: title, compact: true, trailing: _optSwitch(p, key, locked: _locked, fake: fake));

  Widget _optSwitch(SdPalette p, String key, {bool local = false, bool locked = false, bool? fake}) {
    final value = fake ?? (local ? mainGetLocalBoolOptionSync(key) : mainGetBoolOptionSync(key));
    final inert = locked || fake != null || isOptionFixed(key);
    return sdSwitch(
        p,
        value,
        inert
            ? null
            : (v) async {
                await (local ? mainSetLocalBoolOption(key, v) : mainSetBoolOption(key, v));
                _refresh();
              });
  }

  /// Small bordered drop-down (white box, value + chevron), as on the reference's settings rows.
  Widget _dropdown(SdPalette p, String value, Map<String, String> items, ValueChanged<String>? onChanged,
      {double width = 150}) {
    final enabled = onChanged != null;
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: '',
      initialValue: value,
      offset: const Offset(0, 34),
      onSelected: onChanged,
      itemBuilder: (_) => items.entries
          .map((e) =>
              PopupMenuItem(value: e.key, height: 36, child: Text(e.value, style: const TextStyle(fontSize: 14))))
          .toList(),
      child: Container(
        width: width,
        height: 30,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: p.dark ? p.line : const Color(0xFFDADCDD)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(items[value] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: enabled ? p.text : p.hint)),
          ),
          Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: enabled ? p.text : p.hint),
        ]),
      ),
    );
  }

  Widget _statusPill(String label, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 14, color: color)),
      ]);

  Widget _lockCard(SdPalette p) => _card(p, [
        _row(p,
            icon: Icons.shield_outlined,
            title: '部分设置已锁定',
            desc: '修改安全与网络设置需要管理员授权（已设置客户端锁定时输入 PIN）',
            trailing: sdPrimaryButton(p, '解锁', _unlock)),
      ]);

  Widget _moreCard(SdPalette p, SettingsTabKey tab, String title, String desc) => _card(p, [
        _row(p,
            icon: Icons.tune_rounded,
            title: title,
            desc: desc,
            trailing: Icon(Icons.chevron_right_rounded, size: 22, color: p.hint),
            onTap: () => widget.onMore(tab)),
      ]);
}
