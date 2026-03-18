import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'app_theme.dart';
import 'router.dart';
import 'screens/home/home_screen.dart';
import 'providers/app_data_provider.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('✅ Flutter initialized');

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    debugPrint('✅ Orientation set');

    runApp(
      MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ChangeNotifierProvider(create: (_) => AppDataProvider()),
  ],
        child: const GodownApp(),
      ),
    );
    debugPrint('✅ App started');
  } catch (e, stack) {
    debugPrint('❌ main() failed: $e');
    debugPrint('$stack');
  }
}

class GodownApp extends StatelessWidget {
  const GodownApp({super.key});

  @override
  Widget build(BuildContext context) {
    try {
      final themeProvider = context.watch<ThemeProvider>();
      debugPrint('✅ ThemeProvider loaded | isReady: ${themeProvider.isReady}');

      if (!themeProvider.isReady) {
        debugPrint('⏳ Waiting for theme to load...');
        return const MaterialApp(
          home: Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        );
      }

      final lightTheme = AppTheme.light().copyWith(
        extensions: [AppThemeExtension.light()],
      );
      final darkTheme = AppTheme.dark().copyWith(
        extensions: [AppThemeExtension.dark()],
      );
      debugPrint('✅ Themes built');

      return MaterialApp(
        title: 'Godown Inventory',
        debugShowCheckedModeBanner: false,
        themeMode: themeProvider.mode,
        theme: lightTheme,
        darkTheme: darkTheme,
        home: const HomeScreen(),
        onGenerateRoute: AppRouter.onGenerateRoute,
        builder: (context, child) {
          if (child == null) {
            debugPrint('❌ builder: child is null');
            return const SizedBox.shrink();
          }
          debugPrint('✅ builder: child is ready');
          try {
            final mediaQuery = MediaQuery.of(context);
            final clampedScale = mediaQuery.textScaler
                .scale(1.0)
                .clamp(0.85, 1.2);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(clampedScale),
              ),
              child: child,
            );
          } catch (e) {
            debugPrint('❌ MediaQuery builder failed: $e');
            return child;
          }
        },
      );
    }  catch (e, stack) {
      debugPrint('❌ GodownApp.build() failed: $e');
      debugPrint('$stack');
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('App Error: $e'),
          ),
        ),
      );
    }
 
 
 
  }
}