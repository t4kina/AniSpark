import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../utils/translations.dart' show tr;

/// Shown instead of MainNavigation while the user is signed out, so the
/// bottom navigation bar and its tabs only appear after login.
class LoginGateScreen extends StatelessWidget {
  const LoginGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final lang = context.watch<SettingsProvider>().language;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/logo.jpg',
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  tr('connect_anilist', lang),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
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
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      try {
                        await auth.login();
                      } on Exception catch (e) {
                        debugPrint('[LoginGateScreen] Login failed: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(tr('login_failed', lang))),
                          );
                        }
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.login, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(tr('login_with_anilist', lang),
                            style: const TextStyle(
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
      ),
    );
  }
}
