import 'package:flutter/material.dart';

import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../helper/host_palette.dart';

/// Something the flow shows at the top of a step's page, scrolling with it:
/// the admin's clips (docs/host_onboarding.md). [HostStepBody] reads it.
class HostStepHeader extends InheritedWidget {
  const HostStepHeader({super.key, required this.header, required super.child});

  final Widget header;

  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HostStepHeader>()?.header;

  @override
  bool updateShouldNotify(HostStepHeader old) => header != old.header;
}

/// A form step's scrolling page: title, subtitle, then [children]. Dragging
/// dismisses the keyboard. A [HostStepHeader] above it goes first, and
/// scrolls away with the page.
class HostStepBody extends StatelessWidget {
  const HostStepBody({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.titleVariables,
  });

  /// i18n keys.
  final String title;
  final String? subtitle;
  final Map<String, dynamic>? titleVariables;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final header = HostStepHeader.of(context);
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(20.ms, 6.ms, 20.ms, 24.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null) ...[header, SizedBox(height: 14.ms)],
          HostTitle(title, variables: titleVariables),
          if (subtitle != null) ...[
            SizedBox(height: 8.ms),
            CText(
              subtitle!,
              size: 15.5,
              height: 22.5,
              weight: FontWeight.w500,
              color: p.muted,
            ),
          ],
          SizedBox(height: 18.ms),
          ...children,
        ],
      ),
    );
  }
}

class HostTitle extends StatelessWidget {
  const HostTitle(this.text, {super.key, this.variables, this.align});
  final String text;
  final Map<String, dynamic>? variables;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => CText(
    text,
    variables: variables,
    size: 25,
    height: 31,
    weight: FontWeight.w800,
    letterSpacing: -0.4,
    align: align,
    color: HostPalette.of(context).text,
  );
}

/// Field label above a control ("Full name", "Gender"…).
class HostLabel extends StatelessWidget {
  const HostLabel(this.text, {super.key, this.top = 14});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top.ms, bottom: 7.ms),
    child: CText(
      text,
      size: 15.5,
      weight: FontWeight.w600,
      color: HostPalette.of(context).text,
    ),
  );
}

/// Soft card used for tips, notes and suggestions.
class HostCard extends StatelessWidget {
  const HostCard({
    super.key,
    required this.child,
    this.color,
    this.borderColor,
    this.padding,
  });

  final Widget child;
  final Color? color;
  final Color? borderColor;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return Container(
      padding: padding ?? EdgeInsets.all(16.ms),
      decoration: BoxDecoration(
        color: color ?? p.card,
        borderRadius: BorderRadius.circular(16.ms),
        border: Border.all(color: borderColor ?? p.cardBorder),
      ),
      child: child,
    );
  }
}
