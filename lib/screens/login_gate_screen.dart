import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../utils/translations.dart' show tr;

/// Shown instead of the app's tabs while signed out (see AuthGate), so the
/// bottom navigation only appears after logging in.
class LoginGateScreen extends StatefulWidget {
  const LoginGateScreen({super.key});

  @override
  State<LoginGateScreen> createState() => _LoginGateScreenState();
}

class _LoginGateScreenState extends State<LoginGateScreen> {
  // A second tap while AniList's login page is opening would start another
  // OAuth flow on top of the first.
  bool _loggingIn = false;

  Future<void> _login() async {
    final auth = context.read<AuthService>();
    final lang = context.read<SettingsProvider>().language;
    setState(() => _loggingIn = true);
    try {
      await auth.login();
    } on Exception catch (e) {
      // Details go to the log only; they can include server responses.
      debugPrint('[LoginGateScreen] Login failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('login_failed', lang))),
        );
      }
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().language;
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset('assets/logo.jpg', width: 96, height: 96, fit: BoxFit.cover),
                ),
                const SizedBox(height: 24),
                Text(
                  tr('connect_anilist', lang),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('login_description', lang),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, height: 1.5),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: accent.withValues(alpha: 0.6),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _loggingIn ? null : _login,
                    icon: _loggingIn
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      tr('login_with_anilist', lang),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
