import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// The ring around a status circle: coloured while there is something not
/// yet watched, grey once it all was, none for an empty "Add status".
enum StatusRing { fresh, seen, none }

/// One circle on the home row (photo in a ring, a name under it), as
/// statuses look everywhere else people watch them.
class StatusCircle extends StatelessWidget {
  const StatusCircle({
    super.key,
    required this.ring,
    required this.name,
    required this.label,
    required this.onTap,
    this.avatarUrl,
    this.previewUrl,
    this.translateLabel = false,
    this.badge,
    this.semanticsLabel,
  });

  final StatusRing ring;
  final String? avatarUrl;

  /// A still from the newest Vibe: shown in the circle instead of the photo.
  /// Null (older posts, the host's "Add Vibe"): the photo.
  final String? previewUrl;

  /// For the avatar's letter when there is no photo.
  final String name;

  /// The host's name, or an i18n key when [translateLabel].
  final String label;
  final bool translateLabel;
  final VoidCallback onTap;

  /// Over the bottom-right edge (the "+" on the host's own circle).
  final Widget? badge;
  final String? semanticsLabel;

  static double get width => 70.ms;
  static double get photo => 62.ms;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = photo;
    final ringed = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(2.5.ms),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring == StatusRing.fresh
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.accent, c.darkRose],
              )
            : null,
        // Watched: a plain grey ring, clearly not the coloured one.
        color: ring == StatusRing.seen
            ? c.textMuted.withValues(alpha: 0.45)
            : null,
      ),
      child: Container(
        padding: EdgeInsets.all(2.ms),
        decoration: BoxDecoration(color: c.background, shape: BoxShape.circle),
        child: previewUrl == null
            ? CAvatar(url: avatarUrl, name: name, size: size - 9.ms)
            : ClipOval(
                child: SizedBox.square(
                  dimension: size - 9.ms,
                  child: CImage(
                    url: previewUrl,
                    width: size - 9.ms,
                    height: size - 9.ms,
                    // The photo while the still loads or if it fails.
                    errorWidget: CAvatar(
                      url: avatarUrl,
                      name: name,
                      size: size - 9.ms,
                    ),
                  ),
                ),
              ),
      ),
    );
    final text = translateLabel
        ? CText(
            label,
            size: 11,
            weight: FontWeight.w600,
            color: c.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            align: TextAlign.center,
          )
        : CText.raw(
            label,
            size: 11,
            weight: FontWeight.w600,
            color: c.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            align: TextAlign.center,
          );
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Pressable(
        onPressed: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ringed,
                    if (badge != null)
                      PositionedDirectional(end: 0, bottom: 0, child: badge!),
                  ],
                ),
              ),
              SizedBox(height: 5.ms),
              text,
            ],
          ),
        ),
      ),
    );
  }
}

/// The "+" on the host's own circle: its own tap target, to post another
/// even while one is up.
class StatusAddBadge extends StatelessWidget {
  const StatusAddBadge({super.key, required this.onTap, this.busy = false});

  final VoidCallback onTap;

  /// A post is uploading: a spinner instead of the "+".
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = 22.ms;
    return Pressable(
      onPressed: busy ? null : onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [c.accent, c.darkRose]),
          border: Border.all(color: c.background, width: 2),
        ),
        child: busy
            ? Padding(
                padding: EdgeInsets.all(4.ms),
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: c.onAccent,
                ),
              )
            : Icon(LucideIcons.plus, size: 13.ms, color: c.onAccent),
      ),
    );
  }
}
