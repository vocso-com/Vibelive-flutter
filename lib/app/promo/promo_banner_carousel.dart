import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../core/analytics/events/promo_events.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import '../api/promo_banner/promo_banner_models.dart';
import '../api/promo_banner/promo_banner_queries.dart';
import 'promo_banner_actions.dart';
import 'promo_banner_card.dart';
import 'templates/promo_parts.dart';

/// The admin's promo banners for one screen ([placement]): one banner, or a
/// carousel that glides to the next every `rotateSeconds` (held while a
/// finger is on it), with dots. Nothing at all while banners are off or none
/// are live for this user.
///
/// Motion: the cards keep their rounded corners all the way across (nothing
/// is cut at the carousel's edge); a card shrinks a little and fades as it
/// leaves, and its picture drifts slower than the card (parallax). The first
/// banner rises in instead of popping, and the space opens smoothly.
class PromoBannerCarousel extends HookWidget {
  const PromoBannerCarousel({
    super.key,
    required this.placement,
    this.padding = EdgeInsets.zero,
  });

  final PromoPlacement placement;
  final EdgeInsets padding;

  static const _slide = Duration(milliseconds: 700);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final feed =
        usePromoBanners(context, placement).data ?? PromoBannerFeed.empty;
    final dismissed = useValueListenable(PromoDismissed.ids);
    // Countdowns that reached zero while on screen.
    final ended = useState(<String>{});
    final banners = [
      for (final b in feed.banners)
        if (!dismissed.contains(b.id) && !ended.value.contains(b.id)) b,
    ];
    final pages = usePageController();
    final page = useState(0);
    // Seconds since the last slide or swipe (ticks of the timer below).
    final idle = useRef(0);
    final touching = useRef(false);
    final count = banners.length;
    final ids = banners.map((b) => b.id).join(',');
    final still = MediaQuery.disableAnimationsOf(context);

    // Auto-slide. A swipe counts as a move, so the next slide waits a full
    // turn; a finger on the carousel holds it.
    useEffect(() {
      final seconds = feed.rotateSeconds;
      if (count < 2 || seconds <= 0) return null;
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!pages.hasClients || touching.value) return;
        idle.value += 1;
        if (idle.value < seconds) return;
        idle.value = 0;
        final next = ((pages.page?.round() ?? 0) + 1) % count;
        if (still) {
          pages.jumpToPage(next);
        } else {
          pages.animateToPage(
            next,
            duration: _slide,
            curve: Curves.easeInOutCubic,
          );
        }
      });
      return timer.cancel;
    }, [ids, feed.rotateSeconds, still]);

    // The list changed under the current page (one closed, or an update).
    useEffect(() {
      if (page.value >= count && count > 0) {
        page.value = count - 1;
        if (pages.hasClients) pages.jumpToPage(count - 1);
      }
      return null;
    }, [ids]);

    final current = count == 0 ? 0 : page.value.clamp(0, count - 1);
    final shown = count == 0 ? null : banners[current];
    useEffect(() {
      if (shown != null) {
        PromoEvents.bannerViewed(
          id: shown.id,
          placement: placement.name,
          position: current,
          template: shown.content.template,
        );
      }
      return null;
    }, [shown?.id]);

    final Widget body;
    if (count == 0) {
      body = const SizedBox(width: double.infinity);
    } else {
      body = Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth;
            final height = banners
                .map((b) => PromoBannerCard.heightFor(b, width))
                .reduce(math.max);
            Widget card(PromoBanner b) => Align(
              alignment: Alignment.topCenter,
              child: PromoBannerCard(
                key: ValueKey('promo-${b.id}'),
                banner: b,
                width: width,
                onTap: () {
                  PromoEvents.bannerTapped(
                    id: b.id,
                    placement: placement.name,
                    action: b.action.type,
                    template: b.content.template,
                  );
                  PromoBannerActions.open(context, b);
                },
                onDismiss: () {
                  PromoEvents.bannerDismissed(
                    id: b.id,
                    placement: placement.name,
                  );
                  PromoDismissed.add(b.id);
                },
                onCopied: () => PromoEvents.codeCopied(
                  id: b.id,
                  where: placement.name,
                  template: b.content.template,
                ),
                onEnded: () => ended.value = {...ended.value, b.id},
              ),
            );
            if (count == 1) return card(banners.single);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Listener(
                  onPointerDown: (_) => touching.value = true,
                  onPointerUp: (_) {
                    touching.value = false;
                    idle.value = 0;
                  },
                  onPointerCancel: (_) => touching.value = false,
                  child: SizedBox(
                    height: height,
                    child: PageView.builder(
                      controller: pages,
                      itemCount: count,
                      // Cards slide past the edge whole, never cut.
                      clipBehavior: Clip.none,
                      onPageChanged: (i) {
                        page.value = i;
                        idle.value = 0;
                      },
                      itemBuilder: (_, i) => _Slide(
                        pages: pages,
                        index: i,
                        current: current,
                        child: card(banners[i]),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8.ms),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < count; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        margin: EdgeInsets.symmetric(horizontal: 3.ms),
                        width: (i == current ? 16 : 6).ms,
                        height: 6.ms,
                        decoration: BoxDecoration(
                          color: i == current ? c.accent : c.border,
                          borderRadius: BorderRadius.circular(3.ms),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    }

    // The space opens smoothly and the first banner rises in.
    return AnimatedSize(
      duration: still ? Duration.zero : const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: count == 0 ? body : _Reveal(still: still, child: body),
    );
  }
}

/// One page of the carousel: by its distance from the centre it shrinks to
/// 0.94, fades to 0.6, and tells its picture how far to drift.
class _Slide extends StatelessWidget {
  const _Slide({
    required this.pages,
    required this.index,
    required this.current,
    required this.child,
  });

  final PageController pages;
  final int index;
  final int current;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: pages,
    child: child,
    builder: (_, child) {
      final at =
          pages.hasClients && pages.position.haveDimensions
          ? pages.page ?? current.toDouble()
          : current.toDouble();
      final d = (index - at).clamp(-1.0, 1.0);
      final away = Curves.easeOut.transform(d.abs());
      if (away == 0) return PromoParallax(offset: 0, child: child!);
      return Transform.scale(
        scale: 1 - 0.06 * away,
        child: Opacity(
          opacity: 1 - 0.4 * away,
          child: PromoParallax(offset: d, child: child!),
        ),
      );
    },
  );
}

/// Fades [child] in while it rises 12 dp, once, when it first appears.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.still, required this.child});
  final bool still;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.still ? 1 : 0,
  )..forward();
  late final Animation<double> _curve = CurvedAnimation(
    parent: _in,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (_, child) => _curve.value >= 1
        ? child!
        : Opacity(
            opacity: _curve.value,
            child: Transform.translate(
              offset: Offset(0, 12.ms * (1 - _curve.value)),
              child: child,
            ),
          ),
  );
}
