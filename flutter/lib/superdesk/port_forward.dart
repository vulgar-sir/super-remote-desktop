// super远程桌面: port-mapping window in the UU-remote-like layout -- device name + status, a "映射列表" card with
// "添加", a table (名称 / 本地端口 / 目标地址 / 目标端口 / 映射状态 / 操作). Mappings are read from the peer config and
// added / removed with the same session calls as RustDesk's own port-forward page.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/models/platform_model.dart';

import 'theme.dart';

class SdPortForwardView extends StatefulWidget {
  final String id;
  final SessionID sessionId;
  const SdPortForwardView({Key? key, required this.id, required this.sessionId}) : super(key: key);

  @override
  State<SdPortForwardView> createState() => _SdPortForwardViewState();
}

class _SdPortForwardViewState extends State<SdPortForwardView> {
  List<(int, String, int)> _pfs = [];
  String _name = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    try {
      final config = jsonDecode(bind.mainGetPeerSync(id: widget.id));
      final list = <(int, String, int)>[];
      for (final e in (config['port_forwards'] as List? ?? [])) {
        if (e is List && e.length >= 3) list.add((e[0] as int, '${e[1]}', e[2] as int));
      }
      final info = config['info'] is Map ? config['info'] as Map : const {};
      final opts = config['options'] is Map ? config['options'] as Map : const {};
      final alias = '${opts['alias'] ?? ''}';
      final host = '${info['hostname'] ?? ''}';
      setState(() {
        _pfs = list;
        _name = alias.isNotEmpty ? alias : (host.isNotEmpty ? host : widget.id);
      });
    } catch (_) {}
  }

  Future<void> _remove(int localPort) async {
    await bind.sessionRemovePortForward(sessionId: widget.sessionId, localPort: localPort);
    _load();
  }

  void _addDialog() {
    final local = TextEditingController();
    final host = TextEditingController();
    final remote = TextEditingController();
    final ports = [
      FilteringTextInputFormatter.allow(RegExp(
          r'^([0-9]|[1-9]\d|[1-9]\d{2}|[1-9]\d{3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'))
    ];
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        Future<void> submit() async {
          final l = int.tryParse(local.text);
          final r = int.tryParse(remote.text);
          if (l == null || r == null) {
            setState(() => error = '请填写本地端口和目标端口');
            return;
          }
          if (_pfs.any((x) => x.$1 == l)) {
            setState(() => error = '本地端口 $l 已在映射列表中');
            return;
          }
          await bind.sessionAddPortForward(
              sessionId: widget.sessionId,
              localPort: l,
              remoteHost: host.text.trim().isEmpty ? 'localhost' : host.text.trim(),
              remotePort: r);
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }

        InputDecoration deco(String label, [String? hint]) =>
            InputDecoration(labelText: label, hintText: hint, isDense: true, border: const OutlineInputBorder());
        return AlertDialog(
          title: const Text('添加端口映射'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: local, autofocus: true, inputFormatters: ports, decoration: deco('本地端口', '例如 13389')),
              const SizedBox(height: 12),
              TextField(controller: host, decoration: deco('目标地址', 'localhost（对方电脑本身）')),
              const SizedBox(height: 12),
              TextField(
                  controller: remote,
                  inputFormatters: ports,
                  decoration: deco('目标端口', '例如 3389'),
                  onSubmitted: (_) => submit()),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(onPressed: submit, child: const Text('添加')),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    final active = _pfs.isNotEmpty;
    TextStyle head = TextStyle(fontSize: 13.5, color: p.muted);
    TextStyle cell = TextStyle(fontSize: 14, color: p.text);
    Widget row(List<Widget> cells, {Color? color, double height = 44}) => Container(
          height: height,
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(flex: 14, child: cells[0]),
            Expanded(flex: 12, child: cells[1]),
            Expanded(flex: 16, child: cells[2]),
            Expanded(flex: 12, child: cells[3]),
            Expanded(flex: 14, child: cells[4]),
            SizedBox(width: 72, child: cells[5]),
          ]),
        );
    return Container(
      color: p.page,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
            child: Text(_name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text)),
          ),
          const SizedBox(width: 12),
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: active ? kSdOnline : p.hint, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(active ? '映射中' : '未添加映射', style: TextStyle(fontSize: 13.5, color: p.muted)),
        ]),
        const SizedBox(height: 18),
        Expanded(
          child: Container(
            decoration:
                BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(6), border: Border.all(color: p.line)),
            child: Column(children: [
              SizedBox(
                height: 46,
                child: Row(children: [
                  const SizedBox(width: 12),
                  Text('映射列表', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addDialog,
                    icon: Icon(Icons.add_circle_outline_rounded, size: 18, color: p.text),
                    label: Text('添加', style: TextStyle(fontSize: 14, color: p.text)),
                  ),
                  const SizedBox(width: 4),
                ]),
              ),
              Divider(height: 1, color: p.divider),
              row([
                Text('名称', style: head),
                Text('本地端口', style: head),
                Text('目标地址', style: head),
                Text('目标端口', style: head),
                Text('映射状态', style: head),
                Text('操作', style: head),
              ], height: 34),
              Expanded(
                child: _pfs.isEmpty
                    ? Center(
                        child: Text('还没有映射，点右上角“添加”把对方电脑的端口映射到本机',
                            style: TextStyle(fontSize: 13.5, color: p.hint)))
                    : ListView(
                        children: [
                          for (var i = 0; i < _pfs.length; i++)
                            row([
                              Text('端口${i + 1}', style: cell),
                              Text('${_pfs[i].$1}', style: cell),
                              Text(_pfs[i].$2, style: cell, overflow: TextOverflow.ellipsis),
                              Text('${_pfs[i].$3}', style: cell),
                              Row(children: [
                                const Icon(Icons.check_rounded, size: 16, color: kSdOnline),
                                const SizedBox(width: 2),
                                Text('监听中', style: cell),
                              ]),
                              PopupMenuButton<int>(
                                tooltip: '更多',
                                icon: Icon(Icons.more_horiz_rounded, color: p.text, size: 20),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 1, height: 36, child: Text('复制本地地址')),
                                  PopupMenuItem(value: 2, height: 36, child: Text('删除')),
                                ],
                                onSelected: (v) {
                                  if (v == 1) sdCopy('127.0.0.1:${_pfs[i].$1}');
                                  if (v == 2) _remove(_pfs[i].$1);
                                },
                              ),
                            ], color: i.isEven ? (p.dark ? p.soft : const Color(0xFFF2F3F4)) : null),
                        ],
                      ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Text('在本机访问 127.0.0.1:本地端口，即可连到对方电脑上的“目标地址:目标端口”；关闭此窗口后映射停止。',
            style: TextStyle(fontSize: 12.5, color: p.hint)),
      ]),
    );
  }
}
