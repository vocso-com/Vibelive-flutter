import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/listing_models.dart';
import '../../chatscreen/entry/chat_entry.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import '../../component/skeleton.dart';
import '../../component/verification_badge.dart';
import '../helper/busy_label.dart';

/// Discover grid card (RN `DiscoveryCard`): photo, price / rating badges,
/// name + badge, tagline or city, topic chips. Featured cards are taller and
/// span the row.
class HostGridCard extends StatelessWidget {
  const HostGridCard({
    super.key,
    required this.host,
    required this.onTap,
    this.featured = false,
    this.onCall,
  });

  final HostCard host;
  final bool featured;
  final ValueChanged<HostCard> onTap;

  /// "Call Now" under the card's text (Discover); none, no button.
  final ValueChanged<HostCard>? onCall;

  /// As stored, like RN (`12`, `12.5`, `12.75`).
  static String _price(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = host;
    final price = h.aPrice > 0 ? h.aPrice : (h.vPrice > 0 ? h.vPrice : null);
    final image = h.cardImage ?? (h.images.isEmpty ? null : h.images.first);
    final topics = h.topics.take(featured ? 2 : 1);
    final radius = BorderRadius.circular(featured ? 36.ms : 30.ms);
    final badgeBg = c.isDark ? AppColors.blackA(0.45) : AppColors.blackA(0.36);
    // On a call, the wait matters more than the rate (RN).
    final busy = BusyLabel.of(h.presence);

    return Pressable(
      activeOpacity: 0.92,
      onPressed: () => onTap(h),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: c.isDark ? AppColors.whiteA(0.08) : AppColors.blackA(0.12),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (_, box) => image == null
                  ? _Letter(h.name)
                  : CImage(
                      url: image,
                      placeholderUrl: h.cardPlaceholder,
                      // Wide (featured) crops cut portraits: keep the face.
                      alignment: Alignment.topCenter,
                      width: box.maxWidth,
                      height: box.maxHeight,
                    ),
            ),
            const Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: 1,
                  heightFactor: 0.68,
                  child: _Shade(),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(onCall == null ? 16.ms : 12.ms),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopRow(
                    price: price == null
                        ? null
                        : _Badge(
                            bg: badgeBg,
                            padding: 10,
                            gap: 6,
                            leading: Container(
                              width: 6.ms,
                              height: 6.ms,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: busy != null
                                    ? AppColors.orange
                                    : h.isAvailable
                                    ? BrandColors.lime
                                    : AppColors.whiteA(0.35),
                              ),
                            ),
                            text: busy != null
                                ? context.t(busy.key, variables: busy.variables)
                                : context.t(
                                    'home:card.price',
                                    variables: {'price': _price(price)},
                                  ),
                          ),
                    rating: h.rating > 0
                        ? _Badge(
                            bg: badgeBg,
                            padding: 8,
                            gap: 4,
                            leading: Icon(
                              Icons.star_rounded,
                              size: 9.ms,
                              color: BrandColors.lime,
                            ),
                            text: h.ratingLabel,
                          )
                        : null,
                  ),
                  const Spacer(),
                  _Name(
                    host: h,
                    featured: featured,
                    lines: onCall == null ? 2 : 1,
                  ),
                  if (h.tagline.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 3.ms),
                      child: CText.raw(
                        h.tagline,
                        size: 11.5,
                        height: 15,
                        weight: FontWeight.w600,
                        color: AppColors.whiteA(0.92),
                        maxLines: onCall == null ? 3 : 2,
                      ),
                    )
                  else
                    _CityLine(host: h),
                  if (topics.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 7.ms),
                      child: Row(
                        children: [
                          for (final t in topics)
                            Flexible(
                              child: Container(
                                margin: EdgeInsets.only(right: 5.ms),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8.ms,
                                  vertical: 3.ms,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.whiteA(0.25),
                                  borderRadius: BorderRadius.circular(6.ms),
                                ),
                                child: CText.raw(
                                  t,
                                  size: 9,
                                  letterSpacing: 0.3,
                                  weight: FontWeight.w900,
                                  color: AppColors.white,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (onCall != null)
                    Padding(
                      padding: EdgeInsets.only(top: 8.ms),
                      // Message (¼) + Call Now (¾) while chat is on.
                      child: ChatCallSplit(
                        host: h,
                        call: _CallNow(onPressed: () => onCall!(h)),
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

/// White "Call Now" bar at the bottom of a Discover card.
class _CallNow extends StatelessWidget {
  const _CallNow({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // The light theme's accent on white; the dark theme's lime would vanish.
    final fg = c.isDark ? BrandColors.purple : c.accent;
    return Pressable(
      activeOpacity: 0.85,
      semanticLabel: context.t('home:card.call_now'),
      onPressed: onPressed,
      child: Container(
        height: 32.ms,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: AppColors.blackA(0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.phoneCall, size: 13.ms, color: fg),
            SizedBox(width: 6.ms),
            // Beside the message button it has ¾ of a half card: a long
            // label shortens instead of overflowing.
            Flexible(
              child: CText(
                'home:card.call_now',
                size: 12,
                weight: FontWeight.w900,
                color: fg,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Name extends StatelessWidget {
  const _Name({required this.host, required this.featured, this.lines = 2});
  final HostCard host;
  final bool featured;

  /// One line on a card with Call Now: the button needs the room.
  final int lines;

  @override
  Widget build(BuildContext context) {
    final size = featured ? 21.0 : 15.0;
    return Text.rich(
      TextSpan(
        text:
            (host.name.isEmpty ? context.t(HostCard.unknownNameKey) : host.name)
                .toUpperCase(),
        children: [
          const TextSpan(text: ' '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: VerificationBadge(
              user: host.badgeFlags,
              size: featured ? 19.ms : 15.ms,
            ),
          ),
        ],
      ),
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        color: AppColors.white,
        fontSize: size.ms,
        fontWeight: FontWeight.w900,
        fontStyle: FontStyle.italic,
        letterSpacing: 0.4,
        height: 1.15,
        shadows: [
          Shadow(
            color: AppColors.blackA(0.4),
            offset: Offset(0, 1.ms),
            blurRadius: 2,
          ),
        ],
      ),
    );
  }
}

/// "DELHI  •  4.5 STAR" (RN), or "INDIA" when the host has no district.
class _CityLine extends StatelessWidget {
  const _CityLine({required this.host});
  final HostCard host;

  @override
  Widget build(BuildContext context) {
    final city = host.city.isEmpty
        ? context.t(HostCard.defaultCityKey)
        : host.city;
    return CText.raw(
      host.rating > 0
          ? context.t(
              'home:card.city_rating',
              variables: {'city': city, 'rating': host.ratingLabel},
            )
          : city,
      variant: CTextVariant.caption,
      size: 10,
      weight: FontWeight.w700,
      letterSpacing: 1.4,
      color: AppColors.whiteA(0.72),
      maxLines: 1,
    );
  }
}

/// Badges + arrow (RN: badges keep their size, the arrow gives way). On a
/// narrow card whatever doesn't fit whole is left out, in this order:
/// arrow, then rating; never squeezed, never overflowing.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.price, required this.rating});
  final Widget? price;
  final Widget? rating;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 30.ms,
    child: ClipRect(
      child: CustomMultiChildLayout(
        delegate: _TopRowLayout(gap: 6.ms),
        children: [
          if (price != null) LayoutId(id: _Slot.price, child: price!),
          if (rating != null) LayoutId(id: _Slot.rating, child: rating!),
          LayoutId(
            id: _Slot.arrow,
            child: Icon(
              LucideIcons.arrowUpRight,
              size: 22.ms,
              color: AppColors.white,
            ),
          ),
        ],
      ),
    ),
  );
}

enum _Slot { price, rating, arrow }

class _TopRowLayout extends MultiChildLayoutDelegate {
  _TopRowLayout({required this.gap});
  final double gap;

  @override
  void performLayout(Size size) {
    final natural = BoxConstraints(maxHeight: size.height);
    final hidden = Offset(size.width * 2, 0); // clipped away
    var x = 0.0;
    void place(_Slot slot, {bool right = false}) {
      if (!hasChild(slot)) return;
      // The price pill may carry a busy label: capped, it ellipsizes.
      final child = layoutChild(
        slot,
        slot == _Slot.price ? natural.copyWith(maxWidth: size.width) : natural,
      );
      final start = x == 0 ? 0.0 : x + gap;
      final fits = start + child.width <= size.width;
      final y = (size.height - child.height) / 2;
      if (!fits) return positionChild(slot, hidden);
      positionChild(slot, Offset(right ? size.width - child.width : start, y));
      x = start + child.width;
    }

    place(_Slot.price);
    place(_Slot.rating);
    place(_Slot.arrow, right: true);
  }

  @override
  bool shouldRelayout(_TopRowLayout old) => old.gap != gap;
}

/// Price / rating pill (RN paddings: 10 / 8, gaps 6 / 4).
class _Badge extends StatelessWidget {
  const _Badge({
    required this.bg,
    required this.leading,
    required this.text,
    required this.padding,
    required this.gap,
  });
  final Color bg;
  final Widget leading;
  final String text;
  final double padding;
  final double gap;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: padding.ms, vertical: 6.ms),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(12.ms),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        leading,
        SizedBox(width: gap.ms),
        Flexible(
          child: CText.raw(
            text,
            size: 10,
            weight: FontWeight.w700,
            color: AppColors.white,
            maxLines: 1,
          ),
        ),
      ],
    ),
  );
}

/// Bottom 68 % fade to black so the text stays readable on any photo.
class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0xBF000000)],
      ),
    ),
  );
}

/// No photo: the first letter on a per-letter color.
class _Letter extends StatelessWidget {
  const _Letter(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: CAvatar.colorFor(name),
    child: Center(
      child: CText.raw(
        CAvatar.letterFor(name),
        size: 72,
        weight: FontWeight.w900,
        color: AppColors.white,
      ),
    ),
  );
}

/// Skeleton of a feed card (same size and radius). Put under a `Shimmer`.
class HostGridCardSkeleton extends StatelessWidget {
  const HostGridCardSkeleton({super.key, this.featured = false});
  final bool featured;

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(radius: featured ? 36.ms : 30.ms);
}
