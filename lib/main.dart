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
import 'services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final savedStaffId = await getSavedStaffId();

  await SupabaseService.initialize();
debugPrint('=== KEY: ${AppConfig.supabaseAnonKey.length} chars, enabled: ${AppConfig.isSyncEnabled}');
  final dataProvider = AppDataProvider();
  // await dataProvider.initialize();
  dataProvider.startRealtimeSync();
  dataProvider.initialize();
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

class _GodownAppState extends State<GodownApp> with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
      WidgetsBinding.instance.addObserver(this);
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed — reconnecting realtime + push + pull');
      SyncService.instance.reconnectRealtime();
      SyncService.instance.pushNow();
      // Pull missed changes after push completes
      Future.delayed(const Duration(seconds: 5),
          SyncService.instance.backgroundPullAll);
    }
  }


  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    if (!themeProvider.isReady) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF2563EB),
          body: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
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
          if (data.isLoading) {
            return _SyncLoadingScreen(
              message: data.retryMessage,
              attempt: data.retryAttempt,
              max:     data.maxRetries,
            );
          }          if (data.syncFailed) {
            return _SyncErrorScreen(
              onRetry: () async {
                await data.retryInitialize();
                if (!data.syncFailed) data.startRealtimeSync();
              },
            );
          }
          if (data.isLoggedIn) return const HomeScreen();
          return const LoginScreen();
        },
      ),
      onGenerateRoute: (settings) => AppRouter.onGenerateRoute(settings),
      navigatorKey: GlobalKey<NavigatorState>(),
    );
  }
}

class _SyncLoadingScreen extends StatelessWidget {
  final String message;
  final int    attempt;
  final int    max;
  const _SyncLoadingScreen({
    required this.message,
    required this.attempt,
    required this.max,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2563EB),
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color:        Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'SBT',
                    style: TextStyle(
                      fontFamily:    'Inter',
                      fontSize:      28,
                      fontWeight:    FontWeight.w800,
                      color:         Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Godown Inventory',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily:    'Inter',
                  fontSize:      24,
                  fontWeight:    FontWeight.w700,
                  color:         Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sri Baba Traders',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize:   13,
                  color:      Colors.white70,
                ),
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: 28, height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize:   14,
                    color:      Colors.white,
                    height:     1.5,
                  ),
                ),
              ),
              if (attempt > 0) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(max, (i) {
                    final done    = i < attempt;
                    final current = i == attempt - 1;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width:  current ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: done
                            ? Colors.white.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  'Keep internet on',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize:   12,
                    color:      Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
              const Spacer(flex: 1),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'v2.5.0',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize:   11,
                    color:      Colors.white.withValues(alpha: 0.4),
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


class _SyncErrorScreen extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _SyncErrorScreen({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2563EB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color:        Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size:  40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Cannot reach server',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily:  'Inter',
                  fontSize:    22,
                  fontWeight:  FontWeight.w700,
                  color:       Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Could not connect after multiple attempts.\nCheck internet and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize:   14,
                  color:      Colors.white.withValues(alpha: 0.75),
                  height:     1.6,
                ),
              ),
              const Spacer(flex: 2),
              SizedBox(
                width:  double.infinity,
                height: 52,
                child: ElevatedButton.icon(
  onPressed: onRetry,
  icon: const Icon(Icons.refresh_rounded, size: 20),
  label: const Text(
    'Try Again',
    style: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  ),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: const Color(0xFF2563EB),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  ),
),
              ),
              const SizedBox(height: 16),
              Text(
                'The app needs internet on first install\nto download your inventory data.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize:   12,
                  color:      Colors.white.withValues(alpha: 0.5),
                  height:     1.5,
                ),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }
}