// super远程桌面 防窥: the remote toolbar button and the notices. The cover is RustDesk's privacy mode;
// what it shows and what happens after the session are sent with each turn-on request from these
// options (src/superdesk/privacy.rs), and sessions turn it on by themselves unless the auto option is "N".

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/shared_state.dart';
import 'package:flutter_hbb/common/widgets/toolbar.dart' show togglePrivacyModeTime;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import 'quick_apps.dart' show kSdToolbarHover, kSdToolbarIcon;
import 'theme.dart';

const kSdOptionPrivacyAuto = 'superdesk-privacy-auto';
const kSdOptionPrivacyCover = 'superdesk-privacy-cover';
const kSdOptionPrivacyText = 'superdesk-privacy-text';
const kSdOptionPrivacyAfter = 'superdesk-privacy-after';
const kSdPrivacyDefaultText = '此电脑正在被远程使用，屏幕内容已隐藏';
const kSdPrivacyImplVirtualDisplay = 'privacy_mode_impl_virtual_display';

/// Implementation to ask the peer for, by the 显示方式 setting, among those it supports (null: none).
String? sdPrivacyImplKey(FFI ffi) {
  final impls = ffi.ffiModel.pi.platformAdditions[kPlatformAdditionsSupportedPrivacyModeImpl] as List<dynamic>?;
  if (impls == null || impls.isEmpty) return null;
  final keys = impls.map((e) => (e as List<dynamic>)[0] as String).toList();
  if (bind.mainGetOptionSync(key: kSdOptionPrivacyCover) == 'display-off' &&
      keys.contains(kSdPrivacyImplVirtualDisplay)) {
    return kSdPrivacyImplVirtualDisplay;
  }
  return keys.firstWhere((k) => k != kSdPrivacyImplVirtualDisplay, orElse: () => keys.first);
}

/// Turn-on / turn-off notices as a toast: with 防窥 on by default a dialog would open with every session.
bool sdPrivacyNotice(String type, String text) {
  if (type != 'custom-nocancel') return false;
  showToast(text == 'Enter privacy mode'
      ? '已开启防窥'
      : text == 'Exit privacy mode'
          ? '已关闭防窥'
          : translate(text));
  return true;
}

/// "防窥" in the remote toolbar: filled blue while the peer's screen is covered.
class SdPrivacyToolbarButton extends StatefulWidget {
  final String id;
  final FFI ffi;
  const SdPrivacyToolbarButton({Key? key, required this.id, required this.ffi}) : super(key: key);

  @override
  State<SdPrivacyToolbarButton> createState() => _SdPrivacyToolbarButtonState();
}

class _SdPrivacyToolbarButtonState extends State<SdPrivacyToolbarButton> {
  bool _hover = false;

  void _toggle(String state, String? impl) {
    togglePrivacyModeTime = DateTime.now();
    bind.sessionTogglePrivacyMode(
        sessionId: widget.ffi.sessionId, implKey: state.isNotEmpty ? state : impl!, on: state.isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: widget.ffi.ffiModel,
      builder: (context, _) => Obx(() {
        final state = PrivacyModeState.find(widget.id).value;
        final on = state.isNotEmpty;
        final model = widget.ffi.ffiModel;
        final impl = sdPrivacyImplKey(widget.ffi);
        final allowed = model.permissions['privacy_mode'] != false &&
            impl != null &&
            model.pi.platformAdditions['sd_privacy_cover'] == true;
        if (!on && !allowed) return const Offstage();
        final Color bg = on
            ? kSdAccent.withOpacity(dark ? 0.28 : 0.14)
            : (_hover ? (dark ? const Color(0xFF2A3442) : kSdToolbarHover) : Colors.transparent);
        final Color fg = on || _hover ? kSdAccent : (dark ? const Color(0xFFE8EAEE) : kSdToolbarIcon);
        return Tooltip(
          message: on ? '防窥已开启：对方屏幕已黑屏，点击关闭' : '开启防窥：对方屏幕黑屏并锁住本地键鼠',
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: () => _toggle(state, impl),
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                child: Icon(on ? Icons.visibility_off_rounded : Icons.visibility_off_outlined, size: 20, color: fg),
              ),
            ),
          ),
        );
      }),
    );
  }
}
