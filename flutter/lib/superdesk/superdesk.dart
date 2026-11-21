// super远程桌面 (SuperDesk) additions, kept in one file so upstream merges stay easy:
//   - update check against our own server (/download/latest.json, written by publish script)
//   - "request IT help" for the employee helper build (POST /api/superdesk/help)
//   - notice that incoming sessions are recorded (when the policy turns recording on)
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

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

int _buildNum(String s) =>
    int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Tells the console which flavor/build this device runs (shown in its device list).
Future<void> _hello(String api) async {
  try {
    final id = await bind.mainGetMyId();
    if (id.isEmpty) return;
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
