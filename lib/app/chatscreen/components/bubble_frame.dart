import 'package:flutter/widgets.dart';

import '../../../core/utils/scale.dart';
import 'chat_palette.dart';

/// The rounded frame of a text or voice bubble; the corner on the sender's
/// side is pointed on the last of a group ([tail]).
class BubbleFrame extends StatelessWidget {
  const BubbleFrame({
    super.key,
    required this.mine,
    required this.tail,
    required this.child,
    this.padding,
  });

  final bool mine;
  final bool tail;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final p = ChatPalette.of(context);
    final r = Radius.circular(ChatPalette.radius);
    final t = Radius.circular(tail ? ChatPalette.tail : ChatPalette.radius);
    return Container(
      padding:
          padding ?? EdgeInsetsDirectional.fromSTEB(12.ms, 8.ms, 10.ms, 6.ms),
      decoration: BoxDecoration(
        color: mine ? p.mine : p.theirs,
        border: mine ? null : Border.all(color: p.theirsBorder),
        borderRadius: BorderRadiusDirectional.only(
          topStart: r,
          topEnd: r,
          bottomStart: mine ? r : t,
          bottomEnd: mine ? t : r,
        ),
      ),
      child: child,
    );
  }
}
