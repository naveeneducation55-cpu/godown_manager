// ─────────────────────────────────────────────────────────────────────────────
// login_screen.dart
//
// Shown ONLY on first app open on a new device.
// After successful PIN entry, staff ID is persisted to SharedPreferences.
// Subsequent app opens auto-login and skip this screen entirely.
//
// Async notes:
//   • getSavedStaffId()  — async IO, called in main() before runApp
//   • saveStaffId()      — async IO, called after successful PIN verify
//   • clearSavedStaffId() — async IO, called on logout from home screen
//   • PIN verification itself is synchronous (in-memory check)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../providers/app_data_provider.dart';
import '../../router.dart';

// ─── SharedPreferences helpers ────────────────────────────────────────────────
// Defined here so main.dart can import them directly

const _kStaffIdKey = 'logged_in_staff_id';

Future<String?> getSavedStaffId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kStaffIdKey);
  } catch (e) {
    debugPrint('getSavedStaffId error: $e');
    return null;
  }
}

Future<void> saveStaffId(String id) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStaffIdKey, id);
  } catch (e) {
    debugPrint('saveStaffId error: $e');
  }
}

Future<void> clearSavedStaffId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStaffIdKey);
  } catch (e) {
    debugPrint('clearSavedStaffId error: $e');
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {

  StaffModel? _selectedStaff;
  String      _pin       = '';
  bool        _pinError  = false;
  bool        _isSaving  = false;

  static const _keys = [
    '1','2','3',
    '4','5','6',
    '7','8','9',
    '' ,'0','⌫',
  ];

  @override
  Widget build(BuildContext context) {
    final t    = context.appTheme;
    final data = context.watch<AppDataProvider>();

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor:           t.surface,
        automaticallyImplyLeading: false,
        title: Text(
          'Welcome',
          style: AppFonts.heading(color: t.text).copyWith(fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSizes.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              const SizedBox(height: AppSpacing.lg),

              // App logo
              Center(
                child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color:        t.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      'GI',
                      style: AppFonts.monoStyle(
                        size:   24,
                        color:  t.primaryFg,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(
                  'Godown Inventory',
                  style: AppFonts.heading(color: t.text),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Select your name to get started',
                  style: AppFonts.label(color: t.text3),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Staff selection ──────────────────────────────────────────
              const SectionLabel('Who are you?'),

              ...data.staff.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _StaffTile(
                  staff:    s,
                  selected: _selectedStaff?.id == s.id,
                  onTap:    () => _onStaffTapped(s),
                ),
              )),

              // ── PIN pad ──────────────────────────────────────────────────
              if (_selectedStaff != null) ...[
                const SizedBox(height: AppSpacing.xl),

                // Dots
                Center(
                  child: Column(children: [
                    Text(
                      'Enter PIN for ${_selectedStaff!.name}',
                      style: AppFonts.label(color: t.text2),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisSize:      MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (i) {
                        final filled = i < _pin.length;
                        return Container(
                          width:  14, height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: filled
                                ? (_pinError ? t.error : t.primary)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: filled
                                  ? (_pinError ? t.error : t.primary)
                                  : t.border,
                              width: 1.5,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Error text
                    AnimatedOpacity(
                      opacity:  _pinError ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        'Incorrect PIN. Try again.',
                        style: AppFonts.label(color: t.error),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: AppSpacing.lg),

                // PIN pad grid
                GridView.count(
                  crossAxisCount:   3,
                  shrinkWrap:       true,
                  physics:          const NeverScrollableScrollPhysics(),
                  mainAxisSpacing:  AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 2.2,
                  children: _keys.map((key) {
                    if (key.isEmpty) return const SizedBox.shrink();
                    return _PinKey(
                      label:    key,
                      isDelete: key == '⌫',
                      onTap:    () => _onKeyTap(key),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  // ── Staff tapped ──────────────────────────────────────────────────────────
  void _onStaffTapped(StaffModel staff) {
    setState(() {
      _selectedStaff = staff;
      _pin           = '';
      _pinError      = false;
    });
  }

  // ── Key tapped ────────────────────────────────────────────────────────────
  void _onKeyTap(String key) {
    // Prevent input while saving
    if (_isSaving) return;

    if (key == '⌫') {
      if (_pin.isNotEmpty) {
        setState(() {
          _pin      = _pin.substring(0, _pin.length - 1);
          _pinError = false;
        });
      }
      return;
    }

    if (_pin.length >= 4) return;

    final newPin = _pin + key;
    setState(() {
      _pin      = newPin;
      _pinError = false;
    });

    // Auto-submit on 4th digit
    if (newPin.length == 4) {
      _verifyPin(newPin);
    }
  }

  // ── Verify PIN ────────────────────────────────────────────────────────────
  // PIN check is synchronous (in-memory)
  // SharedPreferences save is async — awaited before navigation
  Future<void> _verifyPin(String pin) async {
    if (_selectedStaff == null || _isSaving) return;

    setState(() => _isSaving = true);

    // Short delay so the 4th dot renders before we check
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    // Synchronous PIN check
    final data    = context.read<AppDataProvider>();
    final success = data.login(staffId: _selectedStaff!.id, pin: pin);

    if (success) {
      // Async: save to SharedPreferences — device is now this staff's device
      await saveStaffId(_selectedStaff!.id);
      if (!mounted) return;

      // Replace login with home — back button won't return to login
      Navigator.of(context).pushReplacementNamed(AppRouter.home);
    } else {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _pinError  = true;
        _isSaving  = false;
      });
      // Clear PIN after short pause
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _pin = '');
    }
  }
}

// ─── Staff tile ───────────────────────────────────────────────────────────────
class _StaffTile extends StatelessWidget {
  final StaffModel   staff;
  final bool         selected;
  final VoidCallback onTap;
  const _StaffTile({
    required this.staff,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? t.primary.withValues(alpha:0.06)
              : t.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected ? t.primary : t.border,
            width: selected ? 1.5 : 0.8,
          ),
        ),
        child: Row(children: [
          // Avatar
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha:selected ? 0.15 : 0.07),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Center(
              child: Text(
                staff.name[0].toUpperCase(),
                style: AppFonts.monoStyle(
                  size: 16, color: t.primary, weight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Name + role badge
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  staff.name,
                  style: TextStyle(
                    fontFamily:  AppFonts.sans,
                    fontSize:    15,
                    fontWeight:  FontWeight.w600,
                    color:       selected ? t.primary : t.text,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: staff.isAdmin
                        ? t.successBg
                        : t.infoBg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    staff.isAdmin ? 'admin' : 'staff',
                    style: AppFonts.monoStyle(
                      size:  10,
                      color: staff.isAdmin ? t.success : t.infoFg,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Selected check
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: selected ? t.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: selected ? t.primary : t.border,
                width: 1.5,
              ),
            ),
            child: selected
                ? Icon(Icons.check_rounded, size: 12, color: t.primaryFg)
                : null,
          ),
        ]),
      ),
    );
  }
}

// ─── PIN key ──────────────────────────────────────────────────────────────────
class _PinKey extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  final bool         isDelete;
  const _PinKey({
    required this.label,
    required this.onTap,
    this.isDelete = false,
  });

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
                  ? TextStyle(
                      fontFamily: AppFonts.sans,
                      fontSize:   20,
                      color:      t.text2,
                    )
                  : AppFonts.monoStyle(
                      size:   20,
                      color:  t.text,
                      weight: FontWeight.w600,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}