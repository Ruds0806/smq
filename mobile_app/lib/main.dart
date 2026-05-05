import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartqueue_rs/features/auth/login_page.dart';
import 'package:smartqueue_rs/features/history/history_page.dart';
import 'package:smartqueue_rs/features/profile/profile_page.dart';
import 'package:smartqueue_rs/features/queue/queue_dashboard_page.dart';
import 'package:smartqueue_rs/features/queue/take_queue_page.dart';
import 'package:smartqueue_rs/shared/session_store.dart';
import 'package:smartqueue_rs/shared/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set a sensible default window size on desktop platforms
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    // flutter_window in windows/runner/main.cpp already sets 1280x800
    // Nothing extra needed here unless you want to use window_manager package
  }

  final session = SessionStore();
  await session.load();

  runApp(
    ChangeNotifierProvider.value(
      value: session,
      child: const SmartQueueApp(),
    ),
  );
}

class SmartQueueApp extends StatelessWidget {
  const SmartQueueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartQueue RS',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const RootPage(),
      routes: {
        '/queue/take': (_) => const TakeQueuePage(),
        '/queue/dashboard': (_) => const QueueDashboardPage(),
        '/history': (_) => const HistoryPage(),
        '/profile': (_) => const ProfilePage(),
      },
    );
  }
}

class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    if (session.isLoggedIn) {
      return const QueueDashboardPage();
    }
    return const LoginPage();
  }
}
