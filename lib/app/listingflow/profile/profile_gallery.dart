import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/analytics/events/discover_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/client/client_models.dart';
import '../../api/client/client_queries.dart';
import '../../api/listingflow/listing_models.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import '../../component/c_toast.dart';
import '../../component/image_preview_modal.dart';
import '../../component/pressable.dart';
import '../../component/qr_code_sheet.dart';
import 'gallery_video.dart';
import 'helper/host_profile_controller.dart';
import 'helper/host_profile_rules.dart';

/// Photo carousel at the top (RN): the left / right quarter shows the
/// previous / next slide, the middle opens the photo preview (copy link,
/// favourite). Progress bars when there are several slides; the profile
/// card's rounded top overlaps the bottom edge.
///
/// A host with an approved video intro gets it as the FIRST slide: it plays
/// by itself on a loop with only a sound button ([GalleryVideo]), and pauses
/// while a photo is on screen.
class ProfileGallery extends HookWidget {
  const ProfileGallery({
    super.key,
    required this.host,
    required this.height,
    required this.topInset,
    required this.controller,
    required this.canFavorite,
  });

  final HostCard host;
  final double height;

  /// Status bar height (the sheet itself has no top padding).
  final double topInset;
  final HostProfileController controller;

  /// Signed in and not the viewer's own profile.
  final bool canFavorite;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final images = host.images;
    final thumbs = host.imageThumbs;
    // Only ever an approved clip: the server withholds anything else and
    // the listing model checks the status again.
    final video = host.videoIntro;
    final hasVideo = video != null;
    final count = images.length + (hasVideo ? 1 : 0) < 1
        ? 1
        : images.length + (hasVideo ? 1 : 0);

    /// The photo at carousel position [index]; -1 for the video slide.
    int photoAt(int index) => index % count - (hasVideo ? 1 : 0);
    // Every photo's card-sized rendition (the first is already cached from
    // Discover), so a tap to the next photo shows at once.
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        for (final t in thumbs.skip(1)) {
          precacheImage(CachedNetworkImageProvider(t), context).ignore();
        }
      });
      return null;
    }, [host.id]);
    final expertId = host.expertProfileDocumentId;
    final favoritable = canFavorite && expertId != null;
    final favorites = useFavorites(context, enabled: favoritable);
    final add = useAddFavorite();
    final remove = useRemoveFavorite();
    final name = host.name.isEmpty
        ? context.t(HostCard.unknownNameKey)
        : host.name;

    final hostId = HostProfileRules.expertKey(host);
    void openPreview() {
      final at = photoAt(controller.activeImage.value);
      // The video slide has no preview: only its sound button.
      if (at < 0) return;
      final image = images.isEmpty ? null : images[at];
      DiscoverEvents.photoPreviewOpened(
        hostId: hostId,
        index: at,
        count: images.length,
      );
      // The row to delete when un-favouriting; follows the toggles made
      // inside the preview.
      FavoriteExpert? row = favorites.data
          ?.where((f) => f.expertId == expertId)
          .firstOrNull;
      Future<void> toggle() async {
        final adding = row == null;
        try {
          final current = row;
          if (current != null) {
            row = null;
            await remove.mutateAsync(current);
          } else {
            row = await add.mutateAsync(expertId!);
          }
          DiscoverEvents.favouriteToggled(
            hostId: expertId ?? hostId,
            added: adding,
            source: 'photo_preview',
          );
        } on ApiException catch (e) {
          DiscoverEvents.favouriteFailed(
            hostId: expertId ?? hostId,
            adding: adding,
            error: Analytics.errorCode(e),
          );
          CToast.error(e);
        }
      }

      ImagePreviewModal.show(
        context,
        imageUrl: image,
        title: name,
        handle: host.handler,
        isFavorite: row != null,
        onToggleFavorite: favoritable ? () => unawaited(toggle()) : null,
        onShare: () => controller.share(context, host),
        onCopyLink: () => controller.copyLink(host),
        onShowQR: () {
          DiscoverEvents.profileShared(hostId: hostId, method: 'qr');
          showQrCodeSheet(
            context,
            url: HostProfileRules.shareUrl(host),
            name: name,
            handle: host.handler,
          );
        },
      );
    }

    final lip = 36.ms;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (_, box) => ValueListenableBuilder<int>(
              valueListenable: controller.activeImage,
              builder: (_, index, _) {
                Widget photo(int at) => images.isEmpty
                    ? _Letter(name)
                    : CImage(
                        url: images[at],
                        placeholderUrl: at < thumbs.length ? thumbs[at] : null,
                        width: box.maxWidth,
                        height: box.maxHeight,
                        // Portraits keep the head, as on the cards.
                        alignment: Alignment.topCenter,
                      );
                final at = photoAt(index);
                final onVideo = at < 0;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Kept alive under the photos so coming back to it does
                    // not reload; paused while hidden.
                    if (hasVideo)
                      Offstage(
                        offstage: !onVideo,
                        child: GalleryVideo(
                          key: const ValueKey('gallery-video'),
                          url: video,
                          hostId: hostId,
                          active: onVideo,
                          poster: photo(0),
                        ),
                      ),
                    if (!onVideo) photo(at),
                  ],
                );
              },
            ),
          ),
          ColoredBox(color: AppColors.blackA(0.2)),
          Row(
            children: [
              if (count > 1)
                Expanded(child: _Zone(() => controller.previousImage(count))),
              Expanded(flex: 2, child: _Zone(openPreview)),
              if (count > 1)
                Expanded(child: _Zone(() => controller.nextImage(count))),
            ],
          ),
          if (count > 1)
            Positioned(
              top: topInset + 4.ms,
              left: 20.ms,
              right: 20.ms,
              child: IgnorePointer(
                child: ValueListenableBuilder<int>(
                  valueListenable: controller.activeImage,
                  builder: (_, index, _) => Row(
                    children: [
                      for (var i = 0; i < count; i++) ...[
                        if (i > 0) SizedBox(width: 6.ms),
                        Expanded(
                          child: Container(
                            height: 4.ms,
                            decoration: BoxDecoration(
                              color: i == index % count
                                  ? AppColors.white
                                  : AppColors.whiteA(0.28),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          // The video slide's one control: sound on / off.
          if (hasVideo)
            Positioned(
              right: 16.ms,
              bottom: lip + 12.ms,
              child: ValueListenableBuilder<int>(
                valueListenable: controller.activeImage,
                builder: (_, index, _) => photoAt(index) < 0
                    ? GalleryMuteButton(hostId: hostId)
                    : const SizedBox.shrink(),
              ),
            ),
          // Rounded top of the profile card, with its drag bar.
          Positioned(
            left: 0,
            right: 0,
            bottom: -1,
            height: lip + 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: profileCardColor(c),
                borderRadius: BorderRadius.vertical(top: Radius.circular(lip)),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  width: 50.ms,
                  height: 5.ms,
                  margin: EdgeInsets.only(top: 14.ms),
                  decoration: BoxDecoration(
                    color: c.isDark
                        ? AppColors.whiteA(0.18)
                        : AppColors.blackA(0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Background of the profile card (RN: the dark screen color, white in
/// light mode).
Color profileCardColor(VibeColors c) => c.isDark ? c.bg : AppColors.white;

class _Zone extends StatelessWidget {
  const _Zone(this.onTap);
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap);
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

/// Back on the left; share and ⋮ on the right (no ⋮ on the viewer's own
/// profile: its actions are report and block). Floats over the photo and
/// stays put while the profile scrolls.
class ProfileTopBar extends StatelessWidget {
  const ProfileTopBar({
    super.key,
    required this.onBack,
    required this.onShare,
    this.onMenu,
  });

  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GlassButton(
          icon: LucideIcons.chevronLeft,
          size: 24,
          label: 'actions.back',
          onTap: onBack,
        ),
        const Spacer(),
        _GlassButton(
          icon: LucideIcons.share2,
          label: 'host:actions.share',
          onTap: onShare,
        ),
        if (onMenu != null) ...[
          SizedBox(width: 10.ms),
          _GlassButton(
            icon: LucideIcons.ellipsisVertical,
            label: 'host:actions.more',
            onTap: onMenu!,
          ),
        ],
      ],
    );
  }
}

/// RN's non-liquid-glass look: a dark scrim with a light border (no live
/// blur over scrolling content).
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 21,
  });

  final IconData icon;

  /// i18n key (screen readers).
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Pressable(
    onPressed: onTap,
    semanticLabel: context.t(label),
    child: Container(
      width: 44.ms,
      height: 44.ms,
      decoration: BoxDecoration(
        color: AppColors.blackA(0.42),
        borderRadius: BorderRadius.circular(18.ms),
        border: Border.all(color: AppColors.whiteA(0.25)),
      ),
      child: Icon(icon, size: size.ms, color: AppColors.white),
    ),
  );
}
