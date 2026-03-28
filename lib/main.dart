import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'providers/app_data_provider.dart';
import 'app_theme.dart';
import 'router.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'services/supabase_service.dart';
import 'config/app_config.dart';

void main() async {

  WidgetsFlutterBinding.ensureInitialized();
// ADD TEMPORARILY — remove after confirming
debugPrint('=== SYNC ENABLED: ${AppConfig.isSyncEnabled}');
debugPrint('=== URL: "${AppConfig.supabaseUrl}"');
debugPrint('=== KEY LENGTH: ${AppConfig.supabaseAnonKey}');
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final savedStaffId = await getSavedStaffId();

  // Initialize DB and load all data BEFORE runApp
   // Supabase MUST init before dataProvider so firstSyncFromRemote() works
  await SupabaseService.initialize();       // MUST be first
  final dataProvider = AppDataProvider();
  await dataProvider.initialize();
  dataProvider.startRealtimeSync();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AppDataProvider>.value(value: dataProvider),
      ],
      child: GodownApp(savedStaffId: savedStaffId),
    ),
  );
}

class GodownApp extends StatefulWidget {
  final String? savedStaffId;
  const GodownApp({super.key, this.savedStaffId});
  @override
  State<GodownApp> createState() => _GodownAppState();
}

class _GodownAppState extends State<GodownApp> {

  @override
  void initState() {
    super.initState();
    if (widget.savedStaffId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final data   = context.read<AppDataProvider>();
        final exists = data.staff.any((s) => s.id == widget.savedStaffId);
        if (exists) {
          data.loginWithoutPin(staffId: widget.savedStaffId!);
        } else {
          clearSavedStaffId();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    if (!themeProvider.isReady) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    final lightTheme = AppTheme.light()
        .copyWith(extensions: <ThemeExtension<dynamic>>[AppThemeExtension.light()]);
    final darkTheme = AppTheme.dark()
        .copyWith(extensions: <ThemeExtension<dynamic>>[AppThemeExtension.dark()]);

    return MaterialApp(
      title:                     'Godown Inventory',
      debugShowCheckedModeBanner: false,
      themeMode:                 themeProvider.mode,
      theme:                     lightTheme,
      darkTheme:                 darkTheme,
      home: Consumer<AppDataProvider>(
        builder: (context, data, _) {
          debugPrint('=== SYNC ENABLED: ${AppConfig.isSyncEnabled}');
          debugPrint('=== URL: "${AppConfig.supabaseUrl}"');
          debugPrint('=== Staff: ${data.staff.length}  Items: ${data.items.length}  Movements: ${data.totalMovements}');
          debugPrint('=== Loading: ${data.isLoading}  SyncFailed: ${data.syncFailed}');
          if (data.isLoading)   return _SyncLoadingScreen(message: data.retryMessage, attempt: data.retryAttempt, max: data.maxRetries);
          if (data.syncFailed)  return _SyncErrorScreen(onRetry: () async { await data.retryInitialize(); if (!data.syncFailed) data.startRealtimeSync(); });
          if (data.isLoggedIn)  return const HomeScreen();
          return const LoginScreen();
        },
      ),
      onGenerateRoute: (settings) {
        final route = AppRouter.onGenerateRoute(settings);
        return route;
      },
      navigatorKey: GlobalKey<NavigatorState>(),
    );
  }
}

class _SyncLoadingScreen extends StatelessWidget {
  final String message;
  final int attempt, max;
  const _SyncLoadingScreen({required this.message, required this.attempt, required this.max});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          if (attempt > 0) ...[
            const SizedBox(height: 8),
            Text('Keep internet on', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ],
        ]),
      ),
    ),
  );
}

class _SyncErrorScreen extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _SyncErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.red),
          const SizedBox(height: 24),
          const Text('Cannot reach server', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Could not connect after 20 attempts.\nCheck internet and try again.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(height: 32),
          ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
        ]),
      ),
    ),
  );
}