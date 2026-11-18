import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/screen_tracker.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/listing_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/external_link.dart';
import 'helper/host_profile_rules.dart';

// The small sheets shown over the profile (RN share sheet, ⋮ menu,
// influencer sheet). A sheet returns what was picked and the caller acts
// once it has closed.

/// Slides up from the bottom; tap outside or drag down to close. Never
/// taller than the space under the status bar (`useSafeArea`, which also
/// keeps the page from rebuilding while the keyboard moves).
/// [name]: the analytics screen name of the sheet.
Future<T?> showProfileSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  required String name,
}) => showModalBottomSheet<T>(
  context: context,
  routeSettings: ScreenTracker.sheet(name),
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.transparent,
  elevation: 0,
  barrierColor: AppColors.blackA(0.55),
  builder: builder,
);

enum ProfileMenuAction { report, block }

/// The ⋮ menu: report or block this host.
Future<ProfileMenuAction?> showProfileMenu(BuildContext context) =>
    showProfileSheet<ProfileMenuAction>(
      context,
      (_) => const _MenuSheet(),
      name: 'host_profile_menu_sheet',
    );

enum _ShareChoice { native, copy, qr }

/// Share sheet: the link, "Share via…" (OS sheet), "Copy Link" and "Show QR
/// Code" (RN). The pick runs once the sheet has closed.
Future<void> showShareSheet(
  BuildContext context, {
  required String url,
  required VoidCallback onShareVia,
  required VoidCallback onCopy,
  required VoidCallback onShowQr,
}) async {
  final choice = await showProfileSheet<_ShareChoice>(
    context,
    (_) => _ShareSheet(url: url),
    name: 'host_profile_share_sheet',
  );
  switch (choice) {
    case _ShareChoice.native:
      onShareVia();
    case _ShareChoice.copy:
      onCopy();
    case _ShareChoice.qr:
      onShowQr();
    case null:
  }
}

/// Platforms the host is verified on, with links (RN social preview).
Future<void> showInfluencerSheet(BuildContext context, HostCard host) =>
    showProfileSheet<void>(
      context,
      (_) => _InfluencerSheet(host: host),
      name: 'host_influencer_sheet',
    );

/// Rounded card at the bottom of a profile sheet.
class SheetCard extends StatelessWidget {
  const SheetCard({super.key, required this.child, this.handle = false});

  final Widget child;

  /// Drag bar on top (sheets without a header).
  final bool handle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 20.ms,
      ),
      decoration: BoxDecoration(
        color: c.isDark ? AppColors.darkSurface : AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32.ms)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (handle)
            Container(
              width: 48.ms,
              height: 5.ms,
              margin: EdgeInsets.only(top: 20.ms, bottom: 18.ms),
              decoration: BoxDecoration(
                color: c.isDark
                    ? AppColors.whiteA(0.18)
                    : AppColors.blackA(0.15),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Icon + title on the left, a round close button on the right.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
  });

  final IconData icon;
  final Color iconColor;

  /// i18n key.
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.ms, vertical: 16.ms),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.07),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18.ms, color: iconColor),
          SizedBox(width: 8.ms),
          Expanded(
            child: CText(
              title,
              size: 14,
              weight: FontWeight.w900,
              letterSpacing: 1,
              maxLines: 1,
            ),
          ),
          Pressable(
            onPressed: () => Navigator.of(context).pop(),
            semanticLabel: context.t('actions.close'),
            hitPadding: const EdgeInsets.all(6),
            child: Container(
              width: 32.ms,
              height: 32.ms,
              decoration: BoxDecoration(
                color: dark ? AppColors.whiteA(0.1) : AppColors.blackA(0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.x, size: 16.ms, color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable row: tinted icon tile + label.
class SheetActionRow extends StatelessWidget {
  const SheetActionRow({
    super.key,
    required this.icon,
    required this.tint,
    required this.label,
    required this.onTap,
    this.iconBg,
    this.labelColor,
    this.trailing,
  });

  final IconData icon;
  final Color tint;

  /// i18n key.
  final String label;
  final VoidCallback onTap;
  final Color? iconBg;
  final Color? labelColor;

  /// After the label (a "New" pill, say).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    return Pressable(
      onPressed: onTap,
      activeOpacity: 0.8,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.ms),
        padding: EdgeInsets.all(14.ms),
        decoration: BoxDecoration(
          color: dark ? AppColors.whiteA(0.04) : AppColors.blackA(0.03),
          borderRadius: BorderRadius.circular(16.ms),
        ),
        child: Row(
          children: [
            Container(
              width: 38.ms,
              height: 38.ms,
              decoration: BoxDecoration(
                color:
                    iconBg ??
                    (dark ? AppColors.whiteA(0.06) : AppColors.blackA(0.04)),
                borderRadius: BorderRadius.circular(13.ms),
              ),
              child: Icon(icon, size: 19.ms, color: tint),
            ),
            SizedBox(width: 14.ms),
            Expanded(
              child: CText(
                label,
                size: 15,
                weight: FontWeight.w700,
                color: labelColor ?? c.text,
                maxLines: 1,
              ),
            ),
            if (trailing != null) ...[SizedBox(width: 8.ms), trailing!],
          ],
        ),
      ),
    );
  }
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SheetCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader(
            icon: LucideIcons.share2,
            iconColor: c.accent,
            title: 'host:share.title',
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.ms, 18.ms, 20.ms, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText.raw(
                  url,
                  size: 12,
                  weight: FontWeight.w600,
                  color: c.isDark
                      ? AppColors.whiteA(0.5)
                      : AppColors.blackA(0.45),
                  maxLines: 1,
                ),
                SizedBox(height: 18.ms),
                SheetActionRow(
                  icon: LucideIcons.share2,
                  tint: c.accent,
                  label: 'host:share.native',
                  onTap: () => Navigator.of(context).pop(_ShareChoice.native),
                ),
                SheetActionRow(
                  icon: LucideIcons.link,
                  tint: BrandColors.lime,
                  label: 'host:share.copy',
                  onTap: () => Navigator.of(context).pop(_ShareChoice.copy),
                ),
                SheetActionRow(
                  icon: LucideIcons.qrCode,
                  tint: c.text,
                  label: 'host:share.qr',
                  onTap: () => Navigator.of(context).pop(_ShareChoice.qr),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuSheet extends StatelessWidget {
  const _MenuSheet();

  @override
  Widget build(BuildContext context) {
    final redBg = StatusColors.dangerRed.withValues(alpha: 0.12);
    void pick(ProfileMenuAction a) => Navigator.of(context).pop(a);
    return SheetCard(
      handle: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.ms),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetActionRow(
              icon: LucideIcons.flag,
              tint: StatusColors.dangerRed,
              iconBg: redBg,
              label: 'host:menu.report',
              labelColor: StatusColors.dangerRed,
              onTap: () => pick(ProfileMenuAction.report),
            ),
            SheetActionRow(
              icon: LucideIcons.userX,
              tint: StatusColors.dangerRed,
              iconBg: redBg,
              label: 'host:menu.block',
              labelColor: StatusColors.dangerRed,
              onTap: () => pick(ProfileMenuAction.block),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfluencerSheet extends StatelessWidget {
  const _InfluencerSheet({required this.host});
  final HostCard host;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    Widget row(SocialKind kind, String label, IconData icon, Color color) {
      final url = HostProfileRules.platformUrl(host, kind);
      return Container(
        margin: EdgeInsets.only(bottom: 12.ms),
        padding: EdgeInsets.all(14.ms),
        decoration: BoxDecoration(
          color: c.isDark ? AppColors.whiteA(0.04) : AppColors.blackA(0.03),
          borderRadius: BorderRadius.circular(16.ms),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24.ms, color: color),
            SizedBox(width: 12.ms),
            Expanded(child: CText(label, size: 15, weight: FontWeight.w700)),
            if (url != null && !(ios && kind == SocialKind.instagram))
              Pressable(
                onPressed: () => openExternalLink(
                  url,
                  kind: kind.name,
                  hostId: HostProfileRules.expertKey(host),
                  source: 'influencer_sheet',
                ),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14.ms,
                    vertical: 8.ms,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10.ms),
                  ),
                  child: CText(
                    'host:social.view',
                    size: 12,
                    weight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return SheetCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(
            icon: LucideIcons.crown,
            iconColor: BrandColors.lime,
            title: 'host:social.verified_title',
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.ms, 24.ms, 20.ms, 10.ms),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CText(
                  'host:social.verified_message',
                  size: 13,
                  weight: FontWeight.w600,
                  color: c.isDark
                      ? AppColors.whiteA(0.6)
                      : AppColors.blackA(0.5),
                ),
                SizedBox(height: 20.ms),
                if (host.instaVerified)
                  row(
                    SocialKind.instagram,
                    'host:social.instagram',
                    LucideIcons.camera,
                    SocialColors.instagram,
                  ),
                if (host.facebookVerified)
                  row(
                    SocialKind.facebook,
                    'host:social.facebook',
                    Icons.facebook,
                    SocialColors.facebook,
                  ),
                if (host.snapchatVerified)
                  row(
                    SocialKind.snapchat,
                    'host:social.snapchat',
                    LucideIcons.ghost,
                    SocialColors.snapchat,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand colors of the social networks (RN literals).
abstract final class SocialColors {
  static const instagram = Color(0xFFE1306C);
  static const facebook = Color(0xFF1877F2);
  static const snapchat = Color(0xFFD4CA00);
}
