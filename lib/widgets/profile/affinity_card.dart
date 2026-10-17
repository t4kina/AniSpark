import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../screens/compare_screen.dart';
import '../../services/affinity_api.dart';
import '../../services/api_cache.dart';
import '../../services/auth_service.dart';
import '../../utils/affinity.dart';
import '../../utils/translations.dart';
import '../skeletons.dart';
import 'affinity_ring.dart';

/// AFFINITY on another user's profile: how close the viewer's taste is to
/// theirs, for anime and for manga, each opening a [CompareScreen].
///
/// Only shown to a logged-in viewer on someone else's profile. It loads
/// after the profile is on screen and fails quietly into a retry, so the
/// profile never waits on it.
class AffinityCard extends StatefulWidget {
  const AffinityCard({super.key, required this.userId, required this.userName, this.api});

  final int userId;
  final String userName;

  /// Injected by tests; a default one is created otherwise.
  final AffinityApi? api;

  @override
  State<AffinityCard> createState() => _AffinityCardState();
}

sealed class _Load {
  const _Load();
}

final class _Loading extends _Load {
  const _Loading();
}

final class _Loaded extends _Load {
  const _Loaded(this.affinity);

  final Affinity affinity;
}

final class _Failed extends _Load {
  const _Failed();
}

final class _Private extends _Load {
  const _Private();
}

class _AffinityCardState extends State<AffinityCard> {
  static const _types = ['ANIME', 'MANGA'];

  // Scores change rarely; a recent comparison is shown without refetching.
  static const _maxAge = Duration(minutes: 30);

  late final AffinityApi _api = widget.api ?? AffinityApi();
  Map<String, _Load> _loads = const {};

  /// The viewer the current [_loads] belong to.
  int? _loadedFor;

  @override
  void didUpdateWidget(AffinityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _loadedFor = null;
      _loads = const {};
    }
  }

  static int? _viewerIdOf(AuthService auth) {
    if (!auth.isLoggedIn) return null;
    final id = auth.user?['id'];
    return id is int ? id : null;
  }

  /// Starts over for [viewerId] once the current frame is on screen, so the
  /// profile is never held up by these requests.
  void _startLoading(int viewerId) {
    _loadedFor = viewerId;
    _loads = const {};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadedFor != viewerId) return;
      for (final type in _types) {
        unawaited(_load(type));
      }
    });
  }

  Future<void> _load(String type, {bool force = false}) async {
    final viewerId = _loadedFor;
    final otherId = widget.userId;
    final token = context.read<AuthService>().token;
    if (viewerId == null || token == null) return;
    final cache = context.read<ApiCache>();
    final key = ApiCache.userKey(viewerId, 'affinity:$otherId:$type');
    bool isCurrent() => mounted && _loadedFor == viewerId && widget.userId == otherId;
    var shown = false;
    try {
      await cache.load<List<SharedTitle>>(
        key: key,
        fetch: () => _api.fetchShared(viewerId: viewerId, otherId: otherId, type: type, token: token),
        decode: SharedTitle.listFromJson,
        maxAge: _maxAge,
        force: force,
        onData: (shared, {required isFresh}) {
          if (!isCurrent()) return;
          shown = true;
          _set(type, _Loaded(Affinity.of(shared)));
        },
      );
    } on AffinityUnavailableException catch (e) {
      debugPrint('[AffinityCard] The $type list of $otherId is unavailable: $e');
      if (isCurrent()) _set(type, const _Private());
      try {
        // Titles from a list that has since gone private aren't kept.
        await cache.remove(key);
      } on Exception catch (e) {
        debugPrint('[AffinityCard] Forgetting the cached $type comparison failed: $e');
      }
    } on Exception catch (e) {
      debugPrint('[AffinityCard] Loading the $type affinity with $otherId failed: $e');
      // A cached comparison already on screen is better than an error.
      if (isCurrent() && !shown) _set(type, const _Failed());
    }
  }

  void _set(String type, _Load load) => setState(() => _loads = {..._loads, type: load});

  void _retry(Iterable<String> types) {
    final retried = types.toList();
    setState(() => _loads = {..._loads, for (final type in retried) type: const _Loading()});
    for (final type in retried) {
      unawaited(_load(type, force: true));
    }
  }

  void _openCompare(String type, Affinity affinity) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CompareScreen(affinity: affinity, userName: widget.userName, type: type),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final viewerId = context.select<AuthService, int?>(_viewerIdOf);
    if (viewerId == null || viewerId == widget.userId) return const SizedBox.shrink();
    if (_loadedFor != viewerId) _startLoading(viewerId);

    final lang = context.watch<SettingsProvider>().language;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outline),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  tr('affinity_title', lang),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ..._rows(lang),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _rows(String lang) {
    final loads = [for (final type in _types) (type: type, load: _loads[type] ?? const _Loading())];
    // A private profile hides both lists, so one message covers the card.
    if (loads.any((entry) => entry.load is _Private)) {
      return [_Message(icon: Icons.lock_outline_rounded, text: tr('affinity_private', lang))];
    }
    // A media type with nothing in common gets no row.
    final shown = [for (final entry in loads) if (!_isEmpty(entry.load)) entry];
    if (shown.isEmpty) {
      return [_Message(icon: Icons.people_outline_rounded, text: tr('affinity_no_titles_in_common', lang))];
    }
    // Offline, everything fails at once: one retry covers it.
    if (shown.every((entry) => entry.load is _Failed)) {
      return [
        _FailedRow(
          text: tr('load_error', lang),
          onRetry: () => _retry([for (final entry in shown) entry.type]),
        ),
      ];
    }
    return [
      for (final (:type, :load) in shown)
        switch (load) {
          _Loading() || _Private() => const _RowSkeleton(),
          _Failed() => _FailedRow(
              text: '${_typeLabel(type, lang)} · ${tr('load_error', lang)}',
              onRetry: () => _retry([type]),
            ),
          _Loaded(:final affinity) => _AffinityRow(
              type: type,
              affinity: affinity,
              onCompare: () => _openCompare(type, affinity),
            ),
        },
    ];
  }
}

bool _isEmpty(_Load load) => load is _Loaded && load.affinity.shared.isEmpty;

String _typeLabel(String type, String lang) => tr(type == 'MANGA' ? 'nav_manga' : 'nav_anime', lang);

/// One media type's affinity: ring, verdict and count, opening the
/// comparison.
class _AffinityRow extends StatelessWidget {
  const _AffinityRow({required this.type, required this.affinity, required this.onCompare});

  final String type;
  final Affinity affinity;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final cs = Theme.of(context).colorScheme;
    final percent = affinity.percent;
    final color = affinityTierColor(affinity.tier);
    final typeLabel = _typeLabel(type, lang);
    final headline = affinityHeadline(affinity, lang);
    final count = titlesInCommonText(affinity.shared.length, lang);
    final compare = tr('affinity_compare', lang);
    return Semantics(
      button: true,
      label: [typeLabel, if (percent != null) '$percent%', headline, count, compare].join(', '),
      excludeSemantics: true,
      onTap: onCompare,
      child: InkWell(
        onTap: onCompare,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              AffinityRing(percent: percent, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(typeLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      count,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(compare, style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right_rounded, size: 16, color: cs.primary),
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

class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    return Row(
      children: [
        const Icon(Icons.wifi_off_rounded, size: 18, color: Colors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        IconButton(
          onPressed: onRetry,
          tooltip: tr('retry', lang),
          icon: const Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey))),
          ],
        ),
      );
}

/// Placeholder shaped like an [_AffinityRow].
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) => const Skeleton(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SkeletonBox(width: 52, height: 52, radius: 26),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 64, height: 12),
                  SizedBox(height: 6),
                  SkeletonBox(width: 120, height: 10),
                  SizedBox(height: 6),
                  SkeletonBox(width: 96, height: 10),
                ],
              ),
            ],
          ),
        ),
      );
}
