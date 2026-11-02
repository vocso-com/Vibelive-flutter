import 'package:flutter/material.dart';

import '../core/text_overlay.dart';
import '../strings.dart';

/// Typing a caption: the text over the dimmed clip, a colour row, the box
/// style and the size. Done hands the caption back (empty text removes it);
/// Cancel hands back nothing.
class VibeTextEditor extends StatefulWidget {
  const VibeTextEditor({super.key, required this.initial, required this.strings, required this.accent});

  final VibeTextOverlay initial;
  final VibeCameraStrings strings;
  final Color accent;

  static const palette = [
    Color(0xFFFFFFFF),
    Color(0xFF111111),
    Color(0xFFFF2E7E),
    Color(0xFFFFD54F),
    Color(0xFF4DD0E1),
    Color(0xFF69F0AE),
    Color(0xFF7C4DFF),
    Color(0xFFFF7043),
    Color(0xFFE53935),
  ];

  @override
  State<VibeTextEditor> createState() => _VibeTextEditorState();
}

class _VibeTextEditorState extends State<VibeTextEditor> {
  late VibeTextOverlay _t = widget.initial;
  late final _field = TextEditingController(text: widget.initial.text);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _set(VibeTextOverlay next) => setState(() => _t = next);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final fontSize = _t.size * width * 0.9;
    final fill = switch (_t.style) {
      VibeTextStyle.boxed => _t.color,
      VibeTextStyle.soft => const Color(0x73000000),
      VibeTextStyle.plain => Colors.transparent,
    };
    final ink = _t.style == VibeTextStyle.boxed ? VibeTextOverlay.onColor(_t.color) : _t.color;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(widget.strings.cancel, style: const TextStyle(color: Colors.white)),
                ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('vibe-text-style'),
                  tooltip: 'Style',
                  onPressed: () => _set(_t.copyWith(
                    style: VibeTextStyle.values[(_t.style.index + 1) % VibeTextStyle.values.length],
                  )),
                  icon: Icon(
                    switch (_t.style) {
                      VibeTextStyle.plain => Icons.format_color_text_rounded,
                      VibeTextStyle.boxed => Icons.rectangle_rounded,
                      VibeTextStyle.soft => Icons.rectangle_outlined,
                    },
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  key: const ValueKey('vibe-text-done'),
                  onPressed: () => Navigator.of(context).pop(_t.copyWith(text: _field.text.trim())),
                  child: Text(
                    widget.strings.done,
                    style: TextStyle(color: widget.accent, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Row(
                children: [
                  // Size.
                  RotatedBox(
                    quarterTurns: 3,
                    child: SizedBox(
                      width: 220,
                      child: Slider(
                        value: _t.size,
                        min: 0.04,
                        max: 0.14,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                        onChanged: (v) => _set(_t.copyWith(size: v)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.42, vertical: fontSize * 0.22),
                        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(fontSize * 0.32)),
                        child: IntrinsicWidth(
                          child: TextField(
                            key: const ValueKey('vibe-text-field'),
                            controller: _field,
                            autofocus: true,
                            maxLines: null,
                            textAlign: TextAlign.center,
                            cursorColor: widget.accent,
                            style: TextStyle(
                              color: ink,
                              fontSize: fontSize,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              shadows: _t.style == VibeTextStyle.plain
                                  ? const [Shadow(color: Color(0x99000000), blurRadius: 8)]
                                  : null,
                            ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              hintText: widget.strings.typeSomething,
                              hintStyle: TextStyle(color: ink.withValues(alpha: 0.5), fontSize: fontSize),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in VibeTextEditor.palette)
                    GestureDetector(
                      onTap: () => _set(_t.copyWith(color: c)),
                      child: Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c == _t.color ? widget.accent : Colors.white,
                            width: c == _t.color ? 3 : 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
