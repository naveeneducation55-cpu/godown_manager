// ─────────────────────────────────────────────────────────────────────────────
// shop_service.dart — Phase 3 (v2.6.3)
//
// All shop-related business logic. No UI. No state management.
//
// Responsibilities:
//   • Google Sign-In for shop owner identity verification
//   • Shop ID generation (3-letter code + 3-letter city + 4-digit random)
//   • Shop registration (Supabase shops table)
//   • Invite code validation
//   • Admin staff creation (SQLite → Supabase push)
//   • Shop persistence (SharedPrefs + singleton injection)
//   • Partial registration detection
//   • Trial status check (local grace period → Supabase fallback)
//
// Follows existing service pattern:
//   • Singleton via _() private constructor
//   • All Supabase via Supabase.instance.client (not SupabaseService)
//   • SQLite via DatabaseHelper.instance
//   • Push via SyncService.instance.markMasterDirty()
//   • No throws to UI — returns typed enums for all outcomes
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/database_helper.dart';
import '../services/sync_service.dart';
import '../services/supabase_service.dart';
import '../utils/id_generator.dart';
import 'dart:async';
// ─────────────────────────────────────────────────────────────────────────────
// ENUMS — typed outcomes, no string errors to UI
// ─────────────────────────────────────────────────────────────────────────────


enum ShopValidationResult {
  valid,
  notFound,
  expired,    // trial ended + not paid
  suspended,  // admin action
  networkError,
}

// ─────────────────────────────────────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────────────────────────────────────

class ShopInfo {
  final String    shopId;
  final String    shopName;
  final String    plan;
  final DateTime  trialEndsAt;
  final DateTime? paidUntil;

  const ShopInfo({
    required this.shopId,
    required this.shopName,
    required this.plan,
    required this.trialEndsAt,
    this.paidUntil,
  });

  bool get isTrialActive =>
      plan == 'trial' && DateTime.now().toUtc().isBefore(trialEndsAt);

  bool get isPaidActive =>
      plan == 'active' &&
      (paidUntil == null || DateTime.now().toUtc().isBefore(paidUntil!));

  bool get isValidPlan => plan == 'valid';

  bool get isActive => isTrialActive || isPaidActive || isValidPlan;

  factory ShopInfo.fromMap(Map<String, dynamic> m) => ShopInfo(
        shopId:      m['shop_id']      as String,
        shopName:    m['shop_name']    as String? ?? '',
        plan:        m['plan']         as String,
        trialEndsAt: DateTime.parse(m['trial_ends_at'] as String),
        paidUntil:   m['paid_until'] != null
            ? DateTime.tryParse(m['paid_until'] as String)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EXCEPTION
// ─────────────────────────────────────────────────────────────────────────────

class ShopAlreadyExistsException implements Exception {
  const ShopAlreadyExistsException();
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class ShopService {
  ShopService._();
  static final ShopService instance = ShopService._();

  // SharedPrefs keys — consistent with existing kStaffIdKey pattern
  static const _kShopIdKey    = 'current_shop_id';
  static const _kShopNameKey  = 'current_shop_name';
  static const _kTrialEndsKey = 'trial_ends_at';

  SupabaseClient get _client => Supabase.instance.client;

  // ═══════════════════════════════════════════════════════════════════════════
  // GOOGLE SIGN-IN — identity verification for shop owner registration
  // Uses google_sign_in package + Supabase Auth
  // On success: stores owner email internally for use in registerShop()
  // ═══════════════════════════════════════════════════════════════════════════

  String? _ownerEmail; // set after Google Sign-In, used in registerShop()

  

    Future<void> openGoogleSignIn() async {
    debugPrint('ShopService.openGoogleSignIn: clearing session + opening browser');
    await _client.auth.signOut();
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.supabase.godowninventory://login-callback',
      authScreenLaunchMode: LaunchMode.externalApplication,
      queryParams: {'prompt': 'select_account'},
    );
  }


  void clearOwnerEmail() => _ownerEmail = null;

   void setOwnerEmail(String email) {
    _ownerEmail = email;
    debugPrint('ShopService.setOwnerEmail: $email');
  }
  
  Future<bool> checkEmailExists(String email) async {
  try {
    debugPrint('ShopService.checkEmailExists: checking $email');
    final result = await _client
        .from('shops')
        .select('shop_id')
        .eq('owner_email', email)
        .limit(1);
    final exists = (result as List).isNotEmpty;
    debugPrint('ShopService.checkEmailExists: exists=$exists');
    return exists;
  } catch (e) {
    debugPrint('ShopService.checkEmailExists error: $e');
    return false; // fail open — let registerShop handle duplicate
  }
}
  // ═══════════════════════════════════════════════════════════════════════════
  // SHOP ID GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// 3-letter shop code from name
  /// Single word → first 3 letters. Multi-word → initials (max 3).
  /// Always exactly 3 uppercase letters.
  String extractShopCode(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'[0-9]'), '').trim();
    if (cleaned.isEmpty) return 'SHP';
    final words = cleaned.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'SHP';
    if (words.length == 1) {
      final w = words[0].toUpperCase();
      return w.substring(0, min(3, w.length)).padRight(3, w[0]);
    }
    final initials = words.take(3).map((w) => w[0].toUpperCase()).join();
    return initials.padRight(3, words[0][0].toUpperCase());
  }

  /// 3-letter city code — always first 3 letters uppercase
  String extractCityCode(String city) {
    final cleaned = city.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (cleaned.isEmpty) return 'CIT';
    return cleaned.substring(0, min(3, cleaned.length)).padRight(3, 'X');
  }

  /// Generates unique shop_id with collision check + 5 retries
  Future<String> generateShopId(String shopName, String city) async {
    final code = extractShopCode(shopName);
    final loc  = extractCityCode(city);
    for (int i = 0; i < 5; i++) {
      final num    = (1000 + Random().nextInt(9000)).toString();
      final shopId = '$code-$loc-$num';
      if (!await _shopIdExists(shopId)) {
        debugPrint('ShopService.generateShopId: $shopId (attempt ${i + 1})');
        return shopId;
      }
      debugPrint('ShopService.generateShopId: collision on $shopId');
    }
    throw Exception('ShopService: failed to generate unique shop_id after 5 attempts');
  }

  Future<bool> _shopIdExists(String shopId) async {
    try {
      final result = await _client
          .from('shops')
          .select('shop_id')
          .eq('shop_id', shopId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      return result != null;
    } catch (e) {
      debugPrint('ShopService._shopIdExists error: $e');
      return false; // Assume not exists on network error — safe to retry
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REGISTER SHOP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Creates shop row in Supabase.
  /// Requires signInWithGoogle() to be called first — uses stored _ownerEmail.
  /// Returns shop_id on success. Throws [ShopAlreadyExistsException] on duplicate email.
  
  
  Future<String> registerShop({
    required String shopName,
    required String city,
    required String ownerName,
    required int    trialDays,
    String?         ownerPhone, // optional — user can add phone later
  }) async {
    debugPrint('ShopService.registerShop: $shopName / $city email=$_ownerEmail');
    assert(_ownerEmail != null, 'signInWithGoogle() must be called before registerShop()');
    final shopId      = await generateShopId(shopName, city);
    final now         = DateTime.now().toUtc();
    final trialEndsAt = now.add(Duration(days: trialDays));
    try {
      debugPrint('ShopService.registerShop: _ownerEmail=$_ownerEmail phone=$ownerPhone');
      await _client.from('shops').insert({
        'shop_id':       shopId,
        'shop_name':     shopName,
        'owner_name':    ownerName,
        'owner_email':   _ownerEmail,
        'owner_phone':   ownerPhone, // nullable
        'city':          city,
        'plan':          'trial',
        'trial_ends_at': trialEndsAt.toIso8601String(),
        'paid_until':    null,
        'created_at':    now.toIso8601String(),
      });
      _ownerEmail = null; // clear after use
      debugPrint('ShopService.registerShop: created $shopId');
      return shopId;
    } on PostgrestException catch (e) {
      debugPrint('ShopService.registerShop PostgrestException: ${e.message}');
      if (e.code == '23505') throw const ShopAlreadyExistsException();
      rethrow;
    } catch (e) {
      debugPrint('ShopService.registerShop error: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VALIDATE INVITE CODE
  // ═══════════════════════════════════════════════════════════════════════════

  // TC-008 — format: exactly AAA-BBB-NNNN (3 letters - 3 letters - 4 digits)
  static final _shopIdRegex = RegExp(r'^[A-Z]{3}-[A-Z]{3}-\d{4}$');

  Future<ShopValidationResult> validateInviteCode(String code) async {
    final trimmed = code.trim().toUpperCase();
    debugPrint('ShopService.validateInviteCode: $trimmed');
    if (trimmed.isEmpty) return ShopValidationResult.notFound;

    // TC-008 — reject malformed codes before touching Supabase
    if (!_shopIdRegex.hasMatch(trimmed)) {
      debugPrint('ShopService.validateInviteCode: invalid format — $trimmed');
      return ShopValidationResult.notFound;
    }

    try {
      final result = await _client
          .from('shops')
          .select('shop_id, shop_name, plan, trial_ends_at, paid_until')
          .eq('shop_id', trimmed)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (result == null) {
        debugPrint('ShopService.validateInviteCode: not found');
        return ShopValidationResult.notFound;
      }

      final shop = ShopInfo.fromMap(result);
      debugPrint('ShopService.validateInviteCode: found plan=${shop.plan}');

      if (shop.plan == 'suspended') return ShopValidationResult.suspended;
      if (!shop.isActive)           return ShopValidationResult.expired;

      return ShopValidationResult.valid;
    } catch (e) {
      debugPrint('ShopService.validateInviteCode error: $e');
      return ShopValidationResult.networkError;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADMIN CREATION — SQLite first, then push (offline-first pattern)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> createOwnerAdmin({
    required String shopId,
    required String ownerName,
    required String pin,
  }) async {
    debugPrint('ShopService.createOwnerAdmin: shopId=$shopId');
    final staffId = await IdGenerator.instance.staff();
    final now     = DateTime.now().toUtc();
    await DatabaseHelper.instance.insertStaff({
      'staff_id':   staffId,
      'staff_name': ownerName,
      'pin':        pin,
      'role':       'admin',
      'shop_id':    shopId,
      'created_at': now.toIso8601String(),
    });
    debugPrint('ShopService.createOwnerAdmin: $staffId created locally');
    SyncService.instance.markMasterDirty();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHOP PERSISTENCE — SharedPrefs + singleton injection
  // Called ONLY after shop confirmed in Supabase
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> saveShopLocally({
    required String   shopId,
    required String   shopName,
    required DateTime trialEndsAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kShopIdKey,    shopId);
    await prefs.setString(_kShopNameKey,  shopName);
    await prefs.setString(_kTrialEndsKey, trialEndsAt.toIso8601String());
await prefs.setBool('is_shop_owner',  true);
    // Inject into singletons — all queries now filtered to this shop
    // Mirrors the pattern in AppDataProvider.initialize()
    DatabaseHelper.instance.setShopId(shopId);
    SupabaseService.instance.setShopId(shopId);

    debugPrint('ShopService.saveShopLocally: $shopId persisted + singletons injected');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHOP STATE READERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<String?> getSavedShopId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kShopIdKey);
  }

  Future<String> getSavedShopName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kShopNameKey) ?? '';
  }

  Future<DateTime?> getSavedTrialEndsAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val   = prefs.getString(_kTrialEndsKey);
      return val != null ? DateTime.tryParse(val) : null;
    } catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PARTIAL REGISTRATION DETECTION
  // shop_id in SharedPrefs but no admin staff = app killed mid-registration
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> isPartialRegistration() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final shopId = prefs.getString(_kShopIdKey);
      if (shopId == null || shopId.isEmpty) return false;

      DatabaseHelper.instance.setShopId(shopId);
      final staff    = await DatabaseHelper.instance.getStaff();
      final hasAdmin = staff.any((s) => s['role'] == 'admin');

      if (!hasAdmin) {
        debugPrint('ShopService.isPartialRegistration: shopId=$shopId no admin');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('ShopService.isPartialRegistration error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRIAL STATUS — local grace period first, Supabase fallback
  // Grace period: 2 days after trial_ends_at before hard block
  // Handles offline edge case — device offline when trial expires
  // ═══════════════════════════════════════════════════════════════════════════

  Future<bool> isShopActive(String shopId) async {
    // Step 1 — check local cache with 2-day grace period
    final localEndsAt = await getSavedTrialEndsAt();
    if (localEndsAt != null) {
      final gracePeriod = localEndsAt.add(const Duration(days: 2));
      if (DateTime.now().toUtc().isBefore(gracePeriod)) return true;
    }

    // Step 2 — fetch fresh from Supabase
    try {
      final result = await _client
          .from('shops')
          .select('plan, trial_ends_at, paid_until')
          .eq('shop_id', shopId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (result == null) return false;

      final shop = ShopInfo.fromMap({...result, 'shop_id': shopId, 'shop_name': ''});

      // Refresh local cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTrialEndsKey, shop.trialEndsAt.toIso8601String());

      return shop.isActive;
    } catch (e) {
      debugPrint('ShopService.isShopActive error: $e');
      // Network error — fall back to grace period check
      if (localEndsAt != null) {
        return DateTime.now().toUtc()
            .isBefore(localEndsAt.add(const Duration(days: 2)));
      }
      return false;
    }
  }
}