import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../utils/translations.dart';

/// The pages of a list loaded so far, for lists that load more on scroll.
@immutable
class PagedItems<T> {
  const PagedItems({
    this.items = const [],
    this.lastPage = 0,
    this.hasNextPage = false,
    this.loading = false,
    this.failed = false,
  });

  /// A list whose first page is [items]. [hasNextPage] must already be false
  /// for a page AniList returned empty (the people models do that), but not
  /// for one whose entries were all filtered out.
  const PagedItems.firstPage(List<T> items, {required bool hasNextPage})
      : this(items: items, lastPage: 1, hasNextPage: hasNextPage);

  final List<T> items;
  final int lastPage;
  final bool hasNextPage;
  final bool loading;

  /// The last attempt to load the next page failed; it waits for a retry.
  final bool failed;

  int get nextPage => lastPage + 1;

  bool get canLoadMore => hasNextPage && !loading && !failed;

  PagedItems<T> _copy({required bool loading, required bool failed}) => PagedItems(
        items: items,
        lastPage: lastPage,
        hasNextPage: hasNextPage,
        loading: loading,
        failed: failed,
      );

  PagedItems<T> started() => _copy(loading: true, failed: false);

  PagedItems<T> stoppedWithError() => _copy(loading: false, failed: true);

  /// After loading [nextPage]: [merged] is every item shown so far. Whether
  /// the list goes on is [hasNextPage]; deciding that an empty page ends it
  /// is up to the page models, which can tell a page AniList returned empty
  /// from one whose entries were all filtered out.
  PagedItems<T> withPage(List<T> merged, {required bool hasNextPage}) =>
      PagedItems(items: merged, lastPage: nextPage, hasNextPage: hasNextPage);
}

/// Loads the next pages of [PagedItems] lists held by a [State]. Pages that
/// arrive after [resetPaging] (e.g. after a refresh replaced the lists) are
/// dropped.
mixin PagedLoading<W extends StatefulWidget> on State<W> {
  int _pagingGeneration = 0;

  /// Called after a page is shown, to keep loading while the list doesn't
  /// reach the end of the screen.
  void loadMoreIfNearEnd();

  void resetPaging() => _pagingGeneration++;

  /// Loads the page after [read]'s last one with [fetch] and stores the
  /// result, [merge]d with what was shown, through [write]. Does nothing
  /// while a page is loading, at the end, or after a failure unless [retry].
  Future<void> loadNextPage<T>({
    required PagedItems<T> Function() read,
    required void Function(PagedItems<T> value) write,
    required Future<(List<T>, bool)> Function(int page) fetch,
    required List<T> Function(List<T> shown, List<T> page) merge,
    required String debugLabel,
    bool retry = false,
  }) async {
    final current = read();
    if (!mounted || current.loading || !current.hasNextPage || (current.failed && !retry)) return;
    final generation = _pagingGeneration;
    final page = current.nextPage;
    setState(() => write(current.started()));
    try {
      final (items, hasNextPage) = await fetch(page);
      if (!mounted || generation != _pagingGeneration) return;
      setState(() {
        final latest = read();
        write(latest.withPage(merge(latest.items, items), hasNextPage: hasNextPage));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) loadMoreIfNearEnd();
      });
    } on Exception catch (e) {
      debugPrint('[$debugLabel] Loading page $page failed: $e');
      if (mounted && generation == _pagingGeneration) setState(() => write(read().stoppedWithError()));
    }
  }
}

/// The end of a list that loads more on scroll: a spinner while there's
/// more, a retry button after a failure.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({super.key, required this.hasMore, required this.failed, required this.onRetry});

  final bool hasMore;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      final lang = context.watch<SettingsProvider>().language;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          children: [
            Text(tr('load_error', lang), style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(tr('retry', lang)),
            ),
          ],
        ),
      );
    }
    if (!hasMore) return const SizedBox(height: 32);
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}
