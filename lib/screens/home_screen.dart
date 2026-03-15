import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../services/anilist_service.dart';
import '../widgets/anime_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = AniListService();
  List<dynamic> _trending = [];
  List<dynamic> _seasonal = [];
  List<dynamic> _popular = [];
  List<dynamic> _topAiring = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.getTrending(),
      _service.getThisSeason(),
      _service.getPopularAllTime(),
      _service.getTopAiring(),
    ]);
    setState(() {
      _trending = results[0];
      _seasonal = results[1];
      _popular = results[2];
      _topAiring = results[3];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AniSpark',
          style: TextStyle(
            color: Color(0xFF02A9FF),
            fontWeight: FontWeight.bold,
            fontSize: 24,
            letterSpacing: 1,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.grey),
            onPressed: () {},
          ),
        ],
      ),
      body: _loading
          ? _buildShimmer()
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _sectionHeader('Trending Now'),
                    const SizedBox(height: 10),
                    _buildHorizontalRow(_trending),
                    const SizedBox(height: 20),
                    _sectionHeader('This Season'),
                    const SizedBox(height: 10),
                    _buildHorizontalRow(_seasonal),
                    const SizedBox(height: 20),
                    _sectionHeader('Popular All Time'),
                    const SizedBox(height: 10),
                    _buildHorizontalRow(_popular),
                    const SizedBox(height: 20),
                    _sectionHeader('Top Airing'),
                    const SizedBox(height: 10),
                    _buildHorizontalRow(_topAiring),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );

  Widget _buildHorizontalRow(List<dynamic> items) => SizedBox(
        height: 210,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 120,
              child: AnimeCard(animeData: items[i]),
            ),
          ),
        ),
      );

  Widget _buildShimmer() => Shimmer.fromColors(
        baseColor: Colors.grey[800]!,
        highlightColor: Colors.grey[600]!,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(4, (_) => _shimmerSection()),
          ),
        ),
      );

  Widget _shimmerSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Container(
              width: 120,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 6,
              itemBuilder: (_, _) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 170,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 100,
                      height: 12,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}
