import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/discover_events.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../component/c_image.dart';
import '../../component/pressable.dart';
import '../../chatscreen/list/chat_tab.dart';
import '../../homescreen/helper/home_controller.dart';
import '../../../core/session/session_store.dart';
import '../../client/me/helper/me_data.dart';
import 'host_status_pill.dart';
import 'navbar_collapse.dart';

/// Floating dock: an icon-only nav island (Discover · Chats · History · Me;
/// Chats only while chat is on) and, for
/// hosts, their availability pill ([HostStatusPill]). Solid, not blurred: a
/// live blur re-renders on every scroll frame. Shrinks while the feed
/// scrolls down.
///
/// Home's `Scaffold.bottomNavigationBar` (with `extendBody`), so floating
/// toasts land above it. The margins around the dock let taps through.
class BottomNavbar extends StatelessWidget {
  const BottomNavbar({super.key, required this.home});
  final HomeController home;

  /// Dock height (both parts).
  static double get barHeight => math.max(56.ms, 56);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // viewPadding: the bar must not jump when a keyboard (in a sheet on top)
    // eats the bottom padding.
    final bottom = math.max(
      12.ms,
      MediaQuery.viewPaddingOf(context).bottom + 8.ms,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16.ms, 0, 16.ms, bottom),
      // Collapsing narrows the island (its icons close up) and nudges the
      // dock down; only on a scroll-direction flip. No scale: shrinking the
      // text and avatar mid-scroll read as jitter.
      child: RepaintBoundary(
        child: ValueListenableBuilder<bool>(
          valueListenable: NavbarCollapse.instance,
          builder: (_, collapsed, _) => AnimatedSlide(
            offset: Offset(0, collapsed ? 0.12 : 0),
            duration: _anim,
            curve: Curves.easeOutCubic,
            child: SizedBox(
              height: barHeight,
              child: ValueListenableBuilder<SessionState>(
                valueListenable: SessionStore.instance,
                builder: (_, session, _) {
                  final me = MeData.of(session);
                  final host = me.isExpert;
                  return ChatTabGate(
                    builder: (_, chats) => LayoutBuilder(
                    builder: (_, box) {
                      final tabs = [
                        (HomeTab.discover, LucideIcons.house),
                        if (chats) (HomeTab.chats, LucideIcons.messageCircle),
                        (HomeTab.history, LucideIcons.activity),
                        (HomeTab.me, LucideIcons.user),
                      ];
                      final pill = host ? HostStatusPill.width + _gap : 0;
                      final full = box.maxWidth - pill;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: _anim,
                            curve: Curves.easeOutCubic,
                            width: collapsed
                                ? math.min(_compactWidth(tabs.length), full)
                                : full,
                            height: barHeight,
                            padding: EdgeInsets.symmetric(horizontal: 10.ms),
                            decoration: BoxDecoration(
                              color: c.navBg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: c.border),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.blackA(0.16),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ValueListenableBuilder<HomeTab>(
                              valueListenable: home.tab,
                              builder: (_, active, _) => Row(
                                children: [
                                  for (final (tab, icon) in tabs)
                                    Expanded(
                                      child: _Item(
                                        icon: icon,
                                        label: tab == HomeTab.chats
                                            ? ChatTabGate.label
                                            : 'home:nav.${tab.name}',
                                        badge: tab == HomeTab.chats
                                            ? const ChatUnreadBadge()
                                            : null,
                                        active: active == tab,
                                        onPressed: () {
                                          DiscoverEvents.navTabTapped(
                                            tab: tab.name,
                                            reselect: active == tab,
                                          );
                                          home.select(tab);
                                        },
                                        // Profile shows who is signed in.
                                        avatar: tab == HomeTab.me
                                            ? (
                                                url: me.navAvatarUrl,
                                                name: me.name,
                                              )
                                            : null,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (host) ...[
                            SizedBox(width: _gap),
                            HostStatusPill(
                              mode: me.availability,
                              height: barHeight,
                            ),
                          ],
                        ],
                      );
                    },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _anim = Duration(milliseconds: 220);

  static double get _gap => 10.ms;

  /// Collapsed island: one 44 pt icon per tab and the side padding.
  static double _compactWidth(int tabs) => tabs * 44.ms + 20.ms;
}

/// Icon only; the active tab is the accent colour with a dot under it.
class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
    this.avatar,
    this.badge,
  });

  /// Over the icon's top end corner (the Chats unread count).
  final Widget? badge;

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onPressed;

  /// Drawn instead of [icon]: a photo, or the name's letter without one.
  final ({String? url, String? name})? avatar;

  /// The active avatar's ring: about 1 pt, in whole device pixels.
  static double _ring(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return math.max(1, dpr.round()) / dpr;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Pressable(
      onPressed: onPressed,
      activeOpacity: 0.8,
      semanticLabel: context.t(label),
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (avatar case final a?)
              // The ring lies on the photo's own edge (no gap, so one clean
              // outline) and is a whole number of device pixels thick: 1 pt
              // is 1.75 px on a 1.75x phone, and that stroke aliased into a
              // ring that looked broken.
              DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: active
                      ? Border.all(width: _ring(context), color: c.accent)
                      : null,
                ),
                // The tab is named "Profile", not the avatar's letter.
                child: ExcludeSemantics(
                  child: CAvatar(url: a.url, name: a.name, size: 27.ms),
                ),
              )
            else if (badge == null)
              Icon(
                icon,
                size: 21.ms,
                color: active ? c.accent : AppColors.gray,
                weight: active ? 700 : 500,
              )
            else
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 21.ms,
                    color: active ? c.accent : AppColors.gray,
                    weight: active ? 700 : 500,
                  ),
                  PositionedDirectional(
                    top: -6.ms,
                    end: -10.ms,
                    child: badge!,
                  ),
                ],
              ),
            SizedBox(height: 3.ms),
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Container(
                width: 4.ms,
                height: 4.ms,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
