import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../../core/analytics/screen_tracker.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/utils/log.dart';
import '../../../core/utils/scale.dart';
import '../../api/host_status/host_status_api.dart';
import '../../api/host_status/host_status_models.dart';
import '../../api/host_status/host_status_queries.dart';
import '../../component/c_image.dart';
import '../../component/c_text.dart';
import '../../component/pressable.dart';

/// Plays statuses the way people already know from WhatsApp: a bar fills as
/// each clip plays; tap the right side for the next, the left for the one
/// before; hold to pause; swipe sideways between hosts; swipe down to close.
/// Under someone else's: Visit profile (the viewer closes and returns that
/// host). Each clip is reported as watched once it starts, which greys the
/// ring on Home and counts towards the host's views.
///
/// One video player at a time, as in the profile's viewer: several open
/// decoders on a cheap Android phone (most of this audience) is a stutter.
class StatusStoryViewer extends StatefulWidget {
  const StatusStoryViewer({
    super.key,
    required this.groups,
    this.initialGroup = 0,
    this.own = false,
  });

  final List<StatusGroup> groups;
  final int initialGroup;

  /// The host's own statuses: no Visit profile, nothing reported as watched.
  final bool own;

  /// Opens the viewer. Resolves with the host whose profile to open (Visit
  /// profile), or null when it was just closed.
  static Future<StatusHost?> open(
    BuildContext context, {
    required List<StatusGroup> groups,
    int initialGroup = 0,
    bool own = false,
  }) {
    if (groups.isEmpty) return Future.value();
    return Navigator.of(context, rootNavigator: true).push<StatusHost>(
      PageRouteBuilder<StatusHost>(
        settings: ScreenTracker.sheet('status_viewer'),
        pageBuilder: (_, _, _) => StatusStoryViewer(
          groups: groups,
          initialGroup: initialGroup.clamp(0, groups.length - 1),
          own: own,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<StatusStoryViewer> createState() => _StatusStoryViewerState();
}

class _StatusStoryViewerState extends State<StatusStoryViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initialGroup,
  );
  late int _group = widget.initialGroup;
  late int _item = _startOf(_group);
  VideoPlayerController? _player;
  bool _failed = false;
  bool _held = false; // finger down: paused
  bool _away = false; // the app is in the background
  int _token = 0; // the clip on screen; a stale load or tick is ignored
  int? _finished; // the token whose clip already moved on
  bool _closing = false; // popped once; nothing may pop again
  late final AppLifecycleListener _lifecycle;

  StatusGroup get _current => widget.groups[_group];

  int _startOf(int group) =>
      widget.groups[group].firstUnseen(StatusSeen.ids.value);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _away = true;
        _player?.pause();
      },
      onShow: () {
        _away = false;
        _resume();
      },
    );
    _load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _pages.dispose();
    final player = _player;
    _player = null;
    player?.removeListener(_tick);
    player?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_token;
    final previous = _player;
    _player = null;
    _failed = false;
    previous?.removeListener(_tick);
    if (mounted) setState(() {});
    // Released in the background: the next clip starts loading at once.
    unawaited(previous?.dispose());

    final status = _current.statuses[_item];
    final next = VideoPlayerController.networkUrl(Uri.parse(status.media));
    try {
      await next.initialize();
    } catch (e) {
      Log.d('StatusStory', 'clip unavailable: $e');
      await next.dispose();
      if (!mounted || token != _token) return;
      setState(() => _failed = true);
      // A clip that will not play (expired since, or no network) does not
      // hold up the rest.
      Timer(const Duration(seconds: 2), () {
        if (mounted && token == _token) _next();
      });
      return;
    }
    if (!mounted || token != _token) {
      await next.dispose();
      return;
    }
    next.addListener(_tick);
    setState(() => _player = next);
    _watched(status);
    if (!_held && !_away) await next.play();
  }

  void _watched(HostStatus status) {
    StatusSeen.mark(status.documentId);
    if (widget.own) return;
    unawaited(
      HostStatusApi.recordView(
        hostDocumentId: _current.host.expertDocumentId,
        statusDocumentId: status.documentId,
      ).catchError((Object e) => Log.d('StatusStory', 'view not sent: $e')),
    );
  }

  void _tick() {
    final p = _player;
    if (p == null || !p.value.isInitialized || !mounted) return;
    final duration = p.value.duration;
    if (duration > Duration.zero &&
        p.value.position >= duration &&
        _finished != _token) {
      _finished = _token;
      // Not from inside the player's own notification: moving on disposes
      // that player, which a ChangeNotifier must never do mid-notify.
      final token = _token;
      scheduleMicrotask(() {
        if (mounted && token == _token) _next();
      });
      return;
    }
    setState(() {});
  }

  void _resume() {
    final p = _player;
    if (p != null && !_held && !_away && p.value.isInitialized) p.play();
  }

  void _hold(bool down) {
    _held = down;
    down ? _player?.pause() : _resume();
  }

  void _next() {
    if (_closing) return;
    if (_item < _current.statuses.length - 1) {
      setState(() => _item++);
      _load();
    } else if (_group < widget.groups.length - 1) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } else {
      _close();
    }
  }

  void _previous() {
    if (_closing) return;
    if (_item > 0) {
      setState(() => _item--);
      _load();
    } else if (_group > 0) {
      _pages.previousPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    } else {
      _load(); // the first one again, from the start
    }
  }

  /// Once only. A clip that ends during the closing fade (or a tap racing
  /// it) must not pop again: that would close the screen under the viewer.
  void _close([StatusHost? visit]) {
    if (!mounted || _closing) return;
    _closing = true;
    _token++; // stale loads and ticks stop here
    _player?.pause();
    Navigator.of(context).pop(visit);
  }

  double _progress(int index) {
    if (index < _item) return 1;
    if (index > _item) return 0;
    final p = _player;
    if (p == null || !p.value.isInitialized) return 0;
    final total = p.value.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (p.value.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final width = MediaQuery.sizeOf(context).width;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The near edge goes back, the rest goes on (mirrored right to left).
          onTapUp: (d) {
            final nearStart = rtl
                ? d.localPosition.dx > width * 0.7
                : d.localPosition.dx < width * 0.3;
            nearStart ? _previous() : _next();
          },
          onLongPressStart: (_) => _hold(true),
          onLongPressEnd: (_) => _hold(false),
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 300) _close();
          },
          child: PageView.builder(
            controller: _pages,
            reverse: rtl,
            itemCount: widget.groups.length,
            onPageChanged: (i) {
              setState(() {
                _group = i;
                _item = _startOf(i);
              });
              _load();
            },
            itemBuilder: (_, i) => i == _group
                ? _page(context)
                : _Placeholder(host: widget.groups[i].host),
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context) {
    final group = _current;
    final status = group.statuses[_item];
    final player = _player;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_failed)
          const Center(
            child: CText(
              'listing:status.unavailable',
              size: 13,
              color: Colors.white70,
            ),
          )
        else if (player == null)
          const Center(child: CircularProgressIndicator(color: Colors.white))
        else
          Center(
            child: AspectRatio(
              aspectRatio: player.value.aspectRatio,
              child: VideoPlayer(player),
            ),
          ),
        // Keeps the bars and the name readable over a bright clip.
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 150,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(10.ms, 8.ms, 10.ms, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    for (var k = 0; k < group.statuses.length; k++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 2.ms),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: _progress(k),
                              minHeight: 3,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 10.ms),
                _Header(
                  host: group.host,
                  at: status.recordedAt,
                  onClose: _close,
                ),
              ],
            ),
          ),
        ),
        if (!widget.own)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: 18.ms),
                child: Center(
                  child: Pressable(
                    key: const ValueKey('status-visit-profile'),
                    onPressed: () => _close(group.host),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 18.ms,
                        vertical: 11.ms,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24.ms),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.user,
                            size: 16.ms,
                            color: Colors.black87,
                          ),
                          SizedBox(width: 6.ms),
                          const CText(
                            'home:statuses.visit',
                            size: 13,
                            weight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.host, required this.at, required this.onClose});

  final StatusHost host;
  final DateTime? at;
  final VoidCallback onClose;

  String _ago(BuildContext context) {
    final when = at;
    if (when == null) return '';
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return context.t('home:statuses.just_now');
    if (diff.inMinutes < 60) {
      return context.t(
        'home:statuses.minutes_ago',
        variables: {'count': diff.inMinutes},
      );
    }
    return context.t(
      'home:statuses.hours_ago',
      variables: {'count': diff.inHours},
    );
  }

  @override
  Widget build(BuildContext context) {
    final ago = _ago(context);
    return Row(
      children: [
        CAvatar(url: host.avatarUrl, name: host.name, size: 34.ms),
        SizedBox(width: 10.ms),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: CText.raw(
                      host.name,
                      size: 14,
                      weight: FontWeight.w700,
                      color: Colors.white,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (host.verified) ...[
                    SizedBox(width: 4.ms),
                    Icon(
                      LucideIcons.badgeCheck,
                      size: 14.ms,
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
              if (ago.isNotEmpty)
                CText.raw(ago, size: 11, color: Colors.white70, maxLines: 1),
            ],
          ),
        ),
        Pressable(
          key: const ValueKey('status-close'),
          onPressed: onClose,
          child: Padding(
            padding: EdgeInsets.all(6.ms),
            child: Icon(LucideIcons.x, size: 22.ms, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// A neighbouring host while the swipe is under way: their photo, no player.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.host});
  final StatusHost host;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: Center(
      child: CAvatar(url: host.avatarUrl, name: host.name, size: 72.ms),
    ),
  );
}
