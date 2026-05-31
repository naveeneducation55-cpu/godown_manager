// ─────────────────────────────────────────────────────────────────────────────
// register_shop_screen.dart — Phase 3 (v2.7.0)
//
// Registration flow:
//   Step 1 — Google Sign-In (identity verification)
//   Step 2 — Shop details (owner name, shop name, city)
//   Step 3 — Admin PIN setup
//
// Navigation rules:
//   Step 1 (google) ← back to OnboardingScreen (allowed)
//   Step 2 (details) → NO back (Google verified)
//   Step 3 (pin)    → NO back, NO skip
//
// resumeFromPin: true — used when app killed after shop created but before PIN
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../providers/app_data_provider.dart';
import '../../services/shop_service.dart';
import '../../services/remote_config_service.dart';
import '../../services/oauth_result.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/login/login_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';


class RegisterShopScreen extends StatefulWidget {
  final bool resumeFromPin;
  const RegisterShopScreen({super.key, this.resumeFromPin = false});

  @override
  State<RegisterShopScreen> createState() => _RegisterShopScreenState();
}

enum _Step { google, details, pin }

class _RegisterShopScreenState extends State<RegisterShopScreen> {

  _Step _step = _Step.google;

  // ── Step 1 — Google Sign-In ───────────────────────────────────────────────
  bool    _signingIn   = false;
  String? _googleError;

  // ── Step 3 — details ──────────────────────────────────────────────────────
  final _ownerCtrl = TextEditingController();
  final _shopCtrl  = TextEditingController();
  final _cityCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _detailsError;
  String  _previewId = '';

  // ── Step 3 — PIN ──────────────────────────────────────────────────────────
  String  _pin1        = '';
  String  _pin2        = '';
  bool    _confirmMode = false;
  bool    _agreedToTerms       = false;
  bool    _shopCreationStarted = false;
  AppDataProvider? _dataProvider;
  String? _pinError;
  bool    _creating    = false;

  static const _pinKeys = ['1','2','3','4','5','6','7','8','9','','0','⌫'];

  @override
   void initState() {
    super.initState();
    if (widget.resumeFromPin) _step = _Step.pin;
    _shopCtrl.addListener(_updatePreview);
    _cityCtrl.addListener(_updatePreview);
    _phoneCtrl.addListener(_updatePreview);  // triggers button lock recheck
   WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  _dataProvider = context.read<AppDataProvider>();
  debugPrint('RegisterShopScreen: attaching oauthNotifier listener');
  _dataProvider!.oauthNotifier.addListener(_onOAuthResult);
});
  }

  @override
  void dispose() {
    // Remove OAuth listener and clear state when leaving registration
    debugPrint('🟣 RegisterShopScreen: dispose() called — step=$_step');
  _dataProvider?.oauthNotifier.removeListener(_onOAuthResult);
  _dataProvider?.clearOAuthState();
  _dataProvider?.stopOAuthListener();
  _dataProvider = null;
    _previewDebounce?.cancel();
    _ownerCtrl.dispose();
    _shopCtrl.dispose();
    _cityCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Timer? _previewDebounce;
  void _updatePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final name = _shopCtrl.text.trim();
      final city = _cityCtrl.text.trim();
      if (name.isEmpty || city.isEmpty) { setState(() => _previewId = ''); return; }
      final code = ShopService.instance.extractShopCode(name);
      final loc  = ShopService.instance.extractCityCode(city);
      setState(() => _previewId = '$code-$loc-XXXX');
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return PopScope(
      canPop: _step == _Step.google,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: _step == _Step.google
            ? AppBar(
                backgroundColor: t.bg,
                elevation:       0,
                leading: IconButton(
                  icon:  const Icon(Icons.arrow_back_ios_new_rounded),
                  color: t.text,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              )
            : null,
        body: SafeArea(child: _buildStep(t)),
      ),
    );
  }

  Widget _buildStep(AppThemeExtension t) {
    switch (_step) {
      case _Step.google:  return _buildGoogle(t);
      case _Step.details: return _buildDetails(t);
      case _Step.pin:     return _buildPin(t);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1 — GOOGLE SIGN-IN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGoogle(AppThemeExtension t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // Icon
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color:        t.surface,
              borderRadius: BorderRadius.circular(16),
              border:       Border.all(color: t.border, width: 1),
            ),
            child: Icon(Icons.storefront_outlined, size: 32, color: t.primary),
          ),

          const SizedBox(height: 20),

          Text('Create your shop',
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 22,
                  fontWeight: FontWeight.w700, color: t.text)),

          const SizedBox(height: 8),

          Text(
            'Sign in with Google to verify your identity\nand set up your shop.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 14,
                color: t.text2, height: 1.5),
          ),

          const Spacer(flex: 2),

          // Error message
          if (_googleError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        t.errorBg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(_googleError!,
                  style: TextStyle(fontFamily: AppFonts.sans,
                      fontSize: 13, color: t.error)),
            ),
            const SizedBox(height: 16),
          ],

          // Google Sign-In button
          SizedBox(
            width: double.infinity, height: 52,
            child: OutlinedButton(
              onPressed: _signingIn ? null : _signInWithGoogle,
              style: OutlinedButton.styleFrom(
                foregroundColor: t.text,
                side:  BorderSide(color: t.border, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius)),
                textStyle: const TextStyle(
                    fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w500),
              ),
              child: _signingIn
                  ? SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: t.primary))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Google 'G' logo — coloured text
                        const Text('G',
                            style: TextStyle(
                              fontFamily:  AppFonts.sans,
                              fontSize:    20,
                              fontWeight:  FontWeight.w700,
                              color:        Color(0xFF4285F4),
                            )),
                        const SizedBox(width: 10),
                        Text('Continue with Google',
                            style: TextStyle(fontFamily: AppFonts.sans,
                                fontSize: 15, fontWeight: FontWeight.w500,
                                color: t.text)),
                      ],
                    ),
            ),
          ),

          const Spacer(flex: 1),

          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'Your Google account is only used to verify your identity.\nWe never post or access your data.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: AppFonts.sans,
                  fontSize: 11, color: t.text3, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

 Future<void> _signInWithGoogle() async {
    if (!mounted) return;
    setState(() { _signingIn = true; _googleError = null; });
    // Reset OAuth state before starting
    _dataProvider?.clearOAuthState();
    // Just opens browser — result handled by provider listener
    try {
      await ShopService.instance.openGoogleSignIn();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signingIn   = false;
        _googleError = 'Could not open Google Sign-In. Try again.';
      });
    }
  }

  // Called by ValueNotifier when provider updates OAuth result
  // No async, no mounted issues — ValueNotifier is safe
  void _onOAuthResult() {
    if (!mounted) return;
    final result = _dataProvider?.oauthNotifier.value ?? OAuthResult.idle;
    debugPrint('RegisterShopScreen._onOAuthResult: $result');

    switch (result) {
      case OAuthResult.idle:
        break;
      case OAuthResult.loading:
        break;
      case OAuthResult.success:
        setState(() { _signingIn = false; _step = _Step.details; });
      case OAuthResult.alreadyRegistered:
        setState(() {
          _signingIn   = false;
          _googleError = 'This Google account is already registered.\nJoin with your invite code instead.';
        });
      case OAuthResult.cancelled:
        setState(() => _signingIn = false);
      case OAuthResult.error:
        setState(() {
          _signingIn   = false;
          _googleError = 'Could not complete sign in. Try again.';
        });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 3 — DETAILS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetails(AppThemeExtension t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('About your shop',
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 22,
                  fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 6),
          Text('This sets up your shop identity',
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 14, color: t.text2)),
          const SizedBox(height: 28),

          TextFormField(
            controller: _ownerCtrl,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15, color: t.text),
            decoration: InputDecoration(
              labelText:  'Your name',
              hintText:   'e.g. Ramesh Kumar',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 18, color: t.text3),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _shopCtrl,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15, color: t.text),
            decoration: InputDecoration(
              labelText:  'Shop name',
              hintText:   'e.g. Sri Baba Traders',
              prefixIcon: Icon(Icons.store_outlined, size: 18, color: t.text3),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _cityCtrl,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15, color: t.text),
            decoration: InputDecoration(
              labelText:  'City',
              hintText:   'e.g. Siliguri',
              prefixIcon: Icon(Icons.location_city_outlined, size: 18, color: t.text3),
            ),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength:    13,  // allows +91XXXXXXXXXX
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15, color: t.text),
            decoration: InputDecoration(
              labelText:   'Mobile number',
              hintText:    'e.g. 9876543210',
              prefixIcon:  Icon(Icons.phone_outlined, size: 18, color: t.text3),
              counterText: '',  // hide maxLength counter
              helperText:  '10-digit Indian mobile number',
              helperStyle: TextStyle(fontFamily: AppFonts.sans, fontSize: 11, color: t.text3),
            ),
          ),

          // Shop ID preview
          if (_previewId.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        t.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border:       Border.all(color: t.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.tag_rounded, size: 16, color: t.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Shop ID (invite code)',
                            style: TextStyle(fontFamily: AppFonts.sans,
                                fontSize: 11, color: t.primary)),
                        Text(_previewId,
                            style: TextStyle(fontFamily: AppFonts.mono,
                                fontSize: 15, fontWeight: FontWeight.w700,
                                color: t.primary, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_detailsError != null) ...[
            const SizedBox(height: 8),
            Text(_detailsError!,
                style: TextStyle(fontFamily: AppFonts.sans,
                    fontSize: 12, color: t.error)),
          ],

const SizedBox(height: 20),

          // ── Terms & Privacy checkbox ──────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circle checkbox
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve:    Curves.easeOut,
                  width:  22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _agreedToTerms
                        ? t.primary
                        : Colors.transparent,
                    border: Border.all(
                      color: _agreedToTerms ? t.primary : t.text3,
                      width: 1.5,
                    ),
                  ),
                  child: _agreedToTerms
                      ? const Icon(
                          Icons.check_rounded,
                          size:  13,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                // Statement with tappable links
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontFamily: AppFonts.sans,
                        fontSize:   AppTypeScale.sm,
                        color:      t.text2,
                        height:     1.4,
                      ),
                      children: [
                        const TextSpan(text: 'I agree to the '),
                        TextSpan(
                          text:      'Terms & Conditions',
                          style:     TextStyle(
                            color:      t.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: t.primary,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => launchUrl(
                              Uri.parse('https://YOUR_TERMS_URL'),
                              mode: LaunchMode.externalApplication,
                            ),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text:      'Privacy Policy',
                          style:     TextStyle(
                            color:      t.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: t.primary,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => launchUrl(
                              Uri.parse('https://YOUR_PRIVACY_URL'),
                              mode: LaunchMode.externalApplication,
                            ),
                        ),
                        const TextSpan(
                          text: ' of Godown Manager app.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),


          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _canProceed ? _proceedToPin : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canProceed ? t.primary : t.border,
                foregroundColor: Colors.white,
                elevation: 0,
                textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius)),
              ),
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Phone validation ──────────────────────────────────────────────────────
  bool _isValidPhone(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\s\-]'), '');
    // Strip country code +91 or 91
    final digits = (cleaned.startsWith('+91') && cleaned.length == 13)
        ? cleaned.substring(3)
        : (cleaned.startsWith('91') && cleaned.length == 12)
            ? cleaned.substring(2)
            : cleaned;
    return digits.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(digits);
  }

  // ── Button lock — true only when all fields valid ─────────────────────────
  bool get _canProceed =>
      _ownerCtrl.text.trim().isNotEmpty &&
      _shopCtrl.text.trim().isNotEmpty &&
      _cityCtrl.text.trim().isNotEmpty &&
      _isValidPhone(_phoneCtrl.text.trim()) &&
      _agreedToTerms;

  void _proceedToPin() {
    if (_ownerCtrl.text.trim().isEmpty) {
      setState(() => _detailsError = 'Enter your name'); return;
    }
    if (_shopCtrl.text.trim().isEmpty) {
      setState(() => _detailsError = 'Enter shop name'); return;
    }
    if (_cityCtrl.text.trim().isEmpty) {
      setState(() => _detailsError = 'Enter city name'); return;
    }
    if (!_isValidPhone(_phoneCtrl.text.trim())) {
      setState(() => _detailsError = 'Enter a valid 10-digit mobile number'); return;
    }
    debugPrint('RegisterShopScreen._proceedToPin: all fields valid — proceeding to PIN');
    setState(() { _detailsError = null; _step = _Step.pin; });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 4 — PIN
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPin(AppThemeExtension t) {
    final pin     = _confirmMode ? _pin2 : _pin1;
    final hasError = _pinError != null;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _confirmMode ? 'Confirm your PIN' : 'Set admin PIN',
                    style: TextStyle(fontFamily: AppFonts.sans, fontSize: 22,
                        fontWeight: FontWeight.w700, color: t.text),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _confirmMode
                        ? 'Re-enter your 4-digit PIN to confirm'
                        : "You'll use this PIN to log in as admin",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: AppFonts.sans,
                        fontSize: 14, color: t.text2),
                  ),
                  const SizedBox(height: 40),

                  // PIN dots — reusing exact same pattern as login_screen
                  Row(
                    mainAxisSize:      MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (i) {
                      final filled = i < pin.length;
                      return Container(
                        width:  14, height: 14,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: filled
                              ? (hasError ? t.error : t.primary)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: filled
                                ? (hasError ? t.error : t.primary)
                                : t.border,
                            width: 1.5,
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 12),

                   if (hasError)
                    Text(
                      _pinError ?? '',
                      style: AppFonts.label(color: t.error),
                    )
                  else
                    const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),

        // ── Fixed bottom — PIN pad ────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color:  t.surface,
            border: Border(top: BorderSide(color: t.border, width: 0.8)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GridView.count(
                crossAxisCount:   3,
                shrinkWrap:       true,
                physics:          const NeverScrollableScrollPhysics(),
                mainAxisSpacing:  AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 2.8,
                children: _pinKeys.map((key) {
                  if (key.isEmpty) return const SizedBox.shrink();
                  return _PinKey(
                    label:    key,
                    isDelete: key == '⌫',
                    onTap:    _creating ? () {} : () => _onPinKey(key),
                  );
                }).toList(),
              ),
              if (_confirmMode) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: ElevatedButton(
                    onPressed: _creating ? null : _createShop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.primary, foregroundColor: Colors.white,
                      elevation: 0,
                      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radius)),
                    ),
                    child: _creating
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Create Shop'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _onPinKey(String key) {
    setState(() {
      _pinError = null;
      if (key == '⌫') {
        if (_confirmMode) {
          if (_pin2.isNotEmpty) _pin2 = _pin2.substring(0, _pin2.length - 1);
        } else {
          if (_pin1.isNotEmpty) _pin1 = _pin1.substring(0, _pin1.length - 1);
        }
      } else {
        if (_confirmMode) {
          if (_pin2.length >= 4) return;
          _pin2 += key;
          if (_pin2.length == 4) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _createShop());
          }
        } else {
          if (_pin1.length >= 4) return;
          _pin1 += key;
          if (_pin1.length == 4) _confirmMode = true;
        }
      }
    });
  }

  Future<void> _createShop() async {
    if (_shopCreationStarted) {
      debugPrint('RegisterShopScreen._createShop: duplicate call — ignoring');
      return;
    }
    _shopCreationStarted = true;

    if (_pin1 != _pin2) {
      _shopCreationStarted = false;  // ← reset — user can retry
      setState(() { _pinError = 'PINs do not match. Try again.'; _pin2 = ''; });
      return;
    }
    if (_pin1.length < 4) {
      _shopCreationStarted = false;  // ← reset — user can retry
      setState(() => _pinError = 'Set a 4-digit PIN'); return;
    }

    setState(() { _creating = true; _pinError = null; });

    try {
      final trialDays = RemoteConfigService.instance.trialDays;
      final owner     = _ownerCtrl.text.trim();
      final shopName  = _shopCtrl.text.trim();
      final city      = _cityCtrl.text.trim();
      final phone     = _phoneCtrl.text.trim();


      // 1. Create shop in Supabase
      final shopId = await ShopService.instance.registerShop(
        shopName:  shopName,
        city:      city,
        ownerName: owner,
        ownerPhone: phone,
        trialDays: trialDays,
      );

      // 2. Persist locally + inject singletons
      final trialEndsAt = DateTime.now().toUtc().add(Duration(days: trialDays));
      await ShopService.instance.saveShopLocally(
        shopId:      shopId,
        shopName:    shopName,
        trialEndsAt: trialEndsAt,
      );

      // 3. Create admin staff — SQLite first, then push
      await ShopService.instance.createOwnerAdmin(
        shopId:    shopId,
        ownerName: owner,
        pin:       _pin1,
      );

      // 4. Initialize app data provider with new shop
      if (!mounted) return;
      final data = context.read<AppDataProvider>();
      await data.initialize();
      data.startRealtimeSync();
// DEBUG
debugPrint('🟢 _createShop: mounted=$mounted staff=${data.staff.length} isLoggedIn=${data.isLoggedIn}');
if (!mounted) {
  debugPrint('🔴 _createShop: NOT MOUNTED — loginWithoutPin will not fire');
  return;
}

      // 5. Auto-login as admin
      final admin = data.staff.firstWhere(
        (s) => s.isAdmin,
        orElse: () => data.staff.first,
      );
      debugPrint('🟢 _createShop: logging in as ${admin.name} isAdmin=${admin.isAdmin}');
       data.loginWithoutPin(staffId: admin.id);
      debugPrint('🟢 _createShop: loginWithoutPin called — isLoggedIn=${data.isLoggedIn}');
      if (!mounted) return;
      // Replace entire stack with HomeScreen — onboarding complete
      Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute(
    builder: (_) => Consumer<AppDataProvider>(
      builder: (context, data, _) {
        if (data.isLoggedIn) return const HomeScreen();
        return const LoginScreen();
      },
    ),
  ),
  (_) => false,
);
      // loginWithoutPin() → isLoggedIn=true → Consumer in _resolveHome shows HomeScreen

    } on ShopAlreadyExistsException {
      _shopCreationStarted = false;
      setState(() {
        _creating = false;
        _pinError = 'This Google account is already registered. Use Join instead.';
      });
     } catch (e) {
      debugPrint('RegisterShopScreen._createShop error: $e');
      _shopCreationStarted = false;  // ← reset — user can retry
      String msg = 'Could not create shop. Check internet and try again.';
      if (e.toString().contains('already') ||
          e.toString().contains('duplicate') ||
          e.toString().contains('unique') ||
          e.toString().contains('23505')) {
        msg = 'This email is already registered. Go back and use "Join with invite code".';
      }
      setState(() {
        _creating = false;
        _pinError = msg;  // ← use msg, not hardcoded string
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIN KEY — identical to login_screen._PinKey for consistency
// ─────────────────────────────────────────────────────────────────────────────
class _PinKey extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  final bool         isDelete;
  const _PinKey({required this.label, required this.onTap, this.isDelete = false});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Material(
      color:        t.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border:       Border.all(color: t.border, width: 0.8),
          ),
          child: Center(
            child: Text(
              label,
              style: isDelete
                  ? TextStyle(fontFamily: AppFonts.sans,
                      fontSize: 20, color: t.text2)
                  : AppFonts.monoStyle(size: 20, color: t.text,
                      weight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}