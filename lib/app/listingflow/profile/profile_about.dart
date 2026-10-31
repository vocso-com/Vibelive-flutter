import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/analytics/events/discover_events.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/vibe_colors.dart';
import '../../../core/utils/scale.dart';
import '../../api/listingflow/listing_models.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';
import 'helper/external_link.dart';
import 'helper/host_profile_rules.dart';
import 'profile_sheets.dart';
import 'video_intro.dart';
import 'voice_intro.dart';

/// Instagram / Facebook / Snapchat / website chips (verified ones tinted).
class ProfileSocialLinks extends StatelessWidget {
  const ProfileSocialLinks({super.key, required this.host});
  final HostCard host;

  @override
  Widget build(BuildContext context) {
    final links = HostProfileRules.socialLinks(
      host,
      ios: Theme.of(context).platform == TargetPlatform.iOS,
    );
    if (links.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 14.ms),
      child: Wrap(
        spacing: 8.ms,
        runSpacing: 8.ms,
        children: [
          for (final l in links)
            _SocialChip(l, hostId: HostProfileRules.expertKey(host)),
        ],
      ),
    );
  }
}

class _SocialChip extends StatelessWidget {
  const _SocialChip(this.link, {this.hostId});
  final SocialLink link;
  final String? hostId;

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    final (icon, label, brand) = switch (link.kind) {
      SocialKind.instagram => (
        LucideIcons.camera,
        'host:social.instagram',
        SocialColors.instagram,
      ),
      SocialKind.facebook => (
        Icons.facebook,
        'host:social.facebook',
        SocialColors.facebook,
      ),
      SocialKind.snapchat => (
        LucideIcons.ghost,
        'host:social.snapchat',
        SocialColors.snapchat,
      ),
      SocialKind.website => (
        LucideIcons.link,
        'host:social.website',
        dark ? AppColors.white : AppColors.black,
      ),
    };
    final verified = link.verified;
    final fg = verified ? brand : (dark ? AppColors.white : AppColors.black);
    return Pressable(
      onPressed: () => openExternalLink(
        link.url,
        kind: link.kind.name,
        hostId: hostId,
        source: 'profile_social',
      ),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.ms, vertical: 6.ms),
        decoration: BoxDecoration(
          color: verified
              ? brand.withValues(alpha: dark ? 0.2 : 0.1)
              : (dark ? AppColors.whiteA(0.06) : AppColors.blackA(0.04)),
          borderRadius: BorderRadius.circular(10.ms),
          border: Border.all(
            color: verified
                ? brand
                : (dark ? AppColors.whiteA(0.1) : AppColors.blackA(0.1)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.ms, color: fg),
            SizedBox(width: 5.ms),
            CText(label, size: 10.5, weight: FontWeight.w700, color: fg),
            if (verified) ...[
              SizedBox(width: 5.ms),
              Icon(LucideIcons.badgeCheck, size: 11.ms, color: brand),
            ],
          ],
        ),
      ),
    );
  }
}

/// "THE_VIBE": tagline, description with Read more, voice intro, sparkle
/// watermark.
class ProfileVibeCard extends StatelessWidget {
  const ProfileVibeCard({super.key, required this.host});
  final HostCard host;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = c.isDark;
    final tagline = host.tagline;
    final quoteStyle = (
      size: 16.0,
      weight: FontWeight.w700,
      height: 23.0,
      color: dark ? AppColors.whiteA(0.9) : AppColors.blackA(0.86),
    );
    return Container(
      margin: EdgeInsets.only(bottom: 14.ms),
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: dark ? AppColors.whiteA(0.04) : AppColors.blackA(0.025),
        borderRadius: BorderRadius.circular(22.ms),
        border: Border.all(
          color: dark ? AppColors.whiteA(0.07) : AppColors.blackA(0.08),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -6.ms,
            bottom: -6.ms,
            child: Opacity(
              opacity: 0.08,
              child: Icon(LucideIcons.sparkles, size: 32.ms, color: c.text),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CText(
                'host:about.vibe',
                size: 9,
                weight: FontWeight.w900,
                letterSpacing: 2,
                color: c.accent,
              ),
              SizedBox(height: 4.ms),
              if (tagline.isNotEmpty)
                CText.raw(
                  '"$tagline"',
                  size: quoteStyle.size,
                  weight: quoteStyle.weight,
                  height: quoteStyle.height,
                  color: quoteStyle.color,
                  maxLines: 2,
                )
              else
                CText(
                  'host:about.default_tagline',
                  size: quoteStyle.size,
                  weight: quoteStyle.weight,
                  height: quoteStyle.height,
                  color: quoteStyle.color,
                  maxLines: 2,
                ),
              if (host.description.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 8.ms),
                  child: _Description(host.description),
                ),
              if (host.audioIntro case final url?)
                VoiceIntro(url: url, hostId: HostProfileRules.expertKey(host)),
              // Only ever an approved clip: the server withholds the file for
              // anything else and the listing model checks the status again.
              // onTalkNow is deliberately not passed yet — the prompt stays
              // hidden until it is wired to this profile's own call action,
              // because a dead button is worse than no button.
              if (host.videoIntro case final url?)
                VideoIntro(url: url, hostName: host.name),
            ],
          ),
        ],
      ),
    );
  }
}

/// Three lines, then "Read more" / "Read less" when the text is longer.
class _Description extends HookWidget {
  const _Description(this.text);
  final String text;

  static const _lines = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final expanded = useState(false);
    final color = c.isDark ? AppColors.whiteA(0.6) : AppColors.blackA(0.6);
    final base = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, box) {
        final fontSize = 12.5.ms;
        final style = base.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          height: 18.ms / fontSize,
          letterSpacing: 0,
        );
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: box.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CText.raw(
              text,
              size: 12.5,
              height: 18,
              weight: FontWeight.w500,
              color: color,
              maxLines: expanded.value ? null : _lines,
            ),
            if (long)
              Pressable(
                onPressed: () {
                  expanded.value = !expanded.value;
                  DiscoverEvents.bioToggled(expanded: expanded.value);
                },
                hitPadding: EdgeInsets.symmetric(vertical: 4.ms),
                child: CText(
                  expanded.value
                      ? 'host:about.read_less'
                      : 'host:about.read_more',
                  size: 11,
                  weight: FontWeight.w700,
                  color: c.accent,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "TOPICS & EXPERTISE" and "LANGUAGES SPOKEN" (RN `SpecializationCard`);
/// nothing when both are empty.
class ProfileSpecializationCard extends StatelessWidget {
  const ProfileSpecializationCard({super.key, required this.host});
  final HostCard host;

  @override
  Widget build(BuildContext context) {
    final spec = HostProfileRules.specialization(host.tags, host.languages);
    if (spec.topics.isEmpty && spec.languages.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final dark = c.isDark;
    final hasTopics = spec.topics.isNotEmpty;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 14.ms),
      padding: EdgeInsets.all(14.ms),
      decoration: BoxDecoration(
        color: dark ? AppColors.whiteA(0.03) : AppColors.blackA(0.015),
        borderRadius: BorderRadius.circular(20.ms),
        border: Border.all(
          color: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasTopics) ...[
            _Label(
              leading: Container(
                width: 6.ms,
                height: 6.ms,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
              text: 'host:about.topics',
            ),
            SizedBox(height: 9.ms),
            Wrap(
              spacing: 6.ms,
              runSpacing: 6.ms,
              children: [for (final t in spec.topics) _TopicChip(t)],
            ),
          ],
          if (spec.languages.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: hasTopics ? 12.ms : 0),
              padding: EdgeInsets.only(top: hasTopics ? 10.ms : 0),
              decoration: hasTopics
                  ? BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: dark
                              ? AppColors.whiteA(0.06)
                              : AppColors.blackA(0.05),
                        ),
                      ),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Label(
                    leading: Icon(
                      LucideIcons.globe,
                      size: 11.ms,
                      color: BrandColors.teal,
                    ),
                    text: 'host:about.languages',
                  ),
                  SizedBox(height: 8.ms),
                  Wrap(
                    spacing: 6.ms,
                    runSpacing: 6.ms,
                    children: [
                      for (final l in spec.languages) _LanguageChip(l),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.leading, required this.text});
  final Widget leading;
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    return Row(
      children: [
        leading,
        SizedBox(width: 6.ms),
        Flexible(
          child: CText(
            text,
            size: 9,
            weight: FontWeight.w900,
            letterSpacing: 1.6,
            color: dark ? AppColors.whiteA(0.5) : AppColors.blackA(0.5),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 11.ms, vertical: 6.ms),
      decoration: BoxDecoration(
        color: dark ? AppColors.whiteA(0.07) : AppColors.white,
        borderRadius: BorderRadius.circular(12.ms),
        border: Border.all(
          color: dark ? AppColors.whiteA(0.08) : AppColors.blackA(0.07),
        ),
      ),
      child: CText.raw(
        label,
        size: 12,
        weight: FontWeight.w600,
        letterSpacing: 0.1,
        color: dark ? AppColors.white : const Color(0xFF1E293B),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = context.colors.isDark;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 11.ms, vertical: 5.ms),
      decoration: BoxDecoration(
        color: dark
            ? BrandColors.teal.withValues(alpha: 0.12)
            : BrandColors.tealDark.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10.ms),
        border: Border.all(
          color: dark
              ? BrandColors.teal.withValues(alpha: 0.22)
              : BrandColors.tealDark.withValues(alpha: 0.18),
        ),
      ),
      child: CText.raw(
        label.toUpperCase(),
        size: 11,
        weight: FontWeight.w800,
        letterSpacing: 0.5,
        color: dark ? BrandColors.teal : BrandColors.tealDark,
      ),
    );
  }
}
