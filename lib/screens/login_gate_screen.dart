import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../utils/translations.dart' show tr;
import '../widgets/app_button.dart';
import '../widgets/app_logo.dart';
import '../widgets/motion/staggered_entrance.dart';

/// Shown instead of the app's tabs while signed out (see AuthGate), so the
/// bottom navigation only appears after logging in.
class LoginGateScreen extends StatefulWidget {
  const LoginGateScreen({super.key});

  static const logoSize = 96.0;

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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                // The logo arrives from the splash; the rest follows it in.
                const AppLogo(size: LoginGateScreen.logoSize),
                const SizedBox(height: 24),
                ...staggered(from: 1, [
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
                  AppButton(
                    label: tr('login_with_anilist', lang),
                    icon: Icons.login,
                    large: true,
                    expand: true,
                    // Busy also ignores taps, which is what keeps a second
                    // OAuth flow from starting.
                    busy: _loggingIn,
                    onPressed: _login,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
