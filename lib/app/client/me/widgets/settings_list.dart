import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/analytics/events/me_events.dart';
import '../../../../core/app_scope.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/vibe_colors.dart';
import '../../../../core/utils/scale.dart';
import '../../../component/c_alert.dart';
import '../../../component/c_text.dart';
import '../../../component/c_toast.dart';
import '../../../component/pressable.dart';
import '../../../chatscreen/settings/chat_settings_card.dart';
import '../../../hosthub/hub/host_hub_menu.dart';
import '../../../hosthub/hub/hub_list.dart';
import '../../../hosthub/onboarding/helper/host_palette.dart';
import '../../../hosthub/onboarding/helper/intro_image.dart';
import '../../../hosthub/onboarding/widgets/sheet_frame.dart';
import '../helper/host_unlock_promo.dart';
import '../helper/me_actions.dart';
import '../helper/me_data.dart';
import '../helper/me_menu.dart';
import 'host_unlock_row.dart';
import 'me_segmented.dart';
import 'me_rows.dart';

/// The settings list (RN MeCard, Settings section), as a sliver: wallet,
/// IDENTITY and HOST HUB options inline, RESOURCES as a card that opens its
/// sub-menu. Clients always see it; hosts on the Settings tab.
class MeSettingsList extends HookWidget {
  const MeSettingsList({super.key, required this.data});
  final MeData data;

  @override
  Widget build(BuildContext context) {
    final userKey = data.userKey;
    final seen = useMemoized(() => HostUnlockPromo.seen(userKey), [userKey]);
    final dismissed = useState(false);
    final promo =
        !data.isExpert &&
        data.isPersonalInfoComplete &&
        !seen &&
        !dismissed.value;

    void markSeen() {
      dismissed.value = true;
      HostUnlockPromo.markSeen(userKey).ignore();
    }

    Future<void> becomeHost() async {
      MeEvents.becomeHostTapped(
        source: 'me_list',
        eligible: data.isPersonalInfoComplete,
        missingCount: data.missingPersonalInfo.length,
      );
      if (!data.isPersonalInfoComplete) {
        // Explain instead of a dead row: say what is missing, go fill it in.
        final fields = data.missingPersonalInfo
            .map((f) => context.t(f.i18nKey))
            .join(', ');
        final go = await CAlert.confirm(
          title: 'client:me.become_host_locked.title',
          message: 'client:me.become_host_locked.message',
          variables: {'fields': fields},
          confirmLabel: 'client:me.become_host_locked.action',
          variant: CAlertVariant.info,
        );
        MeEvents.becomeHostLocked(action: go ? 'fill_info' : 'cancel');
        if (go && context.mounted) {
          await MeActions.open(context, AppRoutes.personalInfo);
        }
        return;
      }
      if (promo) markSeen();
      // Decode the intro photo first so it never pops in.
      await HostIntroImage.precache(context);
      if (context.mounted) {
        await MeActions.open(context, AppRoutes.hostOnboarding);
      }
    }

    Future<void> shareProfile() async {
      final link = data.profileLink;
      if (link == null) {
        MeEvents.profileShareUnavailable(source: 'me_list');
        CToast.show(
          'client:me.share.unavailable',
          variant: CToastVariant.error,
        );
        return;
      }
      MeEvents.profileShared(source: 'me_list', hostId: data.expertId);
      await MeActions.share(
        context.t('client:me.share.message', variables: {'link': link}),
        contentType: 'own_profile',
      );
    }

    void tap(MeMenuItem item) {
      MeEvents.itemTapped(
        item: MeActions.itemName(item.label),
        section: 'identity',
      );
      switch (item.id) {
        case MeItemId.share:
          shareProfile();
        case MeItemId.becomeHost:
          becomeHost();
        case MeItemId.verification:
          MeActions.open(context, data.verificationRoute);
        case MeItemId.route:
          MeActions.open(context, item.route!);
      }
    }

    final badgeKey = data.badgePromptKey;
    // Same rows as the Host Hub card (lib/app/hosthub/hub/hub_list.dart).
    Widget row(MeMenuItem item) {
      Widget build([Widget? leading]) => HubListRow(
        icon: item.icon,
        label: item.label,
        leading: leading,
        dimmed: item.id == MeItemId.becomeHost && !data.isPersonalInfoComplete,
        onTap: () => tap(item),
      );

      return switch (item.id) {
        MeItemId.becomeHost when promo => MeHostUnlockRow(
          rowBuilder: build,
          onDismiss: markSeen,
        ),
        MeItemId.verification when badgeKey != null => MeFloatingPill(
          pill: MeBadgeLabel(labelKey: badgeKey, size: 9),
          child: build(),
        ),
        _ => build(),
      };
    }

    final gap = SizedBox(height: 12.ms);
    return SliverList.list(
      children: [
        SizedBox(height: 16.ms),
        HubListCard(
          rows: [
            HubListRow(
              icon: LucideIcons.wallet,
              label: 'client:me.wallet.title',
              subtitle: 'client:me.wallet.subtitle',
              onTap: () {
                MeEvents.itemTapped(item: 'wallet', section: 'wallet');
                MeActions.open(context, AppRoutes.wallet);
              },
            ),
          ],
        ),
        gap,
        const MeCategoryHeader(label: 'client:me.categories.identity'),
        HubListCard(
          rows: [
            for (final item in MeMenu.identity)
              if (item.visibleFor(isExpert: data.isExpert)) row(item),
          ],
        ),
        if (data.isExpert) ...[
          gap,
          MeCategoryHeader(
            label: 'client:me.categories.hub',
            trailing: badgeKey == null
                ? null
                : MeBadgePromptChip(
                    labelKey: badgeKey,
                    onTap: () {
                      MeEvents.itemTapped(
                        item: 'verification_badge_prompt',
                        section: 'badge_chip',
                      );
                      MeActions.open(context, AppRoutes.verificationBadgeFee);
                    },
                  ),
          ),
          // RN HOST HUB, every option, as one card (lib/app/hosthub/hub).
          HostHubMenu(
            host: data.host!,
            // Taps are logged inside HostHubMenu (host_hub_item_tapped).
            open: (route) => MeActions.open(context, route),
            verificationRoute: data.verificationRoute,
            verificationPrompt: badgeKey == null
                ? null
                : MeBadgePromptChip(
                    labelKey: badgeKey,
                    onTap: () {
                      MeEvents.itemTapped(
                        item: 'verification_badge_prompt',
                        section: 'badge_chip',
                      );
                      MeActions.open(context, data.verificationRoute);
                    },
                  ),
          ),
        ],
        gap,
        const _ThemeCard(),
        gap,
        const _LanguageCard(),
        gap,
        // Chat notifications, and "Accept chats" for hosts (chat on only).
        const ChatSettingsCard(),
        HubListCard(
          rows: [
            HubListRow(
              icon: LucideIcons.settings2,
              label: 'client:me.categories.resources',
              subtitle: 'client:me.categories.resources_hint',
              onTap: () {
                MeEvents.itemTapped(item: 'resources', section: 'resources');
                MeActions.open(context, MeMenu.resourcesRoute);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Theme: Device (the default: the app follows the phone's light / dark
/// setting, live), Light or Dark.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard();

  static const _modes = [
    MeSegment(
      ThemeMode.system,
      LucideIcons.smartphone,
      'client:me.theme.system',
    ),
    MeSegment(ThemeMode.light, LucideIcons.sun, 'client:me.theme.light'),
    MeSegment(ThemeMode.dark, LucideIcons.moon, 'client:me.theme.dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final theme = AppScope.of(context).theme;
    return HubListCard(
      rows: [
        Padding(
          padding: EdgeInsets.all(14.ms),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32.ms,
                    height: 32.ms,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.tint,
                      borderRadius: BorderRadius.circular(10.ms),
                    ),
                    child: Icon(
                      context.colors.isDark
                          ? LucideIcons.moon
                          : LucideIcons.sun,
                      size: 17.ms,
                      color: p.accent,
                    ),
                  ),
                  SizedBox(width: 12.ms),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CText(
                          'client:me.theme.title',
                          size: 15,
                          weight: FontWeight.w600,
                          color: p.text,
                          maxLines: 1,
                        ),
                        SizedBox(height: 2.ms),
                        CText(
                          'client:me.theme.hint',
                          size: 12.5,
                          weight: FontWeight.w500,
                          color: p.muted,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.ms),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: theme,
                builder: (_, mode, _) => MeSegmented<ThemeMode>(
                  segments: _modes,
                  selected: mode,
                  onSelect: (next) {
                    if (next != mode) MeEvents.themeChanged(next.name);
                    theme.setMode(next).ignore();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// App language: the current one in its own script; a tap lists them all.
class _LanguageCard extends StatelessWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    final locale = AppScope.of(context).locale;
    return ValueListenableBuilder<Locale>(
      valueListenable: locale,
      builder: (context, current, _) => HubListCard(
        rows: [
          HubListRow(
            icon: LucideIcons.languages,
            label: 'client:me.language.title',
            subtitle: 'client:me.language.hint',
            trailing: HubListRow.value(
              AppI18n.languageOf(current).nativeName,
              p.accent,
            ),
            onTap: () async {
              MeEvents.itemTapped(item: 'language', section: 'language');
              final picked = await showHostSheet<AppLanguage>(
                context,
                title: 'client:me.language.choose',
                name: 'language_picker',
                child: LanguagePicker(selected: current.languageCode),
              );
              if (picked == null || picked.code == current.languageCode) {
                return;
              }
              MeEvents.languageChanged(
                from: current.languageCode,
                to: picked.code,
              );
              await locale.setLocale(picked.locale);
            },
          ),
        ],
      ),
    );
  }
}

/// Every app language, each in its own script with its English name; the
/// current one ticked. Pops the one tapped.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.selected});

  /// Language code of the current language.
  final String selected;

  @override
  Widget build(BuildContext context) {
    final p = HostPalette.of(context);
    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.fromLTRB(16.ms, 0, 16.ms, 8.ms),
      itemCount: AppI18n.languages.length,
      separatorBuilder: (_, _) => SizedBox(height: 8.ms),
      itemBuilder: (context, i) {
        final lang = AppI18n.languages[i];
        final on = lang.code == selected;
        return Pressable(
          key: ValueKey('language_${lang.code}'),
          onPressed: () => Navigator.of(context).pop(lang),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.ms, vertical: 12.ms),
            decoration: BoxDecoration(
              color: on ? p.tint : null,
              borderRadius: BorderRadius.circular(14.ms),
              border: Border.all(color: on ? p.accent : p.track, width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CText.raw(
                        lang.nativeName,
                        size: 16,
                        weight: FontWeight.w700,
                        color: on ? p.accent : p.text,
                        maxLines: 1,
                      ),
                      if (lang.englishName != lang.nativeName) ...[
                        SizedBox(height: 2.ms),
                        CText.raw(
                          lang.englishName,
                          size: 12.5,
                          weight: FontWeight.w500,
                          color: p.muted,
                          maxLines: 1,
                        ),
                      ],
                    ],
                  ),
                ),
                if (on)
                  Icon(LucideIcons.circleCheck, size: 20.ms, color: p.accent),
              ],
            ),
          ),
        );
      },
    );
  }
}
