// super远程桌面 无线副屏 (like the reference's wireless second screen): this device becomes an extra monitor
// of a Windows PC. Built from RustDesk's own pieces: connect, plug in one of the PC's virtual displays
// (IDD driver of the installed service) and show only that display. The PC unplugs its virtual displays
// when the last remote session ends, so nothing is left behind.
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const _kExtendOnConnect = 'sd-extend-on-connect';

/// Device page action: connect and turn this device into the PC's second screen.
Future<void> sdStartExtendScreen(BuildContext context, String peerId) async {
  await bind.mainSetPeerOption(id: peerId, key: _kExtendOnConnect, value: 'Y');
  if (context.mounted) connect(context, peerId);
}

/// Called once the remote session is up (model.dart).
void sdExtendScreenOnConnected(FfiModel model, String peerId) {
  final ffi = model.parent.target;
  if (ffi == null) return;
  if (bind.mainGetPeerOptionSync(id: peerId, key: _kExtendOnConnect) != 'Y') return;
  bind.mainSetPeerOption(id: peerId, key: _kExtendOnConnect, value: '');
  Future.delayed(const Duration(milliseconds: 1200), () => _plugInAndShow(ffi));
}

Future<void> _plugInAndShow(FFI ffi) async {
  final pi = ffi.ffiModel.pi;
  if (!pi.isRustDeskIdd && !pi.isAmyuniIdd) {
    ffi.dialogManager.show((setState, close, context) => CustomAlertDialog(
          title: const Text('无法开启无线副屏'),
          content: const Text('对方电脑需要安装 super远程桌面（以服务方式运行），并且是 Windows 10 2004 或更新的版本。\n'
              '当前已按普通远控连接。'),
          actions: [dialogButton('OK', onPressed: close)],
          onSubmit: close,
          onCancel: close,
        ));
    return;
  }
  final before = pi.displays.length;
  var index = 0; // Amyuni: "add one"
  if (pi.isRustDeskIdd) {
    final used = pi.RustDeskVirtualDisplays;
    index = List.generate(kMaxVirtualDisplayCount, (i) => i + 1).firstWhere((i) => !used.contains(i), orElse: () => -2);
    if (index == -2) {
      showToast('对方电脑的虚拟显示器已用完');
      return;
    }
  }
  await bind.sessionToggleVirtualDisplay(sessionId: ffi.sessionId, index: index, on: true);
  // the new display shows up with the next peer-info update
  for (var i = 0; i < 24; i++) {
    await Future.delayed(const Duration(milliseconds: 500));
    final now = ffi.ffiModel.pi;
    if (now.displays.length > before) {
      openMonitorInTheSameTab(now.displays.length - 1, ffi, now);
      showToast('已开启无线副屏：本机画面就是对方电脑新增的扩展屏');
      return;
    }
  }
  showToast('对方电脑暂未出现新的显示器，可稍后在显示器菜单中手动切换');
}
