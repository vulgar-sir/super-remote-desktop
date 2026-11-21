// super远程桌面: shared palette and small widgets for the redesigned client UI (desktop + mobile).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';

const kSdAccent = Color(0xFF2F6BFF);

class SdPalette {
  final bool dark;
  SdPalette(BuildContext c) : dark = Theme.of(c).brightness == Brightness.dark;
  Color get page => dark ? const Color(0xFF13171E) : const Color(0xFFF3F5F9);
  Color get side => dark ? const Color(0xFF181D25) : Colors.white;
  Color get card => dark ? const Color(0xFF1E242D) : Colors.white;
  Color get field => dark ? const Color(0xFF151A21) : const Color(0xFFF3F5F9);
  Color get line => dark ? const Color(0xFF2A313C) : const Color(0xFFE5E8EE);
  Color get text => dark ? const Color(0xFFE8EAEE) : const Color(0xFF1D2433);
  Color get muted => dark ? const Color(0xFF98A2B3) : const Color(0xFF6B7385);
  Color get soft => dark ? const Color(0xFF22314E) : const Color(0xFFEAF0FF);
}

Widget sdCard(SdPalette p, {required Widget child, EdgeInsets? padding}) => Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
        boxShadow: p.dark
            ? null
            : const [BoxShadow(color: Color(0x0D1D2433), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: child,
    );

Widget sdIconButton(SdPalette p, IconData icon, String tip, VoidCallback onTap) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      splashRadius: 18,
      iconSize: 19,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: Icon(icon, color: p.muted),
    );

void sdCopy(String text) {
  Clipboard.setData(ClipboardData(text: text));
  showToast(translate('Copied'));
}

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

