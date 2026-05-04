// ─────────────────────────────────────────────────────────────────────────────
// register_shop_screen.dart — Phase 3 (v2.7.0)
//
// 3-step registration flow:
//   Step 1 — Phone entry + OTP send
//   Step 2 — OTP verification (6-box, auto-advance, auto-verify)
//   Step 3 — Shop details (owner, shop name, city) → Admin PIN setup
//
// Navigation rules:
//   Step 1 ← back to OnboardingScreen (allowed)
//   Step 2 ← back to Step 1 (allowed)
//   Step 3 → NO back (OTP verified — phone ownership confirmed)
//   PIN    → NO back, NO skip
//
// resumeFromPin: true — used when app killed after shop created but before PIN
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../providers/app_data_provider.dart';
import '../../services/shop_service.dart';
import '../../services/remote_config_service.dart';
import '../home/home_screen.dart';

class RegisterShopScreen extends StatefulWidget {
  final bool resumeFromPin;
  const RegisterShopScreen({super.key, this.resumeFromPin = false});

  @override
  State<RegisterShopScreen> createState() => _RegisterShopScreenState();
}

enum _Step { phone, otp, details, pin }

class _RegisterShopScreenState extends State<RegisterShopScreen> {

  _Step _step = _Step.phone;

  // ── Step 1 ────────────────────────────────────────────────────────────────
  final _phoneCtrl    = TextEditingController();
  String? _phoneError;
  bool    _sendingOtp = false;
  String  _phone      = '';

  // ── Step 2 ────────────────────────────────────────────────────────────────
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpNodes = List.generate(6, (_) => FocusNode());
  String? _otpError;
  bool    _verifyingOtp  = false;
  bool    _canResend     = false;
  int     _resendSeconds = 60;
  Timer?  _resendTimer;
  int     _otpAttempts   = 0;

  // ── Step 3 — details ──────────────────────────────────────────────────────
  final _ownerCtrl = TextEditingController();
  final _shopCtrl  = TextEditingController();
  final _cityCtrl  = TextEditingController();
  String? _detailsError;
  String  _previewId = '';

  // ── Step 3 — PIN ──────────────────────────────────────────────────────────
  String  _pin1        = '';
  String  _pin2        = '';
  bool    _confirmMode = false;
  String? _pinError;
  bool    _creating    = false;

  static const _pinKeys = ['1','2','3','4','5','6','7','8','9','','0','⌫'];

  @override
  void initState() {
    super.initState();
    if (widget.resumeFromPin) _step = _Step.pin;
    _shopCtrl.addListener(_updatePreview);
    _cityCtrl.addListener(_updatePreview);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneCtrl.dispose();
    for (final c in _otpCtrls) c.dispose();
    for (final n in _otpNodes)  n.dispose();
    _ownerCtrl.dispose();
    _shopCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _updatePreview() {
    final name = _shopCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    if (name.isEmpty || city.isEmpty) { setState(() => _previewId = ''); return; }
    final code = ShopService.instance.extractShopCode(name);
    final loc  = ShopService.instance.extractCityCode(city);
    setState(() => _previewId = '$code-$loc-XXXX');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return PopScope(
      canPop: _step == _Step.phone || _step == _Step.otp,
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: (_step == _Step.phone || _step == _Step.otp)
            ? AppBar(
                backgroundColor: t.bg,
                elevation:       0,
                leading: IconButton(
                  icon:  const Icon(Icons.arrow_back_ios_new_rounded),
                  color: t.text,
                  onPressed: _step == _Step.otp
                      ? () => setState(() {
                            _step        = _Step.phone;
                            _otpError    = null;
                            _otpAttempts = 0;
                            for (final c in _otpCtrls) c.clear();
                          })
                      : () => Navigator.of(context).pop(),
                ),
              )
            : null,
        body: SafeArea(child: _buildStep(t)),
      ),
    );
  }

  Widget _buildStep(AppThemeExtension t) {
    switch (_step) {
      case _Step.phone:   return _buildPhone(t);
      case _Step.otp:     return _buildOtp(t);
      case _Step.details: return _buildDetails(t);
      case _Step.pin:     return _buildPin(t);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 1 — PHONE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPhone(AppThemeExtension t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Verify your number',
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 22,
                  fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 6),
          Text("We'll send a one-time code to confirm your number",
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 14,
                  color: t.text2, height: 1.4)),
          const SizedBox(height: 32),
          TextFormField(
            controller:      _phoneCtrl,
            keyboardType:    TextInputType.phone,
            autofocus:       true,
            maxLength:       10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(fontFamily: AppFonts.sans, fontSize: 16, color: t.text),
            decoration: InputDecoration(
              labelText:   'Mobile number',
              hintText:    '10-digit number',
              counterText: '',
              errorText:   _phoneError,
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Text('+91',
                    style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15,
                        fontWeight: FontWeight.w500, color: t.text2)),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0),
            ),
            onFieldSubmitted: (_) => _sendOtp(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _sendingOtp ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary, foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius)),
              ),
              child: _sendingOtp
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Send OTP',
                      style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15,
                          fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (!ShopService.instance.isValidIndianPhone(phone)) {
      setState(() => _phoneError = 'Enter a valid 10-digit mobile number');
      return;
    }
    setState(() { _sendingOtp = true; _phoneError = null; });
    final result = await ShopService.instance.sendOtp(phone);
    if (!mounted) return;
    setState(() => _sendingOtp = false);

    switch (result) {
      case OtpSendResult.sent:
        _phone = phone;
        setState(() { _step = _Step.otp; });
        _startResendTimer();
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _otpNodes[0].requestFocus());
      case OtpSendResult.alreadyRegistered:
        setState(() => _phoneError =
            'This number is already registered. Join with your invite code.');
      case OtpSendResult.invalidPhone:
        setState(() => _phoneError = 'Enter a valid 10-digit mobile number');
      case OtpSendResult.networkError:
        setState(() => _phoneError = 'Check internet and try again');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STEP 2 — OTP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildOtp(AppThemeExtension t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Enter OTP',
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 22,
                  fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 6),
          Text('Sent to +91 $_phone',
              style: TextStyle(fontFamily: AppFonts.sans, fontSize: 14, color: t.text2)),
          const SizedBox(height: 32),

          // 6 OTP boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) => SizedBox(
              width: 44,
              child: TextFormField(
                controller:      _otpCtrls[i],
                focusNode:       _otpNodes[i],
                keyboardType:    TextInputType.number,
                textAlign:       TextAlign.center,
                maxLength:       1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(fontFamily: AppFonts.mono, fontSize: 20,
                    fontWeight: FontWeight.w600, color: t.text),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: BorderSide(color: t.border, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: BorderSide(color: t.primary, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: BorderSide(color: t.error, width: 1.5),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    borderSide: BorderSide(color: t.error, width: 2),
                  ),
                ),
                onChanged: (val) {
                  if (val.isNotEmpty && i < 5) _otpNodes[i + 1].requestFocus();
                  if (val.isEmpty   && i > 0) _otpNodes[i - 1].requestFocus();
                  if (i == 5 && val.isNotEmpty) _verifyOtp();
                },
              ),
            )),
          ),

          if (_otpError != null) ...[
            const SizedBox(height: 8),
            Text(_otpError!,
                style: TextStyle(fontFamily: AppFonts.sans, fontSize: 12, color: t.error)),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _verifyingOtp ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary, foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius)),
              ),
              child: _verifyingOtp
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Verify OTP',
                      style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15,
                          fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 16),

          // Resend
          Center(
            child: _canResend
                ? TextButton(
                    onPressed: _resendOtp,
                    child: Text('Resend OTP',
                        style: TextStyle(fontFamily: AppFonts.sans, fontSize: 14,
                            fontWeight: FontWeight.w500, color: t.primary)),
                  )
                : Text('Resend in ${_resendSeconds}s',
                    style: TextStyle(fontFamily: AppFonts.sans, fontSize: 13,
                        color: t.text3)),
          ),
        ],
      ),
    );
  }

  void _startResendTimer() {
    _resendSeconds = 60; _canResend = false;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) { _canResend = true; t.cancel(); }
      });
    });
  }

  Future<void> _resendOtp() async {
    if (!_canResend) return;
    for (final c in _otpCtrls) c.clear();
    _otpAttempts = 0;
    setState(() { _canResend = false; _otpError = null; });
    await _sendOtp();
  }

  Future<void> _verifyOtp() async {
    final token = _otpCtrls.map((c) => c.text).join();
    if (token.length < 6) {
      setState(() => _otpError = 'Enter the complete 6-digit OTP');
      return;
    }
    setState(() { _verifyingOtp = true; _otpError = null; });
    final result = await ShopService.instance.verifyOtp(phone: _phone, token: token);
    if (!mounted) return;
    setState(() => _verifyingOtp = false);

    switch (result) {
      case OtpVerifyResult.verified:
        setState(() => _step = _Step.details);
      case OtpVerifyResult.invalid:
        _otpAttempts++;
        final rem = 3 - _otpAttempts;
        if (rem <= 0) {
          setState(() => _otpError = 'Too many attempts. Please resend OTP.');
          for (final c in _otpCtrls) c.clear();
        } else {
          setState(() => _otpError =
              'Incorrect OTP. $rem attempt${rem == 1 ? '' : 's'} remaining.');
        }
      case OtpVerifyResult.expired:
        setState(() => _otpError = 'OTP expired. Tap resend.');
        for (final c in _otpCtrls) c.clear();
      case OtpVerifyResult.networkError:
        setState(() => _otpError = 'Check internet and try again');
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

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _proceedToPin,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary, foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius)),
              ),
              child: Text('Continue',
                  style: TextStyle(fontFamily: AppFonts.sans, fontSize: 15,
                      fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

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

                  AnimatedOpacity(
                    opacity:  hasError ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _pinError ?? '',
                      style: AppFonts.label(color: t.error),
                    ),
                  ),
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
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.radius)),
                    ),
                    child: _creating
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('Create Shop',
                            style: TextStyle(fontFamily: AppFonts.sans,
                                fontSize: 15, fontWeight: FontWeight.w600,
                                color: Colors.white)),
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
    if (_pin1 != _pin2) {
      setState(() { _pinError = 'PINs do not match. Try again.'; _pin2 = ''; });
      return;
    }
    if (_pin1.length < 4) {
      setState(() => _pinError = 'Set a 4-digit PIN'); return;
    }

    setState(() { _creating = true; _pinError = null; });

    try {
      final trialDays = RemoteConfigService.instance.trialDays;
      final owner     = _ownerCtrl.text.trim();
      final shopName  = _shopCtrl.text.trim();
      final city      = _cityCtrl.text.trim();

      // 1. Create shop in Supabase
      final shopId = await ShopService.instance.registerShop(
        shopName:  shopName,
        city:      city,
        ownerName: owner,
        phone:     _phone,
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

      // 5. Auto-login as admin
      final admin = data.staff.firstWhere(
        (s) => s.isAdmin,
        orElse: () => data.staff.first,
      );
      data.loginWithoutPin(staffId: admin.id);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } on ShopAlreadyExistsException {
      setState(() {
        _creating = false;
        _pinError = 'This phone is already registered.';
      });
    } catch (e) {
      debugPrint('RegisterShopScreen._createShop error: $e');
      setState(() {
        _creating = false;
        _pinError = 'Could not create shop. Check internet and try again.';
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
