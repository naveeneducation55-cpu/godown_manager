import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'providers/app_data_provider.dart';
import 'app_theme.dart';
import 'router.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final savedStaffId = await getSavedStaffId();
final dataProvider = AppDataProvider();
await dataProvider.initialize();

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
  final int? savedStaffId;
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

    // Build themes once — extensions registered here
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
    if (widget.savedStaffId != null && data.isLoggedIn) {
      return const HomeScreen();
    }
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