import 'package:flutter/widgets.dart';

import '../../../core/utils/scale.dart';
import '../../component/c_text.dart';
import '../helper/chat_format.dart';
import 'chat_palette.dart';

/// "Today", "Yesterday", "Monday", "Nov 3": a small pill between days.
class ChatDateSeparator extends StatelessWidget {
  const ChatDateSeparator({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final label = ChatFormat.of(
      Localizations.localeOf(context).toLanguageTag(),
    ).day(day);
    final style = (size: 11.5, weight: FontWeight.w700, color: p.onChip);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.ms),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.ms, vertical: 4.ms),
          decoration: BoxDecoration(
            color: p.chip,
            borderRadius: BorderRadius.circular(999),
          ),
          child: label.key != null
              ? CText(
                  label.key!,
                  size: style.size,
                  weight: style.weight,
                  color: style.color,
                  maxLines: 1,
                )
              : CText.raw(
                  label.text ?? '',
                  size: style.size,
                  weight: style.weight,
                  color: style.color,
                  maxLines: 1,
                ),
        ),
      ),
    );
  }
}
