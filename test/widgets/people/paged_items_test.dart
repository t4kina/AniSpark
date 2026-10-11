import 'package:anispark/widgets/people/paged_items.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  const _Host({required this.pages});

  final Map<int, (List<int>, bool)> pages;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with PagedLoading<_Host> {
  PagedItems<int> items = PagedItems.firstPage(const [], hasNextPage: true);
  final fetched = <int>[];

  @override
  void loadMoreIfNearEnd() => load();

  void load() => loadNextPage<int>(
        read: () => items,
        write: (value) => items = value,
        fetch: (page) async {
          fetched.add(page);
          return widget.pages[page] ?? (const <int>[], false);
        },
        merge: (shown, page) => [...shown, ...page],
        debugLabel: 'test',
      );

  @override
  Widget build(BuildContext context) => Text('${items.items}');
}

void main() {
  test('a first page without items keeps paging when the server has more', () {
    final items = PagedItems<int>.firstPage(const [], hasNextPage: true);
    expect(items.hasNextPage, isTrue);
  });

  test('withPage keeps hasNextPage for a page whose items were all filtered out', () {
    final items = PagedItems<int>.firstPage(const [1], hasNextPage: true);
    final next = items.withPage(const [1], hasNextPage: true);
    expect(next.hasNextPage, isTrue);
    expect(next.lastPage, 2);
  });

  testWidgets('keeps loading past a page that filtering emptied', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: _Host(pages: {
        2: (<int>[], true),
        3: ([7], false),
      }),
    ));
    final state = tester.state<_HostState>(find.byType(_Host));
    state.items = PagedItems.firstPage(const [1], hasNextPage: true);

    state.load();
    await tester.pump();
    await tester.pump();

    expect(state.fetched, [2, 3]);
    expect(state.items.items, [1, 7]);
    expect(state.items.hasNextPage, isFalse);
  });
}
