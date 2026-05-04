// ─────────────────────────────────────────────────────────────────────────────
// join_shop_screen.dart — Phase 3 (v2.7.0)
//
// Staff join flow — enter invite code → validate → sync → LoginScreen
// Invite code format: XXX-XXX-NNNN (e.g. SBT-SIL-4821)
//
// Rules:
//   • No local write until ShopValidationResult.valid confirmed
//   • Auto-uppercase input
//   • Back to OnboardingScreen allowed
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../providers/app_data_provider.dart';
import '../../services/shop_service.dart';
import '../login/login_screen.dart';

class JoinShopScreen extends StatefulWidget {
  const JoinShopScreen({super.key});

  @override
  State<JoinShopScreen> createState() => _JoinShopScreenState();
}

class _JoinShopScreenState extends State<JoinShopScreen> {

  final _codeCtrl = TextEditingController();
  String? _error;
  bool    _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // JOIN
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _join() async {
    final code = _codeCtrl.text.trim().toUpperCase();

    if (code.isEmpty) {
      setState(() => _error = 'Enter your invite code');
      return;
    }

    // Format: XXX-XXX-NNNN
    if (!RegExp(r'^[A-Z]{3}-[A-Z]{3}-\d{4}$').hasMatch(code)) {
      setState(() => _error = 'Invalid format. Example: SBT-SIL-4821');
      return;
    }

    setState(() { _loading = true; _error = null; });

    final result = await ShopService.instance.validateInviteCode(code);

    if (!mounted) return;

    switch (result) {
      case ShopValidationResult.valid:
        await _onValidCode(code);
      case ShopValidationResult.notFound:
        setState(() {
          _loading = false;
          _error   = 'Invalid invite code. Check with your shop owner.';
        });
      case ShopValidationResult.expired:
        setState(() {
          _loading = false;
          _error   = 'Shop subscription expired. Contact your owner.';
        });
      case ShopValidationResult.suspended:
        setState(() {
          _loading = false;
          _error   = 'Shop account suspended. Contact support.';
        });
      case ShopValidationResult.networkError:
        setState(() {
          _loading = false;
          _error   = 'Check internet and try again.';
        });
    }
  }

  Future<void> _onValidCode(String shopId) async {
    try {
      // Save locally + inject singletons — AFTER validation confirmed
      await ShopService.instance.saveShopLocally(
        shopId:      shopId,
        shopName:    '',
        trialEndsAt: DateTime.now().toUtc().add(const Duration(days: 7)),
      );

      if (!mounted) return;
      final data = context.read<AppDataProvider>();
      await data.initialize();
      data.startRealtimeSync();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      debugPrint('JoinShopScreen._onValidCode error: $e');
      setState(() {
        _loading = false;
        _error   = 'Could not load shop data. Check internet and try again.';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation:       0,
        leading: IconButton(
          icon:      const Icon(Icons.arrow_back_ios_new_rounded),
          color:     t.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              Text('Join your shop',
                  style: TextStyle(fontFamily: AppFonts.sans, fontSize: 22,
                      fontWeight: FontWeight.w700, color: t.text)),

              const SizedBox(height: 6),

              Text('Enter the invite code shared by your shop owner',
                  style: TextStyle(fontFamily: AppFonts.sans, fontSize: 14,
                      color: t.text2, height: 1.4)),

              const SizedBox(height: 32),

              // ── Invite code input ────────────────────────────────────────
              TextFormField(
                controller:         _codeCtrl,
                autofocus:          true,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
                  _UpperCaseFormatter(),
                ],
                style: TextStyle(
                  fontFamily:    AppFonts.mono,
                  fontSize:      18,
                  fontWeight:    FontWeight.w600,
                  color:         t.text,
                  letterSpacing: 1.5,
                ),
                decoration: InputDecoration(
                  labelText: 'Invite code',
                  hintText:  'e.g. SBT-SIL-4821',
                  hintStyle: TextStyle(
                    fontFamily:    AppFonts.mono,
                    fontSize:      16,
                    color:         t.text3,
                    letterSpacing: 1,
                  ),
                  prefixIcon: Icon(Icons.tag_rounded, size: 18, color: t.text3),
                  errorText:  _error,
                ),
                onFieldSubmitted: (_) => _join(),
              ),

              const SizedBox(height: 6),

              Text('Format: XXX-XXX-0000',
                  style: TextStyle(fontFamily: AppFonts.sans,
                      fontSize: 11, color: t.text3)),

              const SizedBox(height: 28),

              // ── Join button ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _join,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary,
                    foregroundColor: Colors.white,
                    elevation:       0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radius)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('Join Shop',
                          style: TextStyle(fontFamily: AppFonts.sans,
                              fontSize: 15, fontWeight: FontWeight.w600,
                              color: Colors.white)),
                ),
              ),

              const Spacer(),

              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Center(
                  child: Text(
                    "Don't have a code? Ask your shop owner.",
                    style: TextStyle(fontFamily: AppFonts.sans,
                        fontSize: 12, color: t.text3),
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

// ── Auto-uppercase formatter ───────────────────────────────────────────────────
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue o, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}
