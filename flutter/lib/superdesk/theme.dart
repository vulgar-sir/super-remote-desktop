// super远程桌面: shared palette and small widgets for the redesigned client UI (desktop + mobile).
// Light colours follow the UU-remote-like layout the product uses (own branding and icons).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';

const kSdAccent = Color(0xFF3A7BFC);
const kSdOnline = Color(0xFF11C78A);
const kSdTile = Color(0xFF2F83FF);

class SdPalette {
  final bool dark;
  SdPalette(BuildContext c) : dark = Theme.of(c).brightness == Brightness.dark;
  Color get page => dark ? const Color(0xFF13171E) : const Color(0xFFF8FBFD);
  Color get side => dark ? const Color(0xFF181D25) : const Color(0xFFF0F5F8);
  Color get card => dark ? const Color(0xFF1E242D) : Colors.white;
  Color get field => dark ? const Color(0xFF151A21) : Colors.white;
  Color get line => dark ? const Color(0xFF2A313C) : const Color(0xFFE3E5E6);
  Color get divider => dark ? const Color(0xFF2A313C) : const Color(0xFFE6E6E6);
  Color get text => dark ? const Color(0xFFE8EAEE) : const Color(0xFF191919);
  Color get muted => dark ? const Color(0xFF98A2B3) : const Color(0xFF656565);
  Color get hint => dark ? const Color(0xFF7D8696) : const Color(0xFF8C8C8C);
  Color get soft => dark ? const Color(0xFF262D38) : const Color(0xFFE4E9EB);
  Color get badge => dark ? const Color(0xFF22314E) : const Color(0xFFDEF0FF);
  Color get disabled => dark ? const Color(0xFF3A414C) : const Color(0xFFC3C3C3);
}

Widget sdCard(SdPalette p, {required Widget child, EdgeInsets? padding}) => Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.line),
      ),
      child: child,
    );

Widget sdIconButton(SdPalette p, IconData icon, String tip, VoidCallback onTap, {Color? color, double size = 19}) =>
    IconButton(
      tooltip: tip,
      onPressed: onTap,
      splashRadius: 18,
      iconSize: size,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: Icon(icon, color: color ?? p.muted),
    );

void sdCopy(String text) {
  Clipboard.setData(ClipboardData(text: text));
  showToast(translate('Copied'));
}

/// Primary (filled) button; grey and inert while [onPressed] is null.
Widget sdPrimaryButton(SdPalette p, String label, VoidCallback? onPressed,
        {double height = 32, double minWidth = 88, double fontSize = 14}) =>
    SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kSdAccent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.disabled,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          minimumSize: Size(minWidth, height),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Text(label, style: TextStyle(fontSize: fontSize)),
      ),
    );

/// Secondary (white, hairline border) button.
Widget sdOutlineButton(SdPalette p, String label, VoidCallback? onPressed,
        {double height = 32, double minWidth = 88, IconData? icon}) =>
    SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          backgroundColor: p.card,
          minimumSize: Size(minWidth, height),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide(color: p.dark ? p.line : const Color(0xFFE5E5E5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: p.text), const SizedBox(width: 6)],
          Text(label, style: const TextStyle(fontSize: 14)),
        ]),
      ),
    );

/// Text field with a hairline border and a darker bottom edge.
InputDecoration sdInputDecoration(SdPalette p, String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: p.hint, fontSize: 14),
      filled: true,
      fillColor: p.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: p.divider)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: kSdAccent, width: 1.2)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: p.divider)),
    );

/// "开/关" caption + switch, as on the settings rows.
Widget sdSwitch(SdPalette p, bool value, ValueChanged<bool>? onChanged, {bool caption = true}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      if (caption)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(value ? '开' : '关', style: TextStyle(fontSize: 14, color: p.text)),
        ),
      Transform.scale(
        scale: 0.85,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Colors.white,
          activeTrackColor: kSdAccent,
          inactiveThumbColor: p.muted,
          inactiveTrackColor: p.card,
          trackOutlineColor: MaterialStateProperty.resolveWith(
              (s) => s.contains(MaterialState.selected) ? kSdAccent : p.hint),
        ),
      ),
    ]);

/// Big "label / value / actions" block used for the device code and the verification code.
Widget sdCodeField(SdPalette p,
    {required String label, required String value, double size = 30, List<Widget> actions = const []}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(fontSize: 13, color: p.muted)),
      const SizedBox(height: 4),
      Row(
        children: [
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w600,
                    letterSpacing: size > 24 ? 1.2 : 0,
                    color: p.text,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 4),
          ...actions,
        ],
      ),
    ],
  );
}

/// Platform tile (blue rounded square with the OS glyph), as used in device lists.
Widget sdPlatformTile(String platform, {double size = 32, bool online = true}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? kSdTile : const Color(0xFFB4B9C0),
        borderRadius: BorderRadius.circular(size * 0.18),
      ),
      child: Center(child: sdPlatformIcon(platform, size: size * 0.55, color: Colors.white)),
    );

IconData _platformIcon(String platform) {
  final pl = platform.toLowerCase();
  if (pl.contains('android')) return Icons.android;
  if (pl.contains('mac') || pl.contains('ios')) return Icons.apple;
  if (pl.contains('linux')) return Icons.terminal;
  return Icons.window;
}

Widget sdPlatformIcon(String platform, {double size = 18, Color? color}) =>
    Icon(_platformIcon(platform), size: size, color: color);

bool sdIsMobilePlatform(String platform) {
  final pl = platform.toLowerCase();
  return pl.contains('android') || pl.contains('ios');
}
