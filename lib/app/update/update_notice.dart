import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/analytics/events/app_events.dart';
import '../../core/analytics/screen_tracker.dart';
import '../../core/i18n/i18n.dart';
import '../../core/network/strapi.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/vibe_colors.dart';
import '../../core/utils/scale.dart';
import '../api/splashscreen/splash_models.dart';
import '../callscreen/helper/call_controller.dart';
import '../component/c_text.dart';
import '../component/pressable.dart';
import '../resourcesscreen/helper/content_blocks.dart';
import '../splashscreen/splash_screen.dart';
import 'helper/update_check.dart';

/// RN `UpdateNotice` (mounted at the app root): "New update available" over
/// whatever screen is open, once the splash has had its moment.
///
/// Never covers a call: while a call is on screen it steps aside and comes
/// back when the call is over. "Later", a tap outside or Back hides it for
/// the rest of the process; a force update (priority "high") can't be
/// closed.
class UpdateNoticeHost extends StatefulWidget {
  const UpdateNoticeHost({super.key, required this.child});

  final Widget child;

  static _UpdateNoticeHostState? _live;

  /// The notice is on screen now (the app-open popup waits for it).
  static bool get isShowing => _live?._showing ?? false;

  @override
  State<UpdateNoticeHost> createState() => _UpdateNoticeHostState();
}

class _UpdateNoticeHostState extends State<UpdateNoticeHost> {
  AppVersionInfo? _info;
  Timer? _wait;
  ChildBackButtonDispatcher? _back;

  @override
  void initState() {
    super.initState();
    UpdateNoticeHost._live = this;
    _wait = Timer(SplashScreen.minDuration, _check);
    appRouter.routerDelegate.addListener(_sync);
    CallController.instance.onCall.addListener(_sync);
  }

  @override
  void dispose() {
    if (identical(UpdateNoticeHost._live, this)) UpdateNoticeHost._live = null;
    _wait?.cancel();
    appRouter.routerDelegate.removeListener(_sync);
    CallController.instance.onCall.removeListener(_sync);
    _releaseBack();
    super.dispose();
  }

  Future<void> _check() async {
    final info = await UpdateCheck.pending();
    if (!mounted || info == null) return;
    setState(() => _info = info);
    _syncBack();
    _logShown();
  }

  /// Analytics, once per notice and only while it is actually on screen
  /// (a call hides it; it shows after the call).
  bool _loggedShown = false;
  void _logShown() {
    final info = _info;
    if (_loggedShown || info == null || !_showing) return;
    _loggedShown = true;
    AppEvents.updatePromptShown(
      version: info.version,
      forced: info.isForceUpdate,
    );
    ScreenTracker.view('update_notice', {'forced': info.isForceUpdate});
  }

  bool get _inCall =>
      CallController.instance.onCall.value ||
      appRouter.routerDelegate.currentConfiguration.uri.path.startsWith(
        AppRoutes.call,
      );

  bool get _showing => _info != null && !_inCall;

  void _sync() {
    if (!mounted || _info == null) return;
    setState(() {});
    _syncBack();
    _logShown();
  }

  /// While shown, Back belongs to the notice (closes it, or does nothing
  /// for a force update) instead of navigating the screen behind it.
  void _syncBack() {
    if (!_showing) return _releaseBack();
    if (_back != null) return;
    _back = appRouter.backButtonDispatcher.createChildBackButtonDispatcher()
      ..addCallback(_onBack)
      ..takePriority();
  }

  void _releaseBack() {
    final back = _back;
    if (back == null) return;
    back.removeCallback(_onBack);
    appRouter.backButtonDispatcher.forget(back);
    _back = null;
  }

  Future<bool> _onBack() async {
    _later();
    return true;
  }

  void _later() {
    final info = _info;
    if (info == null || info.isForceUpdate) return;
    AppEvents.updateDismissed(version: info.version);
    UpdateCheck.dismissed = true;
    setState(() => _info = null);
    _releaseBack();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: _showing && info != null
                ? _UpdateNotice(
                    key: ValueKey(info.version),
                    info: info,
                    onLater: _later,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _UpdateNotice extends StatelessWidget {
  const _UpdateNotice({super.key, required this.info, required this.onLater});

  final AppVersionInfo info;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final force = info.isForceUpdate;
    final title = info.title;
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: force ? null : onLater,
        child: ColoredBox(
          color: AppColors.blackA(0.85),
          child: Center(
            child: GestureDetector(
              onTap: () {}, // taps on the card stay on the card
              child: Container(
                width: size.width * 0.85,
                constraints: BoxConstraints(maxHeight: size.height * 0.8),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.isDark ? AppColors.darkSurface : AppColors.white,
                  borderRadius: BorderRadius.circular(28.ms),
                  border: Border.all(color: AppColors.whiteA(0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Header(accent: c.accent),
                    Flexible(
                      child: Padding(
                        padding: EdgeInsets.all(20.ms),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CText.raw(
                              title ?? context.t('update.title'),
                              size: 20,
                              weight: FontWeight.w900,
                              letterSpacing: 0.5,
                              align: TextAlign.center,
                              color: c.text,
                            ),
                            SizedBox(height: 6.ms),
                            _VersionChip(version: info.version),
                            SizedBox(height: 16.ms),
                            Flexible(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: 200.ms),
                                child: SingleChildScrollView(
                                  child: _Notes(info: info),
                                ),
                              ),
                            ),
                            SizedBox(height: 20.ms),
                            _UpdateButton(accent: c.accent),
                            if (!force)
                              Pressable(
                                onPressed: onLater,
                                hitPadding: EdgeInsets.all(8.ms),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: 10.ms,
                                    horizontal: 20.ms,
                                  ),
                                  child: CText(
                                    'update.later',
                                    size: 14,
                                    weight: FontWeight.w700,
                                    color: c.text.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            SizedBox(height: force ? 12.ms : 4.ms),
                            CText(
                              'update.footer',
                              size: 11,
                              align: TextAlign.center,
                              color: c.text.withValues(alpha: 0.3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120.ms,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent, BrandColors.purpleDark],
        ),
      ),
      child: Container(
        width: 70.ms,
        height: 70.ms,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.whiteA(0.2),
          border: Border.all(color: AppColors.whiteA(0.3), width: 2),
        ),
        child: Icon(Icons.system_update, size: 40.ms, color: AppColors.white),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.ms, vertical: 4.ms),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: c.isDark ? 0.1 : 0.12),
        borderRadius: BorderRadius.circular(12.ms),
      ),
      child: CText.raw(
        'v$version',
        size: 12,
        weight: FontWeight.w800,
        letterSpacing: 0.5,
        color: c.accent,
      ),
    );
  }
}

class _UpdateButton extends StatelessWidget {
  const _UpdateButton({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: () => unawaited(UpdateCheck.openStore()),
      activeOpacity: 0.8,
      child: Container(
        height: 54.ms,
        margin: EdgeInsets.only(bottom: 12.ms),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.ms),
          gradient: LinearGradient(colors: [accent, BrandColors.purpleDark]),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CText(
              'update.cta',
              size: 15,
              weight: FontWeight.w900,
              letterSpacing: 1.5,
              color: AppColors.white,
            ),
            SizedBox(width: 8.ms),
            Icon(LucideIcons.arrowRight, size: 18.ms, color: AppColors.white),
          ],
        ),
      ),
    );
  }
}

/// The release notes: Strapi rich text (headings, paragraphs, lists, with
/// bold / italic / underline / code), plain text, or RN's default line.
class _Notes extends StatelessWidget {
  const _Notes({required this.info});
  final AppVersionInfo info;

  static const _headingSizes = [22.0, 20.0, 18.0, 16.0, 14.0, 12.0];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = c.isDark ? AppColors.whiteA(0.7) : c.textMuted;
    final raw = info.raw['content'] ?? info.raw['description'];
    final blocks = raw is List
        ? StrapiBlocks.parse([
            for (final n in raw)
              if (n is Map) Map<String, dynamic>.from(n),
          ])
        : [
            if ((J.str(raw) ?? '').trim().isNotEmpty)
              ParagraphBlock([InlineRun(J.str(raw)!.trim())]),
          ];
    if (blocks.isEmpty) {
      return CText(
        'update.body',
        size: 14,
        weight: FontWeight.w500,
        height: 20,
        align: TextAlign.center,
        color: muted,
      );
    }

    TextSpan spans(List<InlineRun> runs, TextStyle base) => TextSpan(
      style: base,
      children: [
        for (final r in runs)
          TextSpan(
            text: r.text,
            style: TextStyle(
              fontWeight: r.bold ? FontWeight.w700 : null,
              fontStyle: r.italic ? FontStyle.italic : null,
              fontFamily: r.code ? 'monospace' : null,
              decoration: TextDecoration.combine([
                if (r.underline) TextDecoration.underline,
                if (r.strike) TextDecoration.lineThrough,
              ]),
            ),
          ),
      ],
    );

    final body = TextStyle(
      fontSize: 14.ms,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      color: muted,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in blocks)
          switch (b) {
            HeadingBlock(:final level, :final runs) => Padding(
              padding: EdgeInsets.symmetric(vertical: 8.ms),
              child: Text.rich(
                spans(
                  runs,
                  TextStyle(
                    fontSize: _headingSizes[level - 1].ms,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            ParagraphBlock(:final runs) => Padding(
              padding: EdgeInsets.only(bottom: 10.ms),
              child: Text.rich(spans(runs, body), textAlign: TextAlign.center),
            ),
            ListItemBlock(:final marker, :final runs, :final depth) => Padding(
              padding: EdgeInsets.only(
                left: (10 + depth * 14).ms,
                right: 10.ms,
                bottom: 8.ms,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20.ms,
                    child: Text(
                      marker,
                      style: body.copyWith(
                        color: c.accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(child: Text.rich(spans(runs, body))),
                ],
              ),
            ),
          },
      ],
    );
  }
}
