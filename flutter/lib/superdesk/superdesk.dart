// super远程桌面 (SuperDesk) additions, kept in one file so upstream merges stay easy:
//   - update check against our own server (/download/latest.json, written by publish script)
//   - "request IT help" for the employee helper build (POST /api/superdesk/help)
//   - notice that incoming sessions are recorded (when the policy turns recording on)
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'wallpaper.dart';

class SuperdeskUpdate {
  final String version;
  final String build;
  final String url;
  final String notes;
  SuperdeskUpdate(this.version, this.build, this.url, this.notes);
}

/// Set when the server offers a newer build of this platform + flavor.
final superdeskUpdate = Rxn<SuperdeskUpdate>();

String superdeskOption(String key) => bind.mainGetOptionSync(key: key);

String get superdeskFlavor {
  final f = superdeskOption('superdesk-flavor');
  return f.isEmpty ? 'full' : f;
}

String get superdeskPlatform => Platform.isAndroid
    ? 'android'
    : (Platform.isWindows ? 'windows' : Platform.operatingSystem);

Future<String> _apiServer() async {
  var api = (await bind.mainGetApiServer()).trim();
  while (api.endsWith('/')) {
    api = api.substring(0, api.length - 1);
  }
  return api;
}

/// API server without the trailing slash ('' when none is configured).
Future<String> sdApiServer() => _apiServer();

int _buildNum(String s) =>
    int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Tells the console which flavor/build this device runs (shown in its device list).
Future<void> _hello(String api) async {
  try {
    final id = await bind.mainGetMyId();
    if (id.isEmpty) return;
    sdUploadWallpaper(api);
    await http
        .post(Uri.parse('$api/api/superdesk/hello'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': id,
              'flavor': superdeskFlavor,
              'build': superdeskOption('superdesk-build'),
              'platform': superdeskPlatform,
            }))
        .timeout(const Duration(seconds: 10));
  } catch (_) {}
}

/// Checks the server for a newer build; updates [superdeskUpdate] and returns it.
Future<SuperdeskUpdate?> superdeskCheckUpdate() async {
  try {
    final api = await _apiServer();
    if (api.isEmpty) return null;
    _hello(api);
    final resp = await http
        .get(Uri.parse('$api/download/latest.json'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final clients = data is Map ? data['clients'] : null;
    final entry =
        clients is Map ? clients['$superdeskPlatform-$superdeskFlavor'] : null;
    if (entry is! Map) return null;
    final mine = _buildNum(superdeskOption('superdesk-build'));
    final latest = _buildNum('${entry['build'] ?? ''}');
    if (mine == 0 || latest <= mine) return null;
    var url = '${entry['url'] ?? ''}';
    if (url.startsWith('/')) url = '$api$url';
    final u = SuperdeskUpdate('${entry['version'] ?? ''}',
        '${entry['build'] ?? ''}', url, '${entry['notes'] ?? ''}');
    superdeskUpdate.value = u;
    return u;
  } catch (e) {
    debugPrint('superdesk update check failed: $e');
    return null;
  }
}

Future<void> superdeskOpenUpdate(SuperdeskUpdate u) async {
  await launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
}

/// Mobile: check once and offer the download in a dialog.
Future<void> superdeskCheckUpdateWithDialog(BuildContext context) async {
  final u = await superdeskCheckUpdate();
  if (u == null || !context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('发现新版本'),
      content: Text('super远程桌面 ${u.version}（${u.build}）已发布。'
          '${u.notes.isEmpty ? '' : '\n\n${u.notes}'}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('以后再说')),
        ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              superdeskOpenUpdate(u);
            },
            child: const Text('下载更新')),
      ],
    ),
  );
}

Future<String?> _postHelp(String message) async {
  try {
    final api = await _apiServer();
    if (api.isEmpty) return '未配置服务器地址';
    Map<String, dynamic> dev = {};
    try {
      final d = jsonDecode(bind.mainGetLoginDeviceInfo());
      if (d is Map<String, dynamic>) dev = d;
    } catch (_) {}
    final body = jsonEncode({
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid(),
      'device_name': dev['name'] ?? '',
      'os': dev['os'] ?? '',
      'flavor': superdeskFlavor,
      'build': superdeskOption('superdesk-build'),
      'message': message,
    });
    final resp = await http
        .post(Uri.parse('$api/api/superdesk/help'),
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return '服务器返回 ${resp.statusCode}';
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    if (data is Map && data['error'] != null) return '${data['error']}';
    return null;
  } catch (e) {
    return '$e';
  }
}

Future<void> superdeskRequestHelp(BuildContext context) async {
  final controller = TextEditingController();
  final send = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('请求 IT 协助'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: '简单描述遇到的问题（可不填）',
              border: OutlineInputBorder()),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('发送')),
      ],
    ),
  );
  if (send != true) return;
  final err = await _postHelp(controller.text.trim());
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(err == null ? '已通知 IT' : '发送失败'),
      content: Text(err == null
          ? 'IT 同事会尽快连接这台电脑，届时请在弹出的窗口中点击“接受”。'
          : '请稍后重试，或直接把本机 ID 告诉 IT。\n\n$err'),
      actions: [
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('好的')),
      ],
    ),
  );
}

/// Extra panel on the helper (incoming-only) home page.
Widget superdeskHelperPanel(BuildContext context) {
  final recording = superdeskOption('allow-auto-record-incoming') == 'Y';
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.support_agent, size: 20),
            label: const Text('请求 IT 协助', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2F6BFF),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => superdeskRequestHelp(context),
          ),
        ),
        if (recording)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('提示：远程协助过程会录屏，仅用于安全审计。',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
      ],
    ),
  );
}

/// "没有账号？注册账号" under the login form. Registration needs no approval (internal deployment);
/// on success the login form is filled in and submitted through [onRegistered].
Widget sdRegisterLink(BuildContext context, {required void Function(String user, String pass) onRegistered}) {
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text('没有账号？', style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
      TextButton(
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 32)),
        onPressed: () async {
          final r = await _registerDialog();
          if (r != null) onRegistered(r.$1, r.$2);
        },
        child: const Text('注册账号', style: TextStyle(fontSize: 13)),
      ),
    ]),
  );
}

Future<String?> _postRegister(String user, String pass) async {
  try {
    final api = await _apiServer();
    final resp = await http
        .post(Uri.parse('$api/api/superdesk/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': user, 'password': pass}))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) return null;
    String msg = '注册失败（${resp.statusCode}）';
    try {
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      if (d is Map) msg = '${d['error'] ?? d['detail'] ?? msg}';
    } catch (_) {}
    return msg;
  } catch (e) {
    return '无法连接服务器：$e';
  }
}

// The login dialog lives in dialogManager's overlay (above the navigator), so this one must too.
Future<(String, String)?> _registerDialog() {
  final user = TextEditingController();
  final pass = TextEditingController();
  final pass2 = TextEditingController();
  String? error;
  bool busy = false;
  return gFFI.dialogManager.show<(String, String)>((setState, close, context) {
    Future<void> submit() async {
      if (busy) return;
      final u = user.text.trim();
      String? bad;
      if (!RegExp(r'^[A-Za-z0-9_.@-]{2,32}$').hasMatch(u)) {
        bad = '用户名只能用字母、数字和 _ . @ -，2–32 位';
      } else if (pass.text.length < 8) {
        bad = '密码至少 8 位';
      } else if (pass.text != pass2.text) {
        bad = '两次输入的密码不一致';
      }
      if (bad != null) {
        setState(() => error = bad);
        return;
      }
      setState(() {
        busy = true;
        error = null;
      });
      final err = await _postRegister(u, pass.text);
      if (err == null) {
        close((u, pass.text));
        return;
      }
      setState(() {
        busy = false;
        error = err;
      });
    }

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        );
    return CustomAlertDialog(
      title: const Text('注册账号'),
      contentBoxConstraints: const BoxConstraints(minWidth: 360, maxWidth: 360),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        TextField(controller: user, autofocus: true, decoration: deco('用户名')),
        const SizedBox(height: 12),
        TextField(controller: pass, obscureText: true, decoration: deco('密码（至少 8 位）')),
        const SizedBox(height: 12),
        TextField(controller: pass2, obscureText: true, decoration: deco('确认密码')),
        if (busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
      ]),
      actions: [
        dialogButton('Cancel', onPressed: busy ? null : () => close(), isOutline: true),
        dialogButton('注册并登录', onPressed: busy ? null : submit),
      ],
      onSubmit: submit,
      onCancel: busy ? null : () => close(),
    );
  });
}
