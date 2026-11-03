import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/listing_models.dart';
import '../../chatscreen/entry/chat_entry.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/host_profile_controller.dart';
import 'helper/host_profile_rules.dart';
import 'profile_header.dart';

/// Audio / video call buttons with their rates (RN `CallActionsContent`),
/// and Chat beside them.
/// A call type without a rate is hidden; company accounts call for free (the
/// rate still shows, above the label).
/// Only this block rebuilds while a call is being prepared.
class ProfileCallActions extends StatelessWidget {
  const ProfileCallActions({
    super.key,
    required this.host,
    required this.controller,
    required this.isMe,
    required this.isCompany,
  });

  final HostCard host;
  final HostProfileController controller;
  final bool isMe;
  final bool isCompany;

  @override
  Widget build(BuildContext context) {
    final videoRate = host.vPrice > 0;
    final audioRate = host.aPrice > 0;
    final showAudio = audioRate || (isCompany && !videoRate);
    final showVideo = videoRate;

    void call(bool video) {
      if (controller.preparingCall.value) return;
      controller.pendingVideo = video; // only the tapped button spins
      controller.placeCall(
        host,
        video: video,
        isMe: isMe,
        isCompany: isCompany,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 26.ms),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCompany)
            Padding(
              padding: EdgeInsets.only(bottom: 10.ms),
              child: const Center(
                child: CompanyPill(
                  label: 'host:call.company_banner',
                  large: true,
                ),
              ),
            ),
          if (isMe)
            Padding(
              padding: EdgeInsets.only(bottom: 10.ms),
              child: Wrap(
                spacing: 8.ms,
                runSpacing: 6.ms,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const _OwnProfilePill(),
                  if (isCompany)
                    const CompanyPill(label: 'host:header.company_profile'),
                ],
              ),
            ),
          ValueListenableBuilder<bool>(
            valueListenable: controller.preparingCall,
            builder: (_, busy, _) => Row(
              children: [
                if (showAudio)
                  Expanded(
                    child: ProfileCallButton(
                      video: false,
                      filled: !showVideo,
                      busy: busy && !controller.pendingVideo,
                      enabled: !busy && (isCompany || audioRate),
                      label: isCompany ? 'host:call.audio' : null,
                      price: host.aPrice,
                      onTap: () => call(false),
                    ),
                  ),
                if (showAudio && showVideo) SizedBox(width: 10.ms),
                if (showVideo)
                  Expanded(
                    child: ProfileCallButton(
                      video: true,
                      filled: true,
                      busy: busy && controller.pendingVideo,
                      enabled: !busy,
                      label: isCompany ? 'host:call.video' : null,
                      price: host.vPrice,
                      onTap: () => call(true),
                    ),
                  ),
                if (!showAudio && !showVideo)
                  const Expanded(child: ProfileCallsUnavailable()),
                // Chat, when it is on and the host takes chats.
                ProfileChatButton(
                  host: host,
                  isMe: isMe,
                  open: controller.navigate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Audio / Video Call on a host's profile (also under a Vibe).
class ProfileCallButton extends StatelessWidget {
  const ProfileCallButton({
    super.key,
    required this.video,
    required this.filled,
    required this.busy,
    required this.enabled,
    required this.label,
    required this.price,
    required this.onTap,
  });

  final bool video;

  /// Accent background (the main action); outlined otherwise.
  final bool filled;
  final bool busy;
  final bool enabled;

  /// i18n key replacing the rate (company accounts).
  final String? label;
  final double price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final fg = filled ? c.onAccent : c.text;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Pressable(
        onPressed: enabled ? onTap : null,
        activeOpacity: 0.85,
        child: Container(
          height: 54.ms,
          decoration: BoxDecoration(
            color: filled
                ? c.accent
                : (dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.04)),
            borderRadius: BorderRadius.circular(20.ms),
            border: filled
                ? null
                : Border.all(
                    width: 1.5.ms,
                    color: dark
                        ? AppColors.whiteA(0.2)
                        : AppColors.blackA(0.15),
                  ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox.square(
                  dimension: 18.ms,
                  child: RepaintBoundary(
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  ),
                )
              else
                Icon(
                  video ? Icons.videocam : Icons.call,
                  size: (video ? 22 : 20).ms,
                  color: fg,
                ),
              SizedBox(width: 8.ms),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A company calls for free, but still sees the host's
                    // rate above "Audio / Video Call".
                    if (label != null && price > 0 && !busy)
                      CText(
                        'host:call.rate',
                        variables: {'price': HostProfileRules.price(price)},
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: fg.withValues(alpha: 0.8),
                        maxLines: 1,
                      ),
                    CText(
                      busy
                          ? 'host:call.connecting'
                          : (label ?? 'host:call.rate'),
                      variables: {'price': HostProfileRules.price(price)},
                      size: 13,
                      weight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: fg,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Calls unavailable" in place of both buttons.
class ProfileCallsUnavailable extends StatelessWidget {
  const ProfileCallsUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    return Opacity(
      opacity: 0.6,
      child: Container(
        height: 54.ms,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: dark ? AppColors.whiteA(0.05) : AppColors.blackA(0.04),
          borderRadius: BorderRadius.circular(20.ms),
          border: Border.all(
            color: dark ? AppColors.whiteA(0.12) : AppColors.blackA(0.08),
          ),
        ),
        child: CText(
          'host:call.calls_unavailable',
          size: 13,
          weight: FontWeight.w800,
          color: dark ? AppColors.whiteA(0.5) : AppColors.blackA(0.5),
        ),
      ),
    );
  }
}

class _OwnProfilePill extends StatelessWidget {
  const _OwnProfilePill();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.ms, vertical: 4.ms),
      decoration: BoxDecoration(
        color: c.accentA(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.accent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.user, size: 11.ms, color: c.accent),
          SizedBox(width: 5.ms),
          CText(
            'host:call.your_profile',
            size: 9,
            weight: FontWeight.w900,
            letterSpacing: 1.2,
            color: c.accent,
          ),
        ],
      ),
    );
  }
}
