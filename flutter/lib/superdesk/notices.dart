// super远程桌面: 消息中心 -- announcements published in super控制台 (公告), behind the title-bar bell with an
// unread badge, like the reference's message centre. Which notices were read is kept in a local option.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import 'superdesk.dart';
import 'theme.dart';

class SdNotice {
  final int id;
  final String title;
  final String content;
  final int createdAt;
  SdNotice(this.id, this.title, this.content, this.createdAt);

  String get date {
    final d = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

class SdNotices {
  static final items = <SdNotice>[].obs;
  static final read = <int>{}.obs;
  static Timer? _timer;
  static const _kRead = 'sd-notice-read';

  static void start() {
    if (_timer != null) return;
    read.addAll(bind.mainGetLocalOption(key: _kRead).split(',').map(int.tryParse).whereType<int>());
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => refresh());
  }

  static Future<void> refresh() async {
    try {
      final api = await sdApiServer();
      final id = await bind.mainGetMyId();
      if (api.isEmpty || id.isEmpty) return;
      final resp = await http
          .get(Uri.parse('$api/api/superdesk/notices?id=${Uri.encodeQueryComponent(id)}'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data is! List) return;
      items.assignAll(data.whereType<Map>().map((m) => SdNotice(
          m['id'] is int ? m['id'] : 0, '${m['title'] ?? ''}', '${m['content'] ?? ''}',
          m['created_at'] is int ? m['created_at'] : 0)));
    } catch (_) {}
  }

  static void markRead(Iterable<int> ids) {
    read.addAll(ids);
    // keep only ids that are still published, so the option does not grow forever
    final keep = items.map((n) => n.id).where(read.contains);
    bind.mainSetLocalOption(key: _kRead, value: keep.join(','));
  }
}

/// Title-bar bell with the unread count (red badge), opens the message centre.
Widget sdNoticeBell(SdPalette p) => Obx(() {
      final unread = SdNotices.items.where((n) => !SdNotices.read.contains(n.id)).length;
      return Stack(clipBehavior: Clip.none, children: [
        sdIconButton(p, Icons.notifications_none_rounded, '消息中心', sdShowNoticeCenter, color: p.text, size: 21),
        if (unread > 0)
          Positioned(
            right: 3,
            top: 3,
            child: IgnorePointer(
              child: Container(
                height: 15,
                constraints: const BoxConstraints(minWidth: 15),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFFF5455C), borderRadius: BorderRadius.circular(8)),
                child: Text(unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(fontSize: 10, color: Colors.white, height: 1.1)),
              ),
            ),
          ),
      ]);
    });

void sdShowNoticeCenter() {
  final ctx = globalKey.currentContext;
  if (ctx == null) return;
  SdNotices.refresh();
  SdNotice? open;
  showDialog(context: ctx, builder: (context) => StatefulBuilder(builder: (context, setState) {
    final p = SdPalette(context);
    void close() => Navigator.of(context).pop();
    Widget card(SdNotice n) {
      final unread = !SdNotices.read.contains(n.id);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration:
            BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            hoverColor: p.soft.withOpacity(0.4),
            onTap: () {
              SdNotices.markRead([n.id]);
              setState(() => open = n);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 16, 18),
              child: Row(children: [
                SizedBox(
                  width: 16,
                  child: unread
                      ? Center(
                          child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: Color(0xFFF5455C), shape: BoxShape.circle)))
                      : null,
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: const Color(0xFFFFC233), borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('公告消息    ${n.date}', style: TextStyle(fontSize: 13, color: p.hint)),
                    const SizedBox(height: 4),
                    Text(n.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: p.text)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: p.muted),
              ]),
            ),
          ),
        ),
      );
    }

    final body = Obx(() {
      final list = SdNotices.items.toList();
      SdNotices.read.length; // rebuild on read changes
      if (open != null) {
        final n = open!;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: p.text)),
            const SizedBox(height: 8),
            Text('公告消息    ${n.date}', style: TextStyle(fontSize: 13, color: p.hint)),
            Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: p.divider)),
            SelectableText(n.content.isEmpty ? n.title : n.content,
                style: TextStyle(fontSize: 14.5, height: 1.7, color: p.text)),
          ]),
        );
      }
      if (list.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SdIcon(SdGlyph.emptyBox, size: 64),
            const SizedBox(height: 12),
            Text('暂无消息', style: TextStyle(fontSize: 14, color: p.hint)),
          ]),
        );
      }
      return ListView(padding: const EdgeInsets.fromLTRB(28, 24, 28, 24), children: list.map(card).toList());
    });

    return Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: SizedBox(
          width: 600,
          height: 620,
          child: Column(children: [
            Container(
              height: 56,
              color: p.card,
              child: Row(children: [
                const SizedBox(width: 10),
                IconButton(
                  tooltip: '返回',
                  splashRadius: 18,
                  icon: Icon(Icons.arrow_back_rounded, size: 20, color: open == null ? p.disabled : p.text),
                  onPressed: open == null ? null : () => setState(() => open = null),
                ),
                Text('消息中心', style: TextStyle(fontSize: 15, color: p.text)),
                const Spacer(),
                if (open == null)
                  TextButton.icon(
                    onPressed: () => SdNotices.markRead(SdNotices.items.map((n) => n.id)),
                    icon: Icon(Icons.mark_email_read_outlined, size: 18, color: p.text),
                    label: Text('一键已读', style: TextStyle(fontSize: 14, color: p.text)),
                  ),
                IconButton(
                  tooltip: '关闭',
                  splashRadius: 18,
                  icon: Icon(Icons.close_rounded, size: 20, color: p.text),
                  onPressed: () => close(),
                ),
                const SizedBox(width: 10),
              ]),
            ),
            Divider(height: 1, color: p.divider),
            Expanded(child: Container(color: p.dark ? p.page : const Color(0xFFF7F7F7), child: body)),
          ]),
        ),
    );
  }));
}
