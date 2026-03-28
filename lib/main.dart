import 'dart:async';
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

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final savedStaffId = await getSavedStaffId();

  // Supabase MUST init before dataProvider
  await SupabaseService.initialize();
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
        debugShowCheckedModeBanner: false,
        home: _RawSplash(),
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
          // Determine the base screen behind the overlay
          Widget baseScreen;
          if (data.isLoggedIn) {
            baseScreen = const HomeScreen();
          } else {
            baseScreen = const LoginScreen();
          }

          // Show overlay on top while loading or syncing fresh install
          final bool showOverlay = data.isLoading ||
              (!data.syncFailed && data.staff.isEmpty);

          if (data.syncFailed) {
            return _SyncErrorScreen(
              onRetry: () async {
                await data.retryInitialize();
                if (!data.syncFailed) data.startRealtimeSync();
              },
            );
          }

          // Stack the overlay on top of the real screen
          // Once data is ready the overlay fades out revealing the app
          return Stack(
            children: [
              baseScreen,
              if (showOverlay)
                _SplashOverlay(
                  attempt: data.retryAttempt,
                  max:     data.maxRetries,
                  message: data.retryMessage,
                ),
            ],
          );
        },
      ),
      onGenerateRoute: (settings) => AppRouter.onGenerateRoute(settings),
      navigatorKey: GlobalKey<NavigatorState>(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// RAW SPLASH — shown before theme loads (fraction of a second)
// Uses hardcoded primary blue — theme not available yet
// ═════════════════════════════════════════════════════════════════════════════

class _RawSplash extends StatelessWidget {
  const _RawSplash();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF2563EB),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LogoBadge(size: 72, color: Colors.white),
            SizedBox(height: 20),
            Text(
              'Godown Inventory',
              style: TextStyle(
                fontFamily:  'Inter',
                fontSize:    22,
                fontWeight:  FontWeight.w700,
                color:       Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Sri Baba Traders',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize:   13,
                color:      Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SPLASH OVERLAY — sits on top of the real app while data loads
// Fades out with AnimatedOpacity once data is ready
// ═════════════════════════════════════════════════════════════════════════════

class _SplashOverlay extends StatefulWidget {
  final int    attempt;
  final int    max;
  final String message;
  const _SplashOverlay({
    required this.attempt,
    required this.max,
    required this.message,
  });
  @override
  State<_SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<_SplashOverlay>
    with SingleTickerProviderStateMixin {

  late final AnimationController _ctrl;
  late final Animation<double>    _fade;

  @override
  void initState() {
    super.initState();
    // Fade in immediately — overlay appears as soon as it's shown
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRetrying = widget.attempt > 0;

    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: const Color(0xFF2563EB), // primary blue — always
        child: SafeArea(
          child: Column(
            children: [

              // ── Top spacer ──────────────────────────────────────────────
              const Spacer(flex: 3),

              // ── Logo + app name ─────────────────────────────────────────
              const _LogoBadge(size: 80, color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                'Godown Inventory',
                style: TextStyle(
                  fontFamily:  'Inter',
                  fontSize:    24,
                  fontWeight:  FontWeight.w700,
                  color:       Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sri Baba Traders',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize:   13,
                  color:      Colors.white70,
                ),
              ),

              // ── Bottom section — status ─────────────────────────────────
              const Spacer(flex: 2),

              // Progress indicator
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 20),

              // Status message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize:   14,
                    color:      Colors.white,
                    height:     1.5,
                  ),
                ),
              ),

              // Retry progress dots — only shown when retrying
              if (isRetrying) ...[
                const SizedBox(height: 16),
                _RetryDots(attempt: widget.attempt, max: widget.max),
              ],

              // "Keep internet on" hint
              if (isRetrying) ...[
                const SizedBox(height: 12),
                Text(
                  'Keep internet on',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize:   12,
                    color:      Colors.white.withOpacity(0.6),
                  ),
                ),
              ],

              const Spacer(flex: 1),

              // Version tag at bottom
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'v1.0.0',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize:   11,
                    color:      Colors.white.withOpacity(0.4),
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

// ── Retry progress dots ───────────────────────────────────────────────────────
class _RetryDots extends StatelessWidget {
  final int attempt;
  final int max;
  const _RetryDots({required this.attempt, required this.max});

  @override
  Widget build(BuildContext context) {
    return Row(
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
                ? Colors.white.withOpacity(0.9)
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ── Logo badge ────────────────────────────────────────────────────────────────
class _LogoBadge extends StatelessWidget {
  final double size;
  final Color  color;
  const _LogoBadge({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  size,
      height: size,
      decoration: BoxDecoration(
        color:        Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(size * 0.25),
        border: Border.all(
          color:  Colors.white.withOpacity(0.3),
          width:  1.5,
        ),
      ),
      child: Center(
        child: Text(
          'GI',
          style: TextStyle(
            fontFamily:  'Inter',
            fontSize:    size * 0.35,
            fontWeight:  FontWeight.w800,
            color:       color,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SYNC ERROR SCREEN — shown after all retries exhausted
// ═════════════════════════════════════════════════════════════════════════════

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

              // Icon
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  size:  40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),

              // Title
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

              // Description
              Text(
                'Could not connect to Supabase after multiple attempts.\nPlease check your internet connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize:   14,
                  color:      Colors.white.withOpacity(0.75),
                  height:     1.6,
                ),
              ),

              const Spacer(flex: 2),

              // Retry button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon:  const Icon(Icons.refresh_rounded, size: 20),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(
                      fontFamily:  'Inter',
                      fontSize:    16,
                      fontWeight:  FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF2563EB),
                    elevation:  0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Hint
              Text(
                'The app needs internet on first install\nto download your inventory data.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize:   12,
                  color:      Colors.white.withValues(0.5),
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