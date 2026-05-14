// ─────────────────────────────────────────────────────────────────────────────
// onboarding_screen.dart — Phase 3 (v2.7.0)
//
// Entry point for new users — shown when no shop_id in SharedPrefs.
// Two options: Register new shop OR Join existing shop via invite code.
// No back navigation — root of onboarding flow.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../app_theme.dart';
import 'register_shop_screen.dart';
import 'join_shop_screen.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('🟣 OnboardingScreen: build() called');
    final t = context.appTheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                // ── Logo ──────────────────────────────────────────────────
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color:        t.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Text(
                      'GI',
                      style: TextStyle(
                        fontFamily:    AppFonts.sans,
                        fontSize:      26,
                        fontWeight:    FontWeight.w800,
                        color:         Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Title ─────────────────────────────────────────────────
                Text(
                  'Godown Inventory',
                  style: TextStyle(
                    fontFamily:    AppFonts.sans,
                    fontSize:      24,
                    fontWeight:    FontWeight.w700,
                    color:         t.text,
                    letterSpacing: 0.3,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  'Real-time stock tracking for your business',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize:   14,
                    color:      t.text2,
                    height:     1.4,
                  ),
                ),

                const Spacer(flex: 2),

                // ── Register button ───────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RegisterShopScreen(),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.primary,
                      foregroundColor: Colors.white,
                      elevation:       0,
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize:   15,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
                    ),
                    child: const Text('Register New Shop'),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Join button ───────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const JoinShopScreen(),
                      ),
                    ),
                     style: OutlinedButton.styleFrom(
                      foregroundColor: t.primary,
                      side:            BorderSide(color: t.border, width: 1.5),
                      textStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize:   15,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
                    ),
                    child: const Text('Join Existing Shop'),
                  ),
                ),

                const Spacer(flex: 1),

                // ── Footer ────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'By continuing you agree to our terms of service',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppFonts.sans,
                      fontSize:   11,
                      color:      t.text3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
