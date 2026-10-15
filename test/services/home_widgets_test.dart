import 'package:anispark/providers/settings_provider.dart';
import 'package:anispark/services/auth_service.dart';
import 'package:anispark/services/home_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Logged in as Faye until [signOut].
class _Auth extends AuthService {
  Map<String, dynamic>? _user = {'id': 7, 'name': 'Faye'};

  void signOut() {
    _user = null;
    notifyListeners();
  }

  @override
  String? get token => _user == null ? null : 'tok';

  @override
  Map<String, dynamic>? get user => _user;

  @override
  bool get isLoggedIn => _user != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    messenger.setMockMethodCallHandler(HomeWidgets.channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(HomeWidgets.channel, null));

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('tells the widgets whose list to show and the accent, then each change', () async {
    final auth = _Auth();
    final settings = SettingsProvider();

    syncHomeWidgets(auth, settings);
    await settle();
    expect(calls.single.method, 'configure');
    expect(calls.single.arguments, {'user': 'Faye', 'accent': 0xFF02A9FF});

    await settings.setAccentColor('Pink');
    await settle();
    expect(calls.last.arguments, {'user': 'Faye', 'accent': 0xFFE91E63});

    auth.signOut();
    await settle();
    expect(calls.last.arguments, {'user': null, 'accent': 0xFFE91E63});
    expect(calls, hasLength(3));
  });

  test('says nothing when what the widgets show hasn\'t changed', () async {
    final settings = SettingsProvider();

    syncHomeWidgets(_Auth(), settings);
    await settle();
    await settings.setLanguage('Español');
    await settle();

    expect(calls, hasLength(1));
  });

  test('only talks to widgets on Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    syncHomeWidgets(_Auth(), SettingsProvider());
    await settle();

    expect(calls, isEmpty);
  });

  test('keeps the app going when the widgets can\'t be reached', () async {
    messenger.setMockMethodCallHandler(HomeWidgets.channel, (_) async => throw PlatformException(code: 'gone'));

    await expectLater(HomeWidgets().sync(userName: 'Faye', accent: const Color(0xFF02A9FF)), completes);
  });
}
