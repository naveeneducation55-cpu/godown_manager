import 'package:flutter/material.dart';
import '../screens/home/home_screen.dart';
import '../screens/login/login_screen.dart';
import '../screens/movement/add_movement_screen.dart';
import '../screens/stock/stock_screen.dart';
import '../screens/history/history_screen.dart';
import '../screens/items/items_screen.dart';   // <-- updated
import '../screens/sync/sync_screen.dart';

class AppRouter {
  static const home    = '/';
  static const login   = '/login';
  static const addMove = '/add-movement';
  static const stock   = '/stock';
  static const history = '/history';
  static const items   = '/items';     // now opens ManageScreen
  static const sync    = '/sync';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
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
        page = const ManageScreen();   // <-- 3-tab manage screen
      case sync:
        page = const SyncScreen();
      default:
        page = const HomeScreen();
    }

    return PageRouteBuilder(
      settings:   settings,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
        child:   child,
      ),
      transitionDuration: const Duration(milliseconds: 160),
    );
  }
}