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

/// The admin's promo banners for one screen ([placement]): one banner, or a
/// carousel that slides to the next every `rotateSeconds` (paused for a
/// moment after a swipe), with dots. Nothing at all while banners are off or
/// none are live for this user.
class PromoBannerCarousel extends HookWidget {
  const PromoBannerCarousel({
    super.key,
    required this.placement,
    this.padding = EdgeInsets.zero,
  });

  final PromoPlacement placement;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final feed =
        usePromoBanners(context, placement).data ?? PromoBannerFeed.empty;
    final dismissed = useValueListenable(PromoDismissed.ids);
    final banners = [
      for (final b in feed.banners)
        if (!dismissed.contains(b.id)) b,
    ];
    final pages = usePageController();
    final page = useState(0);
    // Seconds since the last slide or swipe (ticks of the timer below).
    final idle = useRef(0);
    final count = banners.length;
    final ids = banners.map((b) => b.id).join(',');

    // Auto-slide. A swipe counts as a move, so the next slide waits a full turn.
    useEffect(() {
      final seconds = feed.rotateSeconds;
      if (count < 2 || seconds <= 0) return null;
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!pages.hasClients) return;
        idle.value += 1;
        if (idle.value < seconds) return;
        idle.value = 0;
        final next = ((pages.page?.round() ?? 0) + 1) % count;
        pages.animateToPage(
          next,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeInOut,
        );
      });
      return timer.cancel;
    }, [ids, feed.rotateSeconds]);

    // The list changed under the current page (one closed, or an update).
    useEffect(() {
      if (page.value >= count && count > 0) {
        page.value = count - 1;
        if (pages.hasClients) pages.jumpToPage(count - 1);
      }
      return null;
    }, [ids]);

    final current = count == 0 ? 0 : page.value.clamp(0, count - 1);
    final shownId = count == 0 ? null : banners[current].id;
    useEffect(() {
      if (shownId != null) {
        PromoEvents.bannerViewed(
          id: shownId,
          placement: placement.name,
          position: current,
        );
      }
      return null;
    }, [shownId]);

    if (count == 0) return const SizedBox.shrink();

    return Padding(
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
            ),
          );
          if (count == 1) return card(banners.single);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: height,
                child: PageView.builder(
                  controller: pages,
                  itemCount: count,
                  onPageChanged: (i) {
                    page.value = i;
                    idle.value = 0;
                  },
                  itemBuilder: (_, i) => card(banners[i]),
                ),
              ),
              SizedBox(height: 8.ms),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < count; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
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
}
