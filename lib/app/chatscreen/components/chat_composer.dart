import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../component/pressable.dart';
import '../helper/chat_format.dart';
import 'chat_palette.dart';
import 'voice_recorder.dart';

/// The input bar: a photo button, the text field, and send (with text) or
/// a hold-to-record mic (without). No prices here: chat prices show only
/// in the chat menu's Prices sheet. Typing rebuilds only the parts that
/// change (the send / mic swap, the counter).
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.maxLength,
    required this.voiceMaxSeconds,
    required this.onSend,
    required this.onAttach,
    required this.onVoice,
  });

  final TextEditingController controller;
  final int maxLength;

  final int voiceMaxSeconds;
  final ValueChanged<String> onSend;
  final VoidCallback onAttach;
  final void Function(String path, int seconds) onVoice;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _focus = FocusNode();
  late final _hasText = ValueNotifier(widget.controller.text.trim().isNotEmpty);
  late final _voice = VoiceRecording(
    maxSeconds: widget.voiceMaxSeconds,
    onDone: (path, seconds) => widget.onVoice(path, seconds),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  void _onText() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText.value) _hasText.value = has;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    _focus.dispose();
    _hasText.dispose();
    _voice.dispose();
    super.dispose();
  }

  void _send() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    widget.controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.bar,
        border: Border(top: BorderSide(color: p.barBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(10.ms, 6.ms, 10.ms, 8.ms),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<DateTime?>(
                valueListenable: _voice.since,
                builder: (context, since, field) => Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (since == null) ...[
                      _RoundButton(
                        icon: LucideIcons.imagePlus,
                        label: 'chat:composer.attach',
                        onTap: widget.onAttach,
                        filled: false,
                      ),
                      SizedBox(width: 6.ms),
                      Expanded(child: field!),
                    ] else
                      Expanded(child: _RecordingStrip(voice: _voice)),
                    SizedBox(width: 6.ms),
                    _SendOrMic(hasText: _hasText, voice: _voice, onSend: _send),
                  ],
                ),
                child: _Field(
                  controller: widget.controller,
                  focus: _focus,
                  maxLength: widget.maxLength,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focus,
    required this.maxLength,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final style = TextStyle(
      fontSize: 15.ms,
      height: 1.3,
      fontWeight: FontWeight.w500,
      color: p.text,
    );
    return Container(
      constraints: BoxConstraints(minHeight: 44.ms),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(22.ms),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Large text up to where the bar still fits (as message text).
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: ChatPalette.maxTextScale,
            child: TextField(
              key: const ValueKey('chat-composer-field'),
              controller: controller,
              focusNode: focus,
              minLines: 1,
              maxLines: 5,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              maxLength: maxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              cursorColor: p.accent,
              style: style,
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: context.t('chat:composer.hint'),
                hintStyle: style.copyWith(color: p.muted),
                contentPadding: EdgeInsetsDirectional.fromSTEB(
                  16.ms,
                  12.ms,
                  14.ms,
                  12.ms,
                ),
              ),
            ),
          ),
          // The counter only near the limit; only it rebuilds while typing.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) {
              final n = value.text.characters.length;
              if (n < maxLength - 50) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsetsDirectional.only(end: 14.ms, bottom: 6.ms),
                child: CText.raw(
                  '$n/$maxLength',
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: n >= maxLength ? p.failed : p.muted,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Send while there is text; otherwise the mic (hold to record).
class _SendOrMic extends StatelessWidget {
  const _SendOrMic({
    required this.hasText,
    required this.voice,
    required this.onSend,
  });

  final ValueListenable<bool> hasText;
  final VoiceRecording voice;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ValueListenableBuilder<bool>(
      valueListenable: hasText,
      builder: (context, has, _) {
        if (has) {
          return _RoundButton(
            key: const ValueKey('chat-send'),
            icon: LucideIcons.send,
            label: 'chat:composer.send',
            onTap: onSend,
          );
        }
        return Semantics(
          button: true,
          label: context.t('chat:composer.mic'),
          child: GestureDetector(
            key: const ValueKey('chat-mic'),
            onTap: () => CToast.show('chat:composer.hold_hint'),
            onLongPressStart: (_) => voice.press(),
            onLongPressMoveUpdate: (d) => voice.moved(
              rtl ? d.offsetFromOrigin.dx : -d.offsetFromOrigin.dx,
            ),
            onLongPressEnd: (_) => voice.release(),
            onLongPressCancel: voice.cancel,
            child: ValueListenableBuilder<DateTime?>(
              valueListenable: voice.since,
              builder: (_, since, _) => _RoundButton(
                icon: LucideIcons.mic,
                label: 'chat:composer.mic',
                big: since != null,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// While recording: a red dot, the time, "‹ Slide to cancel".
class _RecordingStrip extends StatelessWidget {
  const _RecordingStrip({required this.voice});

  final VoiceRecording voice;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    return Container(
      height: 44.ms,
      padding: EdgeInsetsDirectional.symmetric(horizontal: 14.ms),
      decoration: BoxDecoration(
        color: p.field,
        borderRadius: BorderRadius.circular(22.ms),
      ),
      child: Row(
        children: [
          Icon(
            Icons.fiber_manual_record_rounded,
            size: 12.ms,
            color: StatusColors.dangerRed,
          ),
          SizedBox(width: 6.ms),
          ValueListenableBuilder<int>(
            valueListenable: voice.elapsed,
            builder: (_, s, _) => CText.raw(
              ChatFormat.clock(s),
              size: 14,
              weight: FontWeight.w700,
              color: p.text,
            ),
          ),
          const Spacer(),
          ValueListenableBuilder<double>(
            valueListenable: voice.drag,
            builder: (_, dx, child) => Opacity(
              opacity: (1 - dx / VoiceRecording.cancelAt).clamp(0.2, 1.0),
              child: child,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? LucideIcons.chevronRight
                      : LucideIcons.chevronLeft,
                  size: 16.ms,
                  color: p.muted,
                ),
                CText(
                  'chat:composer.slide_cancel',
                  size: 12.5,
                  weight: FontWeight.w600,
                  color: p.muted,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.filled = true,
    this.big = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final size = (big ? 54 : 44).ms;
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: big ? StatusColors.dangerRed : (filled ? p.accent : p.field),
      ),
      child: Icon(
        icon,
        size: 20.ms,
        color: big ? AppColors.white : (filled ? p.onAccent : p.text),
      ),
    );
    if (onTap == null) return ExcludeSemantics(child: circle);
    return Pressable(
      onPressed: onTap,
      semanticLabel: context.t(label),
      child: circle,
    );
  }
}
