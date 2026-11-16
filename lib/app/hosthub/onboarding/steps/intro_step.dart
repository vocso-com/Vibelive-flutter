import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_text.dart';
import '../../../component/status_bar_style.dart';
import '../helper/host_palette.dart';
import '../helper/intro_image.dart';
import '../widgets/continue_bar.dart';

/// 1 of 11: full-bleed photo under the design's purple gradient, the three
/// benefits and "Get started". Always dark (text sits on the photo) in both
/// themes. The user is signed in, so the design's "Log in" line is dropped;
/// the back gesture leaves.
class IntroStep extends StatelessWidget {
  const IntroStep({
    super.key,
    required this.resuming,
    required this.onStart,
    this.media,
  });

  /// A saved draft exists: "Continue setup" instead of "Get started".
  final bool resuming;
  final VoidCallback onStart;

  /// The admin's clips for this screen (docs/host_onboarding.md), under the
  /// brand line. Null: the screen as designed.
  final Widget? media;

  /// The design's bottom: deep violet.
  static const deep = Color(0xFF120A2E);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ThemedStatusBar(
      darkBackground: true,
      child: ColoredBox(
        color: deep,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: size.height * HostIntroImage.heightFactor,
              child: Image(
                image: HostIntroImage.provider(context),
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.35),
                gaplessPlayback: true,
                excludeFromSemantics: true,
                // Precached before the intro opens; never fades in.
                frameBuilder: (_, child, frame, sync) =>
                    frame == null && !sync ? const SizedBox.shrink() : child,
              ),
            ),
            // Purple wash over the photo, then the fade into the dark base.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.22, 0.45, 0.62, 0.78],
                  colors: [
                    Color(0xB3160A33),
                    Color(0x553A1A8C),
                    Color(0x664A23B0),
                    Color(0xE62A1466),
                    deep,
                  ],
                ),
              ),
            ),
            SafeArea(
              minimum: EdgeInsets.only(bottom: 20.ms),
              // Fills the screen; scrolls only when a short phone with long
              // copy cannot fit it.
              child: CustomScrollView(
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 22.ms),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 14.ms),
                          const CText(
                            'hostflow:intro.brand',
                            size: 30,
                            weight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: AppColors.white,
                          ),
                          if (media case final media?) ...[
                            SizedBox(height: 14.ms),
                            media,
                          ],
                          const Spacer(),
                          const CText(
                            'hostflow:intro.title',
                            size: 36,
                            height: 42,
                            weight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: AppColors.white,
                          ),
                          SizedBox(height: 6.ms),
                          CText(
                            'hostflow:intro.subtitle',
                            size: 19,
                            height: 25,
                            weight: FontWeight.w400,
                            color: AppColors.whiteA(0.92),
                          ),
                          SizedBox(height: 18.ms),
                          for (final (icon, key) in const [
                            (LucideIcons.messageSquareText, 'b1'),
                            (LucideIcons.calendarDays, 'b2'),
                            (LucideIcons.indianRupee, 'b3'),
                          ])
                            _Benefit(
                              icon: icon,
                              keyPrefix: 'hostflow:intro.$key',
                            ),
                          SizedBox(height: 16.ms),
                          HostButton(
                            key: const ValueKey('hostflow-start'),
                            label: resuming
                                ? 'hostflow:intro.resume'
                                : 'hostflow:intro.cta',
                            colors: HostPalette.light.gradient,
                            foreground: AppColors.white,
                            onPressed: onStart,
                          ),
                        ],
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

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.keyPrefix});
  final IconData icon;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 12.ms),
    child: Row(
      children: [
        Container(
          width: 54.ms,
          height: 54.ms,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [BrandColors.purpleLight, BrandColors.purple],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(icon, size: 24.ms, color: AppColors.white),
        ),
        SizedBox(width: 14.ms),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CText(
                '${keyPrefix}_title',
                size: 16.5,
                weight: FontWeight.w600,
                color: AppColors.white,
              ),
              SizedBox(height: 2.ms),
              CText(
                '${keyPrefix}_body',
                size: 13.5,
                weight: FontWeight.w400,
                color: AppColors.whiteA(0.72),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
