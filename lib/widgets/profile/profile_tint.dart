import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';

/// The deep shade of [seed] the top of a profile wears: its hue, calmed,
/// and dark enough for white text in light mode too.
Color profileTintFrom(Color seed) {
  final hsl = HSLColor.fromColor(seed);
  return hsl.withSaturation(hsl.saturation.clamp(0.2, 0.55)).withLightness(0.17).toColor();
}

/// The top of a profile before its picture's colour is known, or without one.
const profileTintFallback = Color(0xFF1F1E24);

/// Finds the main colour of the picture at a URL, or null.
typedef ProfileTintResolver = Future<Color?> Function(String imageUrl);

/// The colour of a profile's banner (or picture), found once per picture.
abstract final class ProfileTint {
  /// How a picture's colour is found. Tests swap it (see
  /// `test/flutter_test_config.dart`).
  static ProfileTintResolver resolver = _fromImage;

  static const _remembered = 40;
  static final _known = <String, Color>{};

  /// The tint of the picture at [url], when it was already found.
  static Color? known(String url) => _known[url];

  /// The tint of the picture at [url], or null when its colour can't be had.
  static Future<Color?> of(String url) async {
    final known = _known[url];
    if (known != null) return known;
    final seed = await resolver(url);
    if (seed == null) return null;
    final tint = profileTintFrom(seed);
    if (_known.length >= _remembered) _known.remove(_known.keys.first);
    _known[url] = tint;
    return tint;
  }

  @visibleForTesting
  static void forget() => _known.clear();

  static Future<Color?> _fromImage(String url) async {
    try {
      // Fidelity keeps the picture's own colour rather than a calmer one.
      final scheme = await ColorScheme.fromImageProvider(
        provider: CachedNetworkImageProvider(url, maxWidth: 200),
        brightness: Brightness.dark,
        dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      );
      return scheme.primaryContainer;
    } on Exception catch (e) {
      debugPrint('[ProfileTint] No colour for the picture: $e');
      return null;
    }
  }
}

/// The top of a profile: [slivers] (its header and what comes right after)
/// on the colour of its banner, else of its picture, which then melts into
/// the page. Inside, the app wears its dark theme, so text stays light on
/// the colour in light mode too.
class ProfileTintZone extends StatefulWidget {
  const ProfileTintZone({super.key, this.bannerUrl, this.avatarUrl, required this.slivers});

  final String? bannerUrl;
  final String? avatarUrl;
  final List<Widget> slivers;

  /// How long the colour takes to melt into the page after [slivers].
  static const fadeLength = 64.0;

  @override
  State<ProfileTintZone> createState() => _ProfileTintZoneState();
}

class _ProfileTintZoneState extends State<ProfileTintZone> {
  Color _tint = profileTintFallback;

  /// The fade's steps, eased at both ends so it has no edge.
  static final _stops = [for (var i = 0; i <= 8; i++) i / 8];
  static double _ease(double t) => t * t * t * (t * (t * 6 - 15) + 10);

  String? get _source {
    for (final url in [widget.bannerUrl, widget.avatarUrl]) {
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(ProfileTintZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bannerUrl != widget.bannerUrl || oldWidget.avatarUrl != widget.avatarUrl) _follow();
  }

  /// Takes the colour of the current picture: at once when it is known,
  /// else when found; the quiet dark until then or without one. Called from
  /// initState and didUpdateWidget, which a build always follows.
  void _follow() {
    final url = _source;
    final known = url == null ? null : ProfileTint.known(url);
    if (url == null || known != null) {
      _tint = known ?? profileTintFallback;
      return;
    }
    unawaited(ProfileTint.of(url).then((tint) {
      if (!mounted || tint == null || url != _source) return;
      setState(() => _tint = tint);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider?>();
    final outer = Theme.of(context);
    final dark = buildAppTheme(
      Brightness.dark,
      settings?.accentColor ?? outer.colorScheme.primary,
      palette: settings?.palette,
    );
    final page = outer.scaffoldBackgroundColor;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _tint),
      duration: AppMotion.of(context, AppMotion.long),
      curve: AppMotion.standard,
      builder: (context, tint, _) {
        final colour = tint ?? _tint;
        return SliverMainAxisGroup(slivers: [
          DecoratedSliver(
            decoration: BoxDecoration(color: colour),
            sliver: Theme(
              data: dark,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: dark.colorScheme.onSurface),
                child: SliverMainAxisGroup(slivers: widget.slivers),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: ProfileTintZone.fadeLength,
              child: DecoratedBox(
                key: const ValueKey('profile-tint-fade'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: _stops,
                    colors: [for (final t in _stops) Color.lerp(colour, page, _ease(t))!],
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
