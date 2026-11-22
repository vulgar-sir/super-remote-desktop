// super远程桌面: Android main screen in the UU-remote-like style -- three tabs (远程协助 / 设备 / 设置)
// with big page titles, the "远控伙伴设备" card + "输入设备验证码" dialog, this device's ID and code,
// and a device page (preview card, 文件传输 / 观看模式 / 终端 / 更多). Connecting, the screen-share
// service, permissions and settings reuse the existing widgets and models.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/chat_page.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/mobile/pages/home_page.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:settings_ui/settings_ui.dart';

import 'devices.dart';
import 'theme.dart';

/// The UU-like tabs replace the stock ones on Android builds that can both control and be controlled.
bool get sdUseMobileHome => isAndroid && !bind.isIncomingOnly() && !bind.isOutgoingOnly();

/// Settings list in card sections (web style: a card per section, themed switches).
DevicePlatform? get sdSettingsPlatform => sdUseMobileHome ? DevicePlatform.web : null;

SettingsThemeData? sdSettingsLightTheme(BuildContext context) {
  if (!sdUseMobileHome) return null;
  final p = SdPalette(context);
  return SettingsThemeData(
    settingsListBackground: p.side,
    settingsSectionBackground: p.card,
    titleTextColor: p.muted,
    settingsTileTextColor: p.text,
    leadingIconsColor: p.text,
    dividerColor: p.divider,
    tileDescriptionTextColor: p.muted,
    trailingTextColor: p.muted,
  );
}

List<PageShape> sdMobilePages({required VoidCallback onShowDevices}) =>
    [SdMobileAssistTab(onShowDevices: onShowDevices), SdMobileDevicesTab(), SdMobileSettingsTab()];

/// Chat with the peers connected to this device (the stock layout had a tab for it).
void sdOpenChat(BuildContext context) {
  Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Scaffold(
                appBar: AppBar(title: Text(translate('Chat'))),
                body: ChatPage(type: ChatPageType.mobileMain),
              )));
}

const _kMobilePad = EdgeInsets.fromLTRB(16, 12, 16, 24);

Widget _mobileTitle(SdPalette p, String title, {List<Widget> actions = const []}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 0, 16),
      child: Row(children: [
        Text(title, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text)),
        const Spacer(),
        ...actions,
      ]),
    );

Widget _mobileCard(SdPalette p, {required Widget child, EdgeInsets? padding}) => Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12)),
      child: child,
    );

InputDecoration _filledInput(SdPalette p, String hint, {Widget? suffix}) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: p.hint, fontSize: 16),
      filled: true,
      fillColor: p.dark ? p.field : const Color(0xFFF2F3F5),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      suffixIcon: suffix,
    );

Widget _bigButton(String label, VoidCallback? onPressed) => SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kSdAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: kSdAccent.withOpacity(0.45),
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );

/// "输入设备验证码" dialog, then the session starts with that code (empty: asked later).
Future<void> sdConnectWithCode(BuildContext context, String id) async {
  final ctrl = TextEditingController();
  final p = SdPalette(context);
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() => Navigator.pop(ctx, ctrl.text.trim());
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: p.card,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: Stack(alignment: Alignment.center, children: [
              Text('输入设备验证码', style: TextStyle(fontSize: 17, color: p.text)),
              Positioned(
                right: 4,
                child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消', style: TextStyle(color: kSdAccent, fontSize: 16))),
              ),
            ]),
          ),
          Divider(height: 1, color: p.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: StatefulBuilder(
              builder: (ctx, setState) => TextField(
                controller: ctrl,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => submit(),
                style: TextStyle(fontSize: 17, color: p.text),
                decoration: _filledInput(p, '对方设备上显示的验证码',
                    suffix: ctrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: Icon(Icons.close_rounded, color: p.hint),
                            onPressed: () => setState(() => ctrl.clear()))),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 18), child: _bigButton('开始远控', submit)),
        ]),
      );
    },
  );
  if (code == null || !context.mounted) return;
  connect(context, id, password: code.isEmpty ? null : code);
}

// ------------------------------------------------------------------------------------- 远程协助 tab

class SdMobileAssistTab extends StatefulWidget implements PageShape {
  @override
  final title = '远程协助';
  @override
  final icon = const Icon(Icons.screen_share_rounded);
  @override
  final appBarActions = <Widget>[];
  final VoidCallback onShowDevices;

  SdMobileAssistTab({Key? key, required this.onShowDevices}) : super(key: key);

  @override
  State<SdMobileAssistTab> createState() => _SdMobileAssistTabState();
}

class _SdMobileAssistTabState extends State<SdMobileAssistTab> {
  final _idCtrl = IDTextEditingController();
  final _showCode = false.obs;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Same housekeeping as the stock share-screen page.
    _timer = periodic_immediate(const Duration(seconds: 3), () async => await gFFI.serverModel.fetchID());
    gFFI.serverModel.checkAndroidPermission();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idCtrl.dispose();
    super.dispose();
  }

  void _start() {
    final id = _idCtrl.id;
    if (id.isNotEmpty) sdConnectWithCode(context, id);
  }

  @override
  Widget build(BuildContext context) {
    checkService();
    final p = SdPalette(context);
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, _) => SafeArea(
          child: SingleChildScrollView(
            controller: model.controller,
            padding: _kMobilePad,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _mobileTitle(p, '远程协助', actions: ServerPage().appBarActions),
              _partner(p),
              const SizedBox(height: 16),
              buildPresetPasswordWarningMobile(),
              _thisDevice(p, model),
              const ConnectionManager(),
              const PermissionChecker(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _partner(SdPalette p) {
    return _mobileCard(
      p,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('远控伙伴设备', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text)),
        const SizedBox(height: 6),
        Text('通过其他设备的【设备ID】及【设备验证码】启动远程控制', style: TextStyle(fontSize: 13.5, color: p.muted)),
        const SizedBox(height: 16),
        Text('伙伴的设备ID', style: TextStyle(fontSize: 14, color: p.text)),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _idCtrl,
          builder: (context, v, _) => Column(children: [
            TextField(
              controller: _idCtrl,
              keyboardType: TextInputType.visiblePassword,
              inputFormatters: [IDTextInputFormatter()],
              onSubmitted: (_) => _start(),
              style: TextStyle(fontSize: 17, color: p.text, letterSpacing: 0.5),
              decoration: _filledInput(p, '请输入设备ID',
                  suffix: v.text.isEmpty
                      ? null
                      : IconButton(icon: Icon(Icons.close_rounded, color: p.hint), onPressed: _idCtrl.clear)),
            ),
            const SizedBox(height: 16),
            _bigButton('开始远控', v.text.trim().isEmpty ? null : _start),
          ]),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(onPressed: widget.onShowDevices, child: const Text('最近连接', style: TextStyle(color: kSdAccent))),
          Container(width: 1, height: 14, color: p.divider),
          TextButton(onPressed: widget.onShowDevices, child: const Text('收藏设备', style: TextStyle(color: kSdAccent))),
        ]),
      ]),
    );
  }

  Widget _thisDevice(SdPalette p, ServerModel model) {
    final click = model.approveMode == 'click';
    final showOneTime = !click && model.verificationMethod != kUsePermanentPassword;
    void toggle(bool on) {
      if (on &&
          gFFI.userModel.userName.value.isEmpty &&
          bind.mainGetLocalOption(key: 'show-scam-warning') != 'N') {
        showScamWarning(context, model);
      } else {
        model.toggleService();
      }
    }

    return _mobileCard(
      p,
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(children: [
            Text('本设备', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text)),
            const Spacer(),
            Text('允许他人远程协助', style: TextStyle(fontSize: 14, color: p.text)),
            sdSwitch(p, model.isStart, toggle, caption: false),
          ]),
        ),
        Divider(height: 1, color: p.divider),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('本设备ID', style: TextStyle(fontSize: 13, color: p.muted)),
            const SizedBox(height: 4),
            Row(children: [
              Flexible(
                child: Text(model.serverId.value.text,
                    maxLines: 1,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text)),
              ),
              sdIconButton(p, Icons.copy_rounded, '复制设备ID',
                  () => sdCopy(model.serverId.value.text.replaceAll(' ', '')), color: p.text),
            ]),
            const SizedBox(height: 10),
            Text(click ? '验证方式' : (showOneTime ? '验证码' : '验证方式'), style: TextStyle(fontSize: 13, color: p.muted)),
            const SizedBox(height: 4),
            Obx(() => Row(children: [
                  Flexible(
                    child: Text(
                      click
                          ? '对方连接时在弹窗中接受'
                          : (showOneTime
                              ? (_showCode.value ? model.serverPasswd.value.text : '••••••')
                              : '已设置固定密码'),
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: showOneTime ? 24 : 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: showOneTime ? 1.5 : 0,
                          color: p.text),
                    ),
                  ),
                  if (showOneTime) ...[
                    sdIconButton(p, _showCode.value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        _showCode.value ? '隐藏验证码' : '查看验证码', () => _showCode.toggle(),
                        color: p.text),
                    sdIconButton(p, Icons.refresh_rounded, '更换验证码', () => bind.mainUpdateTemporaryPassword(),
                        color: p.text),
                  ],
                ])),
            if (showOneTime) Text('每次远控后自动刷新', style: TextStyle(fontSize: 12, color: p.hint)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text(
                    model.isStart
                        ? (model.connectStatus > 0 ? '已就绪，对方可通过设备ID和验证码远程协助本机' : '正在连接服务器…')
                        : '打开右上方开关后，对方才能远程协助本机',
                    style: TextStyle(fontSize: 12.5, color: p.muted)),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: sdOutlineButton(p, '复制并分享', () {
                  final id = model.serverId.value.text.replaceAll(' ', '');
                  sdCopy(showOneTime
                      ? '请用 super远程桌面 远程协助我：\n设备ID：$id\n验证码：${model.serverPasswd.value.text.trim()}'
                      : '请用 super远程桌面 远程协助我：\n设备ID：$id');
                }, minWidth: 0),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------------------------------ 设备 tab

class SdMobileDevicesTab extends StatefulWidget implements PageShape {
  @override
  final title = '设备';
  @override
  final icon = const Icon(Icons.devices_rounded);
  @override
  final appBarActions = <Widget>[];

  SdMobileDevicesTab({Key? key}) : super(key: key);

  @override
  State<SdMobileDevicesTab> createState() => _SdMobileDevicesTabState();
}

class _SdMobileDevicesTabState extends State<SdMobileDevicesTab> {
  bool _pcOpen = true;
  bool _mobileOpen = true;

  @override
  void initState() {
    super.initState();
    SdOnline.start();
    bind.mainLoadRecentPeers();
    bind.mainLoadFavPeers();
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return AnimatedBuilder(
      animation: sdPeersListenable,
      builder: (context, _) {
        return Obx(() {
          gFFI.userModel.userName.value;
          final peers = sdAllPeers();
          SdOnline.want(peers.map((x) => x.id).toList());
          final online = SdOnline.ids.toSet();
          final pcs = peers.where((x) => !sdIsMobilePlatform(x.platform)).toList();
          final mobiles = peers.where((x) => sdIsMobilePlatform(x.platform)).toList();
          return SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                bind.mainLoadRecentPeers();
                bind.mainLoadFavPeers();
              },
              child: ListView(padding: _kMobilePad, children: [
                _mobileTitle(p, '全部设备'),
                if (peers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 90),
                    child: Column(children: [
                      Icon(Icons.devices_other_rounded, size: 84, color: kSdAccent.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      Text('暂无设备', style: TextStyle(fontSize: 16, color: p.text)),
                      const SizedBox(height: 6),
                      Text('在“远程协助”输入伙伴的设备ID，连接过的设备会显示在这里',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: p.muted)),
                    ]),
                  ),
                if (pcs.isNotEmpty) ...[
                  _group(p, '电脑', pcs.length, _pcOpen, () => setState(() => _pcOpen = !_pcOpen)),
                  if (_pcOpen) ...pcs.map((x) => _row(p, x, online.contains(x.id))),
                ],
                if (mobiles.isNotEmpty) ...[
                  _group(p, '手机/平板', mobiles.length, _mobileOpen, () => setState(() => _mobileOpen = !_mobileOpen)),
                  if (_mobileOpen) ...mobiles.map((x) => _row(p, x, online.contains(x.id))),
                ],
              ]),
            ),
          );
        });
      },
    );
  }

  Widget _group(SdPalette p, String label, int n, bool open, VoidCallback toggle) => InkWell(
        onTap: toggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
          child: Row(children: [
            Icon(open ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                size: 20, color: p.text),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 15, color: p.text)),
            const SizedBox(width: 6),
            Text('$n', style: TextStyle(fontSize: 15, color: p.muted)),
          ]),
        ),
      );

  Widget _row(SdPalette p, Peer x, bool online) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: p.card,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SdMobileDevicePage(id: x.id))),
            child: SizedBox(
              height: 66,
              child: Row(children: [
                const SizedBox(width: 16),
                sdPlatformTile(x.platform, size: 36, online: online),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sdPeerName(x),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, color: p.text)),
                    const SizedBox(height: 2),
                    Row(children: [
                      if (online)
                        Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: const BoxDecoration(color: kSdOnline, shape: BoxShape.circle)),
                      Text(online ? '在线' : formatID(x.id), style: TextStyle(fontSize: 12.5, color: p.muted)),
                    ]),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: p.hint),
                const SizedBox(width: 10),
              ]),
            ),
          ),
        ),
      );
}

// --------------------------------------------------------------------------------------- device page

class SdMobileDevicePage extends StatefulWidget {
  final String id;
  const SdMobileDevicePage({Key? key, required this.id}) : super(key: key);

  @override
  State<SdMobileDevicePage> createState() => _SdMobileDevicePageState();
}

class _SdMobileDevicePageState extends State<SdMobileDevicePage> {
  bool _fav = false;

  @override
  void initState() {
    super.initState();
    sdIsFav(widget.id).then((v) {
      if (mounted) setState(() => _fav = v);
    });
  }

  Peer get _peer => sdAllPeers().firstWhereOrNull((x) => x.id == widget.id) ?? Peer.fromJson({'id': widget.id});

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    return Scaffold(
      backgroundColor: p.side,
      body: SafeArea(
        child: Obx(() {
          final x = _peer;
          final online = SdOnline.ids.contains(x.id);
          return ListView(padding: const EdgeInsets.fromLTRB(4, 4, 12, 24), children: [
            Row(children: [
              IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: p.text),
                  onPressed: () => Navigator.pop(context)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: online ? const Color(0xFF191919) : p.soft, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (online)
                    Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: const BoxDecoration(color: kSdOnline, shape: BoxShape.circle)),
                  Text(online ? '在线' : '离线', style: TextStyle(fontSize: 12, color: online ? Colors.white : p.muted)),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(sdPeerName(x),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: p.text)),
              ),
              IconButton(icon: Icon(Icons.more_vert_rounded, color: p.text), onPressed: () => _more(x)),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 0, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _preview(p, x, online),
                const SizedBox(height: 22),
                Text('设备信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
                const SizedBox(height: 10),
                _mobileCard(
                  p,
                  child: Column(children: [
                    _info(p, '设备ID', formatID(x.id)),
                    if (x.hostname.isNotEmpty) _info(p, '设备名称', x.hostname),
                    if (x.username.isNotEmpty) _info(p, '用户名', x.username),
                    if (x.platform.isNotEmpty) _info(p, '系统', x.platform),
                  ]),
                ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }

  Widget _info(SdPalette p, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 80, child: Text(k, style: TextStyle(fontSize: 14, color: p.muted))),
          Expanded(child: SelectableText(v, style: TextStyle(fontSize: 14, color: p.text))),
        ]),
      );

  Widget _preview(SdPalette p, Peer x, bool online) {
    final colors = online
        ? const [Color(0xFF00A2FF), Color(0xFF0057D9), Color(0xFF00328A)]
        : const [Color(0xFF9AA3AE), Color(0xFF6E7781), Color(0xFF4F565E)];
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Icon(icon, size: 22, color: p.text),
                const SizedBox(height: 5),
                Text(label, style: TextStyle(fontSize: 12.5, color: p.text)),
              ]),
            ),
          ),
        );
    Widget sep() => Container(width: 1, height: 30, color: p.divider);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        InkWell(
          onTap: () => sdConnectMode(context, x.id, viewOnly: false),
          child: Container(
            height: 190,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
            child: Stack(children: [
              Positioned(
                  right: 40,
                  top: 30,
                  child: sdPlatformIcon(x.platform, size: 110, color: Colors.white.withOpacity(0.28))),
              const Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text('进入桌面 ›', style: TextStyle(fontSize: 15, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
        Row(children: [
          action(Icons.drive_folder_upload_outlined, '文件传输', () => connect(context, x.id, isFileTransfer: true)),
          sep(),
          action(Icons.smart_display_outlined, '观看模式', () => sdConnectMode(context, x.id, viewOnly: true)),
          sep(),
          action(Icons.terminal_rounded, '终端', () => connect(context, x.id, isTerminal: true)),
          sep(),
          action(Icons.grid_view_rounded, '更多', () => _more(x)),
        ]),
      ]),
    );
  }

  void _more(Peer x) {
    final p = SdPalette(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('远程摄像头'),
              onTap: () {
                Navigator.pop(ctx);
                connect(context, x.id, isViewCamera: true);
              }),
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改备注名'),
              onTap: () {
                Navigator.pop(ctx);
                renameDialog(
                    oldName: x.alias,
                    onSubmit: (name) async {
                      await bind.mainSetPeerAlias(id: x.id, alias: name);
                      bind.mainLoadRecentPeers();
                      bind.mainLoadFavPeers();
                    });
              }),
          ListTile(
              leading: Icon(_fav ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined),
              title: Text(_fav ? '取消收藏' : '收藏'),
              onTap: () async {
                Navigator.pop(ctx);
                await sdSetFav(x.id, !_fav);
                if (mounted) setState(() => _fav = !_fav);
              }),
          ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制设备ID'),
              onTap: () {
                Navigator.pop(ctx);
                sdCopy(x.id);
              }),
          ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              title: const Text('删除连接记录', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                await bind.mainRemovePeer(id: x.id);
                await sdSetFav(x.id, false);
                bind.mainLoadRecentPeers();
                if (mounted) Navigator.pop(context);
              }),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------ 设置 tab

class SdMobileSettingsTab extends StatelessWidget implements PageShape {
  @override
  final title = '设置';
  @override
  final icon = const Icon(Icons.settings_rounded);
  @override
  final appBarActions = <Widget>[];

  SdMobileSettingsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    final settings = SettingsPage();
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: _mobileTitle(p, '设置', actions: settings.appBarActions),
        ),
        Expanded(
          child: Theme(
            // flat white cards like the other pages (the web-style sections use Card)
            data: Theme.of(context).copyWith(
              cardTheme: CardTheme(
                shadowColor: Colors.transparent,
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            child: settings,
          ),
        ),
      ]),
    );
  }
}
