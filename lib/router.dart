import 'package:flutter/material.dart';
import 'screens/home/home_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/movement/add_movement_screen.dart';
import 'screens/stock/stock_screen.dart';
import 'screens/history/history_screen.dart';
import 'screens/sync/sync_screen.dart';
import 'screens/items/manage_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/onboarding/register_shop_screen.dart';
import 'screens/onboarding/join_shop_screen.dart';
import 'screens/feedback/feedback_screen.dart';

class AppRouter {
  static const home    = '/';
  static const login   = '/login';
  static const addMove = '/add-movement';
  static const stock   = '/stock';
  static const history = '/history';
  static const items   = '/items';
  static const sync       = '/sync';
  static const onboarding = '/onboarding';
  static const register   = '/register';
  static const join       = '/join';
  static const feedback   = '/feedback';

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    Widget page;

    switch (settings.name) {
      case home:
        page = const HomeScreen();
      case login:
        page = const LoginScreen();
      case addMove:
        page = const AddMovementScreen();
      case stock:
        page = const StockScreen();
      case history:
        page = const HistoryScreen();
      case items:
        page = const ManageScreen();
      case sync:
        page = const SyncScreen();
      case onboarding:
        page = const OnboardingScreen();
      case register:
        page = const RegisterShopScreen();
      case join:
        page = const JoinShopScreen();
      case feedback:
        page = const FeedbackScreen();
      default:
      // OAuth callback — let supabase_flutter handle it, don't push any route
        if (settings.name?.contains('code=') == true ||
            settings.name?.contains('login-callback') == true) {
          return null;
        }
        page = const HomeScreen();
    }

    // MaterialPageRoute handles theme inheritance correctly during transitions.
    // PageRouteBuilder's transitionsBuilder runs in a context outside the
    // MaterialApp subtree, causing Theme.of(context).extension() to return null.
    return MaterialPageRoute(
      settings: settings,
      builder:  (_) => page,
    );
  }
}