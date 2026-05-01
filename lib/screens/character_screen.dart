import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/anilist_service.dart';
import '../services/auth_service.dart';
import '../utils/refresh_notifier.dart';
import '../widgets/overlay_button.dart';
import 'detail_screen.dart';

class CharacterScreen extends StatefulWidget {
  final int characterId;
  final String? name;
  final String? imageUrl;

  const CharacterScreen({
    super.key,
    required this.characterId,
    this.name,
    this.imageUrl,
  });

  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen> {
  final _service = AniListService();
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AuthService>().token;
    final data = await _service.getCharacterDetail(widget.characterId, token);
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  Future<void> _toggleFavourite() async {
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) return;
    final ok = await _service.toggleCharacterFavourite(
        characterId: widget.characterId, token: auth.token!);
    if (ok && mounted) {
      _load();
      profileRefreshNotifier.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFav = _data?['isFavourite'] == true;
    return Scaffold(
      body: Stack(
        children: [
          _loading ? _buildShimmer() : _buildContent(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            left: 12,
            right: 12,
            child: Row(
              children: [
                overlayBtn(
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.pop(context),
                ),
                const Spacer(),
                overlayBtn(
                  icon: isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? Colors.red : Colors.white,
                  onPressed: _loading ? null : _toggleFavourite,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    final topPadding = MediaQuery.of(context).padding.top;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(height: 300 + topPadding, color: cs.surfaceContainerHighest),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            Container(height: 20, color: cs.surfaceContainerHighest),
            const SizedBox(height: 8),
            Container(height: 14, width: 120, color: cs.surfaceContainerHighest),
          ]),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final d = _data;
    if (d == null) return const Center(child: Text('Could not load character.'));

    final image = d['image']?['large'] as String? ?? widget.imageUrl;
    final name = d['name']?['full'] as String? ?? widget.name ?? '';
    final nativeName = d['name']?['native'] as String?;
    final description = (d['description'] as String? ?? '').trim();
    final gender = d['gender'] as String?;
    final age = d['age'] as String?;
    final bloodType = d['bloodType'] as String?;
    final dob = d['dateOfBirth'] as Map<String, dynamic>?;
    final dobStr = _dobStr(dob);
    final media = (d['media']?['nodes'] as List<dynamic>?) ?? [];

    final surface = Theme.of(context).colorScheme.surface;
    final topPadding = MediaQuery.of(context).padding.top;
    final cs = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        // ── Hero image card ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  child: SizedBox(
                    height: 340 + topPadding,
                    width: double.infinity,
                    child: image != null
                        ? CachedNetworkImage(
                            imageUrl: image,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            memCacheWidth: 600,
                            placeholder: (ctx, _) => Container(color: cs.surfaceContainerHighest),
                            errorWidget: (_, _, _) => Container(color: cs.surfaceContainerHighest),
                          )
                        : Container(color: cs.surfaceContainerHighest),
                  ),
                ),
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, surface.withValues(alpha: 0.5), surface],
                          stops: const [0.45, 0.75, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      if (nativeName != null) ...[
                        const SizedBox(height: 4),
                        Text(nativeName,
                            style: TextStyle(
                                fontSize: 14,
                                color: cs.onSurface.withValues(alpha: 0.55))),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Info pills ───────────────────────────────────────────────────
        if (gender != null || age != null || bloodType != null || dobStr != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (gender != null) _infoPill(Icons.person_outline_rounded, gender),
                  if (age != null) _infoPill(Icons.cake_outlined, age),
                  if (bloodType != null) _infoPill(Icons.water_drop_outlined, bloodType),
                  if (dobStr != null) _infoPill(Icons.calendar_today_outlined, dobStr),
                ],
              ),
            ),
          ),

        // ── Description ──────────────────────────────────────────────────
        if (description.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('ABOUT'),
                  const SizedBox(height: 8),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: _descExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: Text(
                      description,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.55,
                          color: cs.onSurface.withValues(alpha: 0.8)),
                    ),
                    secondChild: Text(
                      description,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.55,
                          color: cs.onSurface.withValues(alpha: 0.8)),
                    ),
                  ),
                  if (description.length > 200)
                    GestureDetector(
                      onTap: () => setState(() => _descExpanded = !_descExpanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _descExpanded ? 'Show less' : 'Read more',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

        // ── Appears in ───────────────────────────────────────────────────
        if (media.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
              child: _sectionLabel('APPEARS IN'),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 165,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: media.length,
                itemBuilder: (_, i) => _mediaCard(media[i]),
              ),
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  Widget _infoPill(IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            letterSpacing: 0.7),
      );

  Widget _mediaCard(dynamic item) {
    final m = item as Map<String, dynamic>;
    final id = m['id'] as int?;
    final image = m['coverImage']?['medium'] as String?;
    final title = (m['title']?['english'] ?? m['title']?['romaji'] ?? '') as String;
    final isAnime = m['type'] == 'ANIME';
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: id != null && isAnime
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => DetailScreen(animeId: id)))
            : null,
        child: SizedBox(
          width: 100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: image != null
                    ? CachedNetworkImage(
                        imageUrl: image,
                        width: 100,
                        height: 130,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                      )
                    : Container(
                        width: 100, height: 130,
                        color: cs.surfaceContainerHighest),
              ),
              const SizedBox(height: 4),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5)),
            ],
          ),
        ),
      ),
    );
  }

  String? _dobStr(Map<String, dynamic>? dob) {
    if (dob == null) return null;
    final month = dob['month'] as int?;
    final day = dob['day'] as int?;
    if (month == null && day == null) return null;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final m = month != null ? months[month - 1] : '';
    final d = day != null ? ' $day' : '';
    return '$m$d';
  }
}
