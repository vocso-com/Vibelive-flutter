import 'package:flutter_test/flutter_test.dart';
import 'package:vibelive/app/authscreen/helper/campaign_links.dart';
import 'package:vibelive/app/authscreen/helper/link_parser.dart';
import 'package:vibelive/app/hosthub/onboarding/helper/host_steps.dart';
import 'package:vibelive/core/router/app_router.dart';

void main() {
  group('LinkParser.parse (share links)', () {
    test('root slug is a host profile', () {
      final link = LinkParser.parse(
        'https://vibelive.angrymamba.com/john_doe',
      )!;
      expect(link.path, 'expert');
      expect(link.openUserId, 'john_doe');
    });

    test('custom scheme with and without the domain', () {
      expect(
        LinkParser.parse(
          'vibeexpoapp://vibelive.angrymamba.com/abc',
        )!.openUserId,
        'abc',
      );
      expect(LinkParser.parse('vibeexpoapp://wallet')!.path, 'wallet');
    });

    test('suffix -R / -I becomes the r marker', () {
      final link = LinkParser.parse(
        'https://vibelive.angrymamba.com/GFGNNV-I',
      )!;
      expect(link.params['handler'], 'GFGNNV');
      expect(link.params['r'], 'i');
    });

    test('legacy expert-profile.php?userid=', () {
      final link = LinkParser.parse(
        'https://www.vibelive.angrymamba.com/expert-profile.php?userid=doc1',
      )!;
      expect(link.path, 'expert-profile');
      expect(link.openUserId, 'doc1');
    });

    test('junk slugs and foreign hosts are dropped', () {
      expect(
        LinkParser.parse('https://vibelive.angrymamba.com/utm_source=x'),
        isNull,
      );
      expect(
        LinkParser.parse('https://vibelive.angrymamba.com/gclid123'),
        isNull,
      );
      expect(LinkParser.parse('https://evil.com/john'), isNull);
    });
  });

  group('LinkParser.referral', () {
    test('share shape /{code}?r=r|i', () {
      final refer = LinkParser.referral(
        'https://vibelive.angrymamba.com/ABC123?r=r',
      )!;
      expect((refer.handler, refer.intent), ('ABC123', ReferralIntent.refer));
      expect(refer.withSuffix, 'ABC123-R');
      final invite = LinkParser.referral(
        'https://vibelive.angrymamba.com/ABC123?r=i',
      )!;
      expect(invite.withSuffix, 'ABC123-I');
    });

    test('/invite/CODE, /referral?code=, generic ?referral=', () {
      expect(
        LinkParser.referral(
          'https://vibelive.angrymamba.com/invite/XYZ',
        )!.intent,
        ReferralIntent.invite,
      );
      expect(
        LinkParser.referral(
          'https://vibelive.angrymamba.com/referral?code=XYZ',
        )!.intent,
        ReferralIntent.refer,
      );
      expect(
        LinkParser.referral('https://other.site/?referral=XYZ')!.withSuffix,
        'XYZ',
      );
    });

    test('a plain profile share carries no attribution', () {
      expect(
        LinkParser.referral('https://vibelive.angrymamba.com/john'),
        isNull,
      );
    });
  });

  group('install referrer', () {
    test('referrer=CODE-R, double encoded utm_source, bare code', () {
      expect(LinkParser.installReferrer('referrer=ABC-R')!.withSuffix, 'ABC-R');
      expect(
        LinkParser.installReferrer(
          'utm_source%253DABC-I%2526utm_medium%253Dx',
        )!.withSuffix,
        'ABC-I',
      );
      final bare = LinkParser.installReferrer('ABC')!;
      expect((bare.handler, bare.intent), ('ABC', ReferralIntent.hostProfile));
    });

    test('organic / ad-network values are ignored', () {
      expect(
        LinkParser.installReferrer('utm_source=google-play&utm_medium=organic'),
        isNull,
      );
      expect(LinkParser.installReferrer('utm_medium=organic'), isNull);
      expect(LinkParser.installReferrer('(not set)'), isNull);
    });
  });

  test('share link builder', () {
    expect(
      LinkParser.shareLink('CODE', ReferralIntent.refer),
      'https://vibelive.angrymamba.com/CODE?r=r',
    );
    expect(
      LinkParser.shareLink('host'),
      'https://vibelive.angrymamba.com/host',
    );
  });

  group('CampaignLinks', () {
    test('presets, aliases and renamed params', () {
      final t = CampaignLinks.resolve(
        'vibecalling://expert-profile.php?userid=doc9',
      );
      expect(t.route!.route, AppRoutes.home);
      expect(t.params, {'tab': 'DISCOVER', 'openUserId': 'doc9'});
      expect(
        CampaignLinks.resolve('vibecalling://favorites').route!.route,
        AppRoutes.favourites,
      );
    });

    test('missing required params and unknown paths are reported', () {
      expect(CampaignLinks.resolve('vibecalling://page').missing, ['slug']);
      expect(CampaignLinks.resolve('vibecalling://nope').route, isNull);
    });

    test('every screen has a link; hosts and clients land right', () {
      for (final (link, route) in [
        ('vibecalling://categories', AppRoutes.categories),
        ('vibecalling://badge', AppRoutes.verificationBadge),
        ('vibecalling://badge-form', AppRoutes.verificationBadgeForm),
        ('vibecalling://badge-status', AppRoutes.verificationBadgeStatus),
        ('vibecalling://resources?id=3', AppRoutes.categoryMenu),
      ]) {
        expect(CampaignLinks.resolve(link).route?.route, route, reason: link);
      }
      expect(CampaignLinks.resolve('vibecalling://resources').missing, ['id']);

      // Become a Host: the flow for a client, the editor for a host.
      final become = CampaignLinks.resolve('vibecalling://become-host').route!;
      expect(become.routeFor(isHost: false), AppRoutes.hostOnboarding);
      expect(become.routeFor(isHost: true), AppRoutes.professionalDetails);

      // A wallet top-up amount and a Discover topic come through.
      expect(
        CampaignLinks.resolve('vibecalling://wallet?prefillAmount=99').params,
        {'amount': '99'},
      );
      expect(
        CampaignLinks.resolve('vibecalling://home?topic=dating-advice').params,
        {'tab': 'DISCOVER', 'topic': 'dating-advice'},
      );
    });

    // The backend's deep-link presets (app-notification-orchestrator
    // settings.js `defaultDeepLinkPresets`): the moderation thread and the
    // notification composer offer exactly these. Each must open a screen.
    test('every backend preset path opens a screen', () {
      const presets = [
        'home',
        'wallet',
        'search',
        'history',
        'profile',
        'favourites',
        'login',
        'expert-profile.php?userid=x',
        'professional-account',
        'approval',
        'referral',
        'personal-info',
        'interests',
        'expertise',
        'schedule',
        'call-rates',
        'verification-badge',
        'profile-qr',
        'online-status',
        'gst-details',
        'blocked-users',
        'about',
        'support',
        'page?slug=x',
        'webview',
        'become-host',
        'host-basic',
        'host-interests',
        'host-photos',
        'host-voice',
        'host-video',
        'host-tagline',
        'host-bio',
        'host-rates',
        'host-availability',
        'host-preview',
        'host-guidelines',
        'host-step?step=bio',
        'verification-badge-info',
        'verification-badge-form',
        'verification-badge-status',
        'categories',
        'resources?id=1',
        'chats',
        'chat?userid=1',
      ];
      for (final path in presets) {
        final t = CampaignLinks.resolve('vibecalling://$path');
        expect(t.route, isNotNull, reason: path);
        expect(t.missing, isEmpty, reason: path);
      }
      // The older presets' names.
      expect(
        CampaignLinks.resolve('vibecalling://interests').route!.route,
        AppRoutes.categories,
      );
      expect(CampaignLinks.resolve('vibecalling://home?cat=Self-love').params, {
        'tab': 'DISCOVER',
        'topic': 'Self-love',
      });
    });

    test('chat links open the Chats tab and one chat', () {
      final tab = CampaignLinks.resolve('vibecalling://chats');
      expect(tab.route!.route, AppRoutes.home);
      expect(tab.params, {'tab': 'CHATS'});
      final chat = CampaignLinks.resolve('vibecalling://chat?userid=42');
      expect(chat.route!.route, AppRoutes.chat);
      expect(chat.params, {'userId': '42'});
      expect(CampaignLinks.resolve('vibecalling://chat').missing, ['userid']);
    });

    test('each onboarding step has a link', () {
      for (final step in HostStep.pages) {
        if (step == HostStep.submitted) continue;
        final t = CampaignLinks.resolve('vibecalling://host-${step.name}');
        expect(t.params, {'step': step.name}, reason: step.name);
        expect(t.route!.routeFor(isHost: false), AppRoutes.hostOnboarding);
        expect(t.route!.routeFor(isHost: true), AppRoutes.professionalDetails);
      }
      expect(
        CampaignLinks.resolve('vibecalling://host-submitted').route,
        isNull,
      );
      expect(
        CampaignLinks.resolve('vibecalling://host-step?step=voice').params,
        {'step': 'voice'},
      );
      expect(CampaignLinks.resolve('vibecalling://host-step').missing, [
        'step',
      ]);

      expect(HostStep.linkable('voice'), HostStep.voice);
      expect(HostStep.linkable('guidelines'), HostStep.guidelines);
      expect(HostStep.linkable('submitted'), isNull);
      expect(HostStep.linkable('intro'), isNull);
      expect(HostStep.linkable('nope'), isNull);
      expect(HostStep.linkable(null), isNull);
    });

    test('website /app/<screen> links are screen links; slugs stay shares', () {
      for (final web in [
        'https://vibelive.angrymamba.com/app/wallet?amount=99',
        'https://www.vibelive.angrymamba.com/app/wallet?amount=99',
        'vibeexpoapp://vibelive.angrymamba.com/app/wallet?amount=99',
      ]) {
        expect(
          CampaignLinks.fromWeb(web),
          'vibecalling://wallet?amount=99',
          reason: web,
        );
      }
      expect(
        CampaignLinks.fromWeb('https://vibelive.angrymamba.com/wallet'),
        isNull,
      );
      expect(CampaignLinks.fromWeb('https://evil.com/app/wallet'), isNull);
      // `app` is never a host handle.
      expect(
        LinkParser.parse('https://vibelive.angrymamba.com/app')?.isExpert,
        isFalse,
      );
    });

    test('home?q= becomes search', () {
      final t = CampaignLinks.resolve('vibecalling://home?q=dating');
      expect(t.route!.route, AppRoutes.search);
      expect(t.params, {'q': 'dating'});
    });

    test('web urls are normalized and hosts checked', () {
      expect(
        CampaignLinks.webUrl('https%3A%2F%2Fangrymamba.com%2Fx'),
        'https://angrymamba.com/x',
      );
      expect(
        CampaignLinks.webUrl('angrymamba.com/x'),
        'https://angrymamba.com/x',
      );
      expect(CampaignLinks.webUrl('javascript:alert(1)'), isNull);
      expect(
        CampaignLinks.isTrustedHost('https://vibelive.angrymamba.com/a'),
        isTrue,
      );
      expect(
        CampaignLinks.isTrustedHost('https://angrymamba.com.evil.com'),
        isFalse,
      );
    });
  });
}
