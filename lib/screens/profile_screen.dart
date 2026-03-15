import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/anilist_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return auth.isLoggedIn ? const _LoggedInProfile() : const _LoginPrompt();
  }
}

// ─── Login Prompt ──────────────────────────────────────────────────────────

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Icon(Icons.person, size: 50, color: Color(0xFF02A9FF)),
              ),
              const SizedBox(height: 24),
              const Text('Connect your AniList',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'Login to sync your anime list and track your progress across devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF02A9FF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    try {
                      await auth.login();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Login failed: $e')),
                        );
                      }
                    }
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.login, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Login with AniList',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Logged In Profile ─────────────────────────────────────────────────────

class _LoggedInProfile extends StatefulWidget {
  const _LoggedInProfile();

  @override
  State<_LoggedInProfile> createState() => _LoggedInProfileState();
}

class _LoggedInProfileState extends State<_LoggedInProfile> {
  final _service = AniListService();
  // AniList status → count, e.g. {'CURRENT': 5, 'COMPLETED': 20, ...}
  Map<String, int> _listCounts = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCounts());
  }

  Future<void> _fetchCounts() async {
    final auth = context.read<AuthService>();
    final userId = auth.user?['id'] as int?;
    if (userId == null || auth.token == null) return;
    final counts = await _service.getUserListCounts(userId, auth.token!);
    if (mounted) setState(() => _listCounts = counts);
  }

  int _count(String status) => _listCounts[status] ?? 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user!;
    final animeStats = user['statistics']?['anime'];
    final mangaStats = user['statistics']?['manga'];
    final avatar = user['avatar']?['large'];
    final name = user['name'] ?? 'Unknown';
    final minutesWatched = (animeStats?['minutesWatched'] as num?)?.toInt() ?? 0;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: const Color(0xFF161B22),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 20,
                right: 20,
                bottom: 24,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: const Color(0xFF21262D),
                        backgroundImage: avatar != null
                            ? CachedNetworkImageProvider(avatar)
                            : null,
                        child: avatar == null
                            ? const Icon(Icons.person, size: 36, color: Colors.grey)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            const Text('AniList Member',
                                style: TextStyle(
                                    color: Color(0xFF02A9FF), fontSize: 13)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.grey),
                        onPressed: () => _confirmLogout(context, auth),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _statBox('Anime', '${animeStats?['count'] ?? 0}'),
                      _statBox('Episodes', '${animeStats?['episodesWatched'] ?? 0}'),
                      _statBox('Score',
                          '${(animeStats?['meanScore'] ?? 0.0).toStringAsFixed(1)}'),
                      _statBox('Time', _formatTime(minutesWatched)),
                    ],
                  ),
                  if (mangaStats != null) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Color(0xFF21262D)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statBox('Manga', '${mangaStats['count'] ?? 0}'),
                        _statBox('Chapters', '${mangaStats['chaptersRead'] ?? 0}'),
                        _statBox('M. Score',
                            '${(mangaStats['meanScore'] ?? 0.0).toStringAsFixed(1)}'),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── My List summary (from AniList) ───────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('My List',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _listStatCard('Watching', _count('CURRENT'),
                          const Color(0xFF02A9FF)),
                      const SizedBox(width: 10),
                      _listStatCard('Completed', _count('COMPLETED'), Colors.green),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _listStatCard('Plan to Watch', _count('PLANNING'), Colors.orange),
                      const SizedBox(width: 10),
                      _listStatCard('Dropped', _count('DROPPED'), Colors.red),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Account section ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Account',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _settingsTile(
                    context,
                    icon: Icons.open_in_new,
                    label: 'View on AniList',
                    onTap: () {},
                  ),
                  _settingsTile(
                    context,
                    icon: Icons.logout,
                    label: 'Logout',
                    color: Colors.red,
                    onTap: () => _confirmLogout(context, auth),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      );

  Widget _listStatCard(String label, int count, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(5)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  Text(label,
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _settingsTile(BuildContext context,
      {required IconData icon,
      required String label,
      Color? color,
      required VoidCallback onTap}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color ?? Colors.grey),
        title: Text(label, style: TextStyle(color: color ?? Colors.white)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        onTap: onTap,
      );

  String _formatTime(int minutes) {
    final days = minutes ~/ (60 * 24);
    if (days > 0) return '${days}d';
    final hours = minutes ~/ 60;
    return '${hours}h';
  }

  void _confirmLogout(BuildContext context, AuthService auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              auth.logout();
              Navigator.pop(context);
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
