// super远程桌面: shared palette and small widgets for the redesigned client UI (desktop + mobile).
// Light colours follow the UU-remote-like layout the product uses (own branding and icons).
import 'dart:math';

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

/// "开/关" caption + Fluent-style toggle, as on the settings rows.
Widget sdSwitch(SdPalette p, bool value, ValueChanged<bool>? onChanged, {bool caption = true}) =>
    Row(mainAxisSize: MainAxisSize.min, children: [
      if (caption)
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(value ? '开' : '关', style: TextStyle(fontSize: 14, color: p.text)),
        ),
      SdToggle(value: value, onChanged: onChanged),
    ]);

/// Windows 11 (Fluent) toggle: 40x20 pill, 12px knob; filled accent when on, outlined when off.
class SdToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const SdToggle({Key? key, required this.value, this.onChanged}) : super(key: key);

  @override
  State<SdToggle> createState() => _SdToggleState();
}

class _SdToggleState extends State<SdToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    final on = widget.value;
    final enabled = widget.onChanged != null;
    final off = p.dark ? const Color(0xFFB0B0B0) : const Color(0xFF5C5C5C);
    final knob = 12.0 + (_hover && enabled ? 2 : 0);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? () => widget.onChanged!(!on) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 40,
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: on ? kSdAccent : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: on ? kSdAccent : off, width: 1),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: knob,
                height: knob,
                decoration: BoxDecoration(color: on ? Colors.white : off, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fluent text box: hairline frame with a darker bottom edge (accent while focused).
class SdTextBox extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final double width;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  const SdTextBox(
      {Key? key,
      required this.controller,
      required this.hint,
      this.width = 170,
      this.inputFormatters,
      this.onSubmitted,
      this.autofocus = false})
      : super(key: key);

  @override
  State<SdTextBox> createState() => _SdTextBoxState();
}

class _SdTextBoxState extends State<SdTextBox> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    final focused = _focus.hasFocus;
    final edge = p.dark ? p.line : const Color(0xFFE5E5E5);
    return Container(
      width: widget.width,
      height: 32,
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: edge),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border(
            bottom: BorderSide(
                color: focused ? kSdAccent : (p.dark ? p.hint : const Color(0xFF8A8A8A)),
                width: focused ? 2 : 1)),
      ),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        inputFormatters: widget.inputFormatters,
        onSubmitted: widget.onSubmitted,
        cursorWidth: 1.2,
        style: TextStyle(fontSize: 14.5, color: p.text),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: p.hint, fontSize: 14.5),
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
        ),
      ),
    );
  }
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

/// Platform tile (blue rounded square with the OS glyph), as used in device lists.
Widget sdPlatformTile(String platform, {double size = 32, bool online = true}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? kSdTile : const Color(0xFFB4B9C0),
        borderRadius: BorderRadius.circular(size * 0.2),
      ),
      child: Center(child: sdPlatformIcon(platform, size: size * 0.56, color: Colors.white)),
    );

/// OS glyph; Windows is drawn as the four-pane logo.
Widget sdPlatformIcon(String platform, {double size = 18, Color? color}) {
  final pl = platform.toLowerCase();
  final c = color ?? const Color(0xFF191919);
  if (pl.contains('android')) return Icon(Icons.android, size: size, color: c);
  if (pl.contains('mac') || pl.contains('ios')) return Icon(Icons.apple, size: size, color: c);
  if (pl.contains('linux')) return Icon(Icons.terminal, size: size, color: c);
  return CustomPaint(size: Size.square(size * 0.82), painter: _WinLogo(c));
}

class _WinLogo extends CustomPainter {
  final Color color;
  _WinLogo(this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final g = s.width * 0.1, h = (s.width - g) / 2, r = Radius.circular(s.width * 0.06);
    final paint = Paint()..color = color;
    for (final o in [Offset.zero, Offset(h + g, 0), Offset(0, h + g), Offset(h + g, h + g)]) {
      canvas.drawRRect(RRect.fromRectAndRadius(o & Size(h, h), r), paint);
    }
  }

  @override
  bool shouldRepaint(_WinLogo old) => old.color != color;
}

/// Sidebar / page icons in the reference style: thin line icons for section headers, two-tone blue
/// glyphs for entries. Drawn on a 20x20 grid and scaled to [size].
enum SdGlyph {
  devices,
  assist,
  allDevices,
  startAssist,
  favorites,
  emptyBox,
  // title bar: one stroke weight and colour for all of them
  barScreens,
  barBell,
  barUser,
  barMenu,
  barMinimize,
  barClose,
}

class SdIcon extends StatelessWidget {
  final SdGlyph glyph;
  final double size;
  final Color? color;
  const SdIcon(this.glyph, {Key? key, this.size = 20, this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GlyphPainter(glyph, color ?? SdPalette(context).text));
}

/// Main-window title-bar button: line glyph, rounded grey square on hover (red for close), no ripple and
/// no focus ring. [onTap] gets the button's own context so a menu can open under it.
class SdBarButton extends StatefulWidget {
  final SdGlyph glyph;
  final String tip;
  final void Function(BuildContext context) onTap;
  final bool danger;
  final Widget? badge;
  const SdBarButton(this.glyph, this.tip, this.onTap, {Key? key, this.danger = false, this.badge}) : super(key: key);

  @override
  State<SdBarButton> createState() => _SdBarButtonState();
}

class _SdBarButtonState extends State<SdBarButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = SdPalette(context);
    final red = widget.danger && _hover;
    final bg = red
        ? const Color(0xFFE5484D)
        : _down
            ? (p.dark ? const Color(0xFF323A47) : const Color(0xFFD8DEE2))
            : _hover
                ? p.soft
                : Colors.transparent;
    return Tooltip(
      message: widget.tip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = _down = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTap: () {
            setState(() => _down = false);
            widget.onTap(context);
          },
          child: SizedBox(
            width: 52,
            height: 48,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                child: Stack(clipBehavior: Clip.none, children: [
                  SdIcon(widget.glyph, size: 22, color: red ? Colors.white : p.text),
                  if (widget.badge != null) Positioned(right: -7, top: -5, child: IgnorePointer(child: widget.badge!)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a menu under a title-bar button, right-aligned with it (the menu takes the button's context).
Future<T?> sdBarMenu<T>(BuildContext context, List<PopupMenuEntry<T>> items) {
  final p = SdPalette(context);
  final box = context.findRenderObject() as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final rect = Rect.fromPoints(box.localToGlobal(Offset(0, box.size.height - 6), ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay));
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    items: items,
    color: p.card,
    elevation: 6,
    shadowColor: Colors.black38,
    surfaceTintColor: Colors.transparent,
    constraints: const BoxConstraints(minWidth: 168),
    menuPadding: const EdgeInsets.symmetric(vertical: 6),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: p.line)),
  );
}

PopupMenuItem<T> sdBarMenuItem<T>(SdPalette p, T value, IconData icon, String label) => PopupMenuItem<T>(
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Icon(icon, size: 18, color: p.text),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 14, color: p.text)),
      ]),
    );

class _GlyphPainter extends CustomPainter {
  final SdGlyph glyph;
  final Color line;
  _GlyphPainter(this.glyph, this.line);

  static RRect _rr(double l, double t, double r, double b, double rad) =>
      RRect.fromLTRBR(l, t, r, b, Radius.circular(rad));

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 20;
    canvas.save();
    canvas.scale(k);
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Paint fill(Color c) => Paint()..color = c;
    final grad = Paint()
      ..shader = const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF4F8EFF), Color(0xFF2E6FF5)])
          .createShader(const Rect.fromLTWH(0, 0, 20, 20));
    final light = Paint()
      ..shader = const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9CC2FF), Color(0xFF7DAEFF)])
          .createShader(const Rect.fromLTWH(0, 0, 20, 20));
    Path corner(Offset a, Offset c, Offset b) => Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(c.dx + (a.dx - c.dx).sign * 1.6, c.dy + (a.dy - c.dy).sign * 1.6)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + (b.dx - c.dx).sign * 1.6, c.dy + (b.dy - c.dy).sign * 1.6)
      ..lineTo(b.dx, b.dy);
    switch (glyph) {
      case SdGlyph.devices: // open laptop frame with base + a second screen, outlined
        canvas.drawPath(corner(const Offset(9.2, 4.2), const Offset(3.6, 4.2), const Offset(3.6, 12.4)), stroke);
        canvas.drawLine(const Offset(2, 15.4), const Offset(8, 15.4), stroke..strokeWidth = 1.6);
        stroke.strokeWidth = 1.35;
        canvas.drawRRect(_rr(9.6, 8.8, 18.2, 16.2, 1.6), stroke);
        break;
      case SdGlyph.assist: // corner brackets + two small boxes, outlined
        canvas.drawPath(corner(const Offset(8.4, 3.8), const Offset(3.4, 3.8), const Offset(3.4, 8.6)), stroke);
        canvas.drawRRect(_rr(11.4, 3.4, 17.2, 8.6, 1.8), stroke);
        canvas.drawRRect(_rr(3, 11.4, 8.8, 16.4, 1.8), stroke);
        canvas.drawPath(corner(const Offset(16.8, 11.4), const Offset(16.8, 16.4), const Offset(11.8, 16.4)), stroke);
        break;
      case SdGlyph.allDevices: // 2x2 dots, two-tone
        canvas.drawCircle(const Offset(5.8, 5.8), 4, grad);
        canvas.drawCircle(const Offset(14.2, 5.8), 4, light);
        canvas.drawCircle(const Offset(5.8, 14.2), 4, light);
        canvas.drawCircle(const Offset(14.2, 14.2), 4, grad);
        break;
      case SdGlyph.startAssist: // filled boxes on one diagonal, thick brackets on the other
        final br = Paint()
          ..shader = grad.shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.1
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(corner(const Offset(8.4, 3.4), const Offset(3, 3.4), const Offset(3, 8.4)), br);
        canvas.drawRRect(_rr(10.8, 1.8, 18.4, 9, 2.2), grad);
        canvas.drawRRect(_rr(1.8, 10.8, 9.2, 18.2, 2.2), grad);
        canvas.drawPath(corner(const Offset(17, 11.6), const Offset(17, 16.8), const Offset(11.6, 16.8)), br);
        break;
      case SdGlyph.favorites: // bookmark with a star
        final b = Path()
          ..moveTo(3.4, 3.4)
          ..quadraticBezierTo(3.4, 1.8, 5, 1.8)
          ..lineTo(15, 1.8)
          ..quadraticBezierTo(16.6, 1.8, 16.6, 3.4)
          ..lineTo(16.6, 18.4)
          ..lineTo(10, 14.6)
          ..lineTo(3.4, 18.4)
          ..close();
        canvas.drawPath(b, grad);
        canvas.drawPath(_star(const Offset(10, 8.4), 3.5, 1.55), fill(const Color(0xFFDDEBFF)));
        break;
      case SdGlyph.emptyBox: // open box with a star (empty state)
        const c1 = Color(0xFFB9D6FB), c2 = Color(0xFFD7E8FD), c3 = Color(0xFF9CC5F7);
        canvas.drawRRect(_rr(3, 8, 17, 17.5, 1), fill(c1));
        canvas.drawPath(
            Path()
              ..moveTo(3, 8)
              ..lineTo(5.5, 4.5)
              ..lineTo(10, 4.5)
              ..lineTo(10, 8)
              ..close(),
            fill(c2));
        canvas.drawPath(
            Path()
              ..moveTo(10, 4.5)
              ..lineTo(14.5, 4.5)
              ..lineTo(17, 8)
              ..lineTo(10, 8)
              ..close(),
            fill(c3));
        canvas.drawPath(
            Path()
              ..moveTo(17, 8)
              ..lineTo(19.5, 10.5)
              ..lineTo(17, 10.5)
              ..close(),
            fill(c3));
        canvas.drawPath(_star(const Offset(10, 12.8), 2.6, 1.1), fill(Colors.white));
        break;
      case SdGlyph.barScreens: // two overlapping windows, the back one peeking out top-right
        stroke.strokeWidth = 1.3;
        final front = _rr(2.6, 7, 13.6, 16.4, 2);
        canvas.save();
        canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(const Rect.fromLTWH(0, 0, 20, 20)),
            Path()..addRRect(front.inflate(1.6))));
        canvas.drawRRect(_rr(6.4, 3.6, 17.4, 13, 2), stroke);
        canvas.restore();
        canvas.drawRRect(front, stroke);
        break;
      case SdGlyph.barBell:
        stroke.strokeWidth = 1.3;
        canvas.drawPath(
            Path()
              ..moveTo(5.4, 14.4)
              ..lineTo(5.4, 9.2)
              ..arcToPoint(const Offset(14.6, 9.2), radius: const Radius.circular(4.6))
              ..lineTo(14.6, 14.4),
            stroke);
        canvas.drawLine(const Offset(3.6, 14.4), const Offset(16.4, 14.4), stroke);
        canvas.drawLine(const Offset(10, 2.8), const Offset(10, 4.6), stroke);
        canvas.drawPath(
            Path()
              ..moveTo(8.2, 16.6)
              ..arcToPoint(const Offset(11.8, 16.6), radius: const Radius.circular(1.8), clockwise: false),
            stroke);
        break;
      case SdGlyph.barUser: // head + bowl-shaped shoulders
        stroke.strokeWidth = 1.3;
        canvas.drawCircle(const Offset(10, 5.8), 2.8, stroke);
        canvas.drawPath(
            Path()
              ..moveTo(4.2, 11.8)
              ..lineTo(15.8, 11.8)
              ..arcToPoint(const Offset(4.2, 11.8), radius: const Radius.circular(5.8))
              ..close(),
            stroke);
        break;
      case SdGlyph.barMenu:
        stroke.strokeWidth = 1.3;
        for (final y in [4.6, 10.0, 15.4]) {
          canvas.drawLine(Offset(3.4, y), Offset(16.6, y), stroke);
        }
        break;
      case SdGlyph.barMinimize:
        stroke.strokeWidth = 1.3;
        canvas.drawLine(const Offset(4.6, 10), const Offset(15.4, 10), stroke);
        break;
      case SdGlyph.barClose:
        stroke.strokeWidth = 1.3;
        canvas.drawLine(const Offset(5, 5), const Offset(15, 15), stroke);
        canvas.drawLine(const Offset(15, 5), const Offset(5, 15), stroke);
        break;
    }
    canvas.restore();
  }

  static Path _star(Offset c, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -pi / 2 + i * pi / 5;
      final x = c.dx + r * cos(a), y = c.dy + r * sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.line != line;
}

/// Closed-eye glyph (code hidden), outlined.
class SdClosedEye extends StatelessWidget {
  final double size;
  final Color color;
  const SdClosedEye({Key? key, this.size = 20, required this.color}) : super(key: key);
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _ClosedEye(color));
}

class _ClosedEye extends CustomPainter {
  final Color color;
  _ClosedEye(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(2.5, 8)
          ..quadraticBezierTo(10, 15, 17.5, 8),
        p);
    canvas.drawLine(const Offset(5, 10.6), const Offset(3.6, 12.6), p);
    canvas.drawLine(const Offset(10, 11.6), const Offset(10, 14), p);
    canvas.drawLine(const Offset(15, 10.6), const Offset(16.4, 12.6), p);
  }

  @override
  bool shouldRepaint(_ClosedEye old) => old.color != color;
}

bool sdIsMobilePlatform(String platform) {
  final pl = platform.toLowerCase();
  return pl.contains('android') || pl.contains('ios');
}
