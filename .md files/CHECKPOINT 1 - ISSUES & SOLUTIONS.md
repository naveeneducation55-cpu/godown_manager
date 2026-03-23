# Checkpoint 1 — Issues, Solutions & Technical Decisions
## Sri Baba Traders — Godown Inventory App

> This document covers every real issue faced during development,
> the implemented solution, alternatives considered, and how it
> could be improved further. Useful for interviews and future reference.

---

## 1. SQLite Deadlock on App Startup

### Problem
App would hang for 5+ minutes on launch with no output on terminal.

### Root Cause
`_seedData()` was called **inside** `_onCreate` transaction in `database_helper.dart`.
`_onCreate` opens `godown_inventory.db` → starts a transaction → calls `_seedData()`
→ which calls `IdGenerator` → which tries to open `id_sequences.db`
→ SQLite locks the thread waiting for the first transaction to finish
→ **deadlock**.

```
_onCreate() → transaction → _seedData() → IdGenerator → db.open() → WAIT FOREVER
```

### Implemented Solution
Moved `_seedData()` call to **outside** the transaction:

```dart
Future<void> _onCreate(Database db, int version) async {
  await db.transaction((txn) async {
    // create tables only — no IdGenerator calls here
  });
  await _seedData(db); // called AFTER transaction closes
}
```

### Why Not Other Alternatives
- **Merge id_sequences into main DB** — tried this, caused circular dependency.
  `DatabaseHelper` needs `IdGenerator` → `IdGenerator` needs `DatabaseHelper` → crash.
- **Pre-generate IDs without IdGenerator** — worked but sequence counters
  were out of sync, causing duplicate IDs on next add operation.

### How to Make It Better
Use a single DB connection pool (like `sqflite_common_ffi`) that supports
concurrent read access. Or move ID generation entirely to a UUID library
(`uuid` package) which needs no DB at all — simpler, zero deadlock risk.

---

## 2. Duplicate Entries in Supabase

### Problem
Every item, location, and staff member appeared **twice** in Supabase tables.
Example: `ITM-00001-20260322-1226` and `ITM-00001-20260322-1542` — same item, two IDs.

### Root Cause — 3 causes
1. `_pushMasterData()` ran every 60 seconds pushing ALL records every time.
2. `id_sequences.db` survived app uninstall on OnePlus device — old counters
   persisted, new IDs generated on reinstall had different timestamps but
   same sequence numbers, Supabase treated them as new records.
3. Reseed condition `if (_staff.isEmpty)` triggered even when items existed,
   generating a full new set of IDs.

### Implemented Solution
- Changed reseed condition to `if (_staff.isEmpty && _items.isEmpty && _locations.isEmpty)` — only truly fresh install.
- `_pushMasterData` now uses `_masterDataDirty` flag — only pushes when data actually changed via CRUD.
- Seed movements marked `sync_status = 'synced'` — never pushed to Supabase.
- Realtime echo fix — `upsertMovementFromRemote` returns `bool`, skips if no change.

### Why Not Other Alternatives
- **UUIDs instead of sequential IDs** — would eliminate the duplicate ID
  problem entirely since UUIDs are globally unique. Didn't switch because
  human-readable IDs (`MOV-00001-20260322`) are better for a godown
  business — staff can reference them verbally.
- **Supabase as source of truth** — would require internet always. App is
  offline-first by design, so local SQLite must be the source of truth.

### How to Make It Better
Use `uuid` package for IDs. Format: `mov_uuid4` instead of `MOV-00001-20260322`.
Or keep human-readable format but add device ID prefix: `MOV-D1-00001-20260322`
so two devices never generate the same ID even if counters reset.

---

## 3. Sync Button Stayed "Pending" After Successful Push

### Problem
Movements were pushed to Supabase successfully, SQLite was updated to `synced`,
but the UI still showed `8 pending`. Button never updated.

### Root Cause
After `markMovementsSynced()` updated SQLite, `_reloadMovements()` was only
called on **manual** sync (button press), not on background auto-sync.
The in-memory `_movements` list still had old `syncStatus = 'pending'` objects.
`pendingSyncCount` reads from memory, not SQLite — so count never dropped.

### Implemented Solution
Added `_onMovementsSynced` callback in `SyncService`. After marking SQLite synced,
fires callback → `_markMovementsSyncedInMemory()` updates in-memory list directly
without a full DB reload:

```dart
void _markMovementsSyncedInMemory(List<String> ids) {
  final idSet = ids.toSet();
  for (final m in _movements) {
    if (idSet.contains(m.id)) m.syncStatus = 'synced';
  }
  _notify();
}
```

### Why Not Other Alternatives
- **Full reload on every sync** — works but loads 99999 rows every 60 seconds.
  Heavy on memory and slow on low-end phones.
- **Read pendingSyncCount from SQLite directly** — would require async call
  inside a synchronous getter, breaking the provider pattern.

### How to Make It Better
Use a `Stream` from SQLite (via `sqflite` watchers) that automatically
notifies the UI when `sync_status` changes in the DB. Eliminates the need
for manual in-memory updates entirely.

---

## 4. Foreign Key Violation on Supabase Push

### Problem
```
PostgrestException: insert or update on table "movements" violates
foreign key constraint "movements_item_id_fkey"
Key is not present in table "items"
```

### Root Cause
Supabase `movements` table had a foreign key constraint on `item_id` referencing
`items`. When movements were pushed before items, Supabase rejected them.
Push order was: movements first → items second → constraint violated.

### Implemented Solution
Changed push order in `sync_service.dart`:
```
1. Push items first
2. Push locations
3. Push staff
4. Push movements last
```

Also removed `_pushMasterData` from periodic 60s sync — master data now
only pushed when `_masterDataDirty = true` (set by CRUD operations).

### Why Not Other Alternatives
- **Disable FK constraints in Supabase** — cleanest solution actually.
  Supabase is a sync relay, not the source of truth. FK constraints on a
  relay add no value and cause push failures. Recommended for production.
- **Batch upsert with dependencies** — complex, error-prone, not worth it.

### How to Make It Better
Drop all FK constraints on the Supabase `movements` table via SQL Editor:
```sql
ALTER TABLE movements DROP CONSTRAINT IF EXISTS movements_item_id_fkey;
ALTER TABLE movements DROP CONSTRAINT IF EXISTS movements_from_location_fkey;
ALTER TABLE movements DROP CONSTRAINT IF EXISTS movements_to_location_fkey;
ALTER TABLE movements DROP CONSTRAINT IF EXISTS movements_staff_id_fkey;
```
Referential integrity is enforced locally by SQLite — no need for it in Supabase.

---

## 5. Items/Locations/Staff Not Syncing to Other Devices

### Problem
Device A adds a new item. Device B never sees it — even after 10 minutes.
Movements synced fine in realtime. Master data never did.

### Root Cause
Realtime subscription only watched the `movements` table.
`_pullAndMerge()` only pulled movements.
Master data (items/locations/staff) was only **pushed** from local,
never **pulled** from remote.

### Implemented Solution
- Added `subscribeToMasterData()` in `SupabaseService` — subscribes to
  INSERT/UPDATE/DELETE on items, locations, staff tables.
- Added `_pullMasterData()` in `SyncService` — pulls changes since last sync.
- Added `_reloadMasterData()` in `AppDataProvider` — reloads all three
  tables from SQLite and notifies UI.
- Debounced master data reload (500ms) to batch rapid changes.

### Why Not Other Alternatives
- **Polling every 60s** — already doing this as fallback. But realtime
  is instant vs 60s delay. Both work together.
- **Full app restart to get new data** — unacceptable UX for a live
  inventory system where 7 staff are working simultaneously.

### How to Make It Better
Add optimistic updates — when Device A adds an item, immediately show it
on Device B without waiting for Supabase confirmation. Use a local
broadcast mechanism (like `EventBus`) between the sync service and provider.

---

## 6. Type Cast Crash from Supabase Realtime

### Problem
```
SyncService._handleRemoteMovement error:
type 'String' is not a subtype of type 'int' in type cast
```

### Root Cause
`upsertMovementFromRemote()` had:
```dart
final remoteId = remote['movement_id'] as int;  // WRONG
```
But IDs are strings (`MOV-00001-20260322`). The original spec defined IDs
as integers, but implementation uses text IDs. The cast was never updated.

Also `updated_at` from Supabase comes as a timestamp object, not a plain String.

### Implemented Solution
Changed all field reads to use `.toString()` and null-safe casts:
```dart
final remoteId = remote['movement_id'].toString();
final remoteTs = remote['updated_at']?.toString() ?? '';
```

### Why Not Other Alternatives
- **Change IDs back to integers** — human-readable IDs are a business
  requirement. Staff reference movement IDs in conversation.
  Integer IDs like `1042` give no context. `MOV-00001-20260322` tells
  you it's the first movement of the day on 22 March 2026.

### How to Make It Better
Define a proper `RemoteMovement` model with typed fields that maps
Supabase response to local format. Eliminates all `as int` / `.toString()`
guesswork:
```dart
class RemoteMovement {
  final String id;
  final String itemId;
  // ...
  factory RemoteMovement.fromSupabase(Map<String,dynamic> row) { ... }
}
```

---

## 7. Stock Validation Missing on Movement

### Problem
Staff could enter any quantity when transferring — even more than available.
Example: 10 pcs in Godown A, staff transfers 50 pcs. App accepted it.
Stock went negative. Data integrity broken.

### Root Cause
`_handleSave()` in `add_movement_screen.dart` only validated:
- Item selected ✓
- From/To selected ✓
- Qty > 0 ✓
- From ≠ To ✓

Never checked available stock.

### Implemented Solution
Added stock check before saving:
```dart
final available = stockEntry.isEmpty ? 0.0 : stockEntry.first.balance;
if (qty > available) {
  showError(context, 'Not enough stock. Available: $available ${item.unit} in ${from.name}');
  return;
}
```
Same validation added to edit movement sheet.
Special case: `SUPPLIER` as from-location skips validation (opening stock).

### Why Not Other Alternatives
- **Validate in provider/DB layer** — better architecture actually.
  UI validation can be bypassed. DB-level constraint is safer.
  SQLite `CHECK` constraint could enforce `quantity > 0` but can't
  enforce `quantity <= available` since that requires a JOIN.

### How to Make It Better
Add validation in `AppDataProvider.addMovement()` as well — defence in depth.
Show available stock as a hint below the quantity field so staff knows
the limit before entering:
```
Quantity
[  50  ]
Available in Godown A: 120 pcs
```

---

## 8. Last Admin Lockout

### Problem
Admin could change their own role to `staff` — leaving zero admins.
No way to recover without uninstalling the app.
Uninstall → reinstall → duplicate Supabase entries (cascading issue).

### Root Cause
No guard in the staff edit sheet. Role selector was always enabled.

### Implemented Solution
Three rules enforced in `manage_screen.dart`:

1. **Cannot delete yourself**
2. **Cannot delete last admin**
3. **Cannot change role if last admin or editing self**

Role chips visually disabled with badge explanation:
```
Role  [last admin — locked]
[Staff]  [Admin ✓]  ← greyed out, non-tappable
```

### Why Not Other Alternatives
- **Super-admin hardcoded in code** — inflexible. What if Ramesh leaves?
  Then the hardcoded admin is gone and a new one can't be assigned.
- **Recovery code / emergency PIN** — adds complexity. The three-rule
  approach is simpler and covers all real-world scenarios.

### How to Make It Better
Add a "Transfer admin" flow — when the last admin tries to change their role,
show a modal: "Select a new admin first before changing your role."
Forces a clean handover rather than just blocking.

---

## 9. `connectivity_plus` 5.x API Breaking Change

### Problem
App crashed on network state change. Background sync stopped working.

### Root Cause
`connectivity_plus` 5.x changed `onConnectivityChanged` to emit
`List<ConnectivityResult>` instead of single `ConnectivityResult`.
Code was written for the old API:
```dart
// Old API — crashes on 5.x
_connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
  final online = result != ConnectivityResult.none; // result is a List now
});
```

### Implemented Solution
Checked actual installed version (5.0.2) — on Android it still emits
a single value despite the breaking change in later versions.
Reverted to single value check:
```dart
_connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
  final online = result != ConnectivityResult.none;
});
```

### Why Not Other Alternatives
- **Upgrade to connectivity_plus 6.x** — would require changing to
  `results.any((r) => r != ConnectivityResult.none)` but introduces
  risk of other breaking changes. Stable v5.0.2 works fine.

### How to Make It Better
Pin the version in `pubspec.yaml` to prevent accidental upgrades:
```yaml
connectivity_plus: 5.0.2  # pinned — breaking change in 6.x
```

---

## 10. `shared_preferences_android` Build Failure

### Problem
```
error: cannot find symbol
  new StringListObjectInputStream(...)
BUILD FAILED
```

### Root Cause
Known bug in `shared_preferences_android 2.4.21` — a class was removed
but still referenced in the compiled Java. Gradle cache corruption
compounded the issue.

### Implemented Solution
```powershell
flutter clean
cd android && .\gradlew clean && cd ..
flutter pub get
flutter run
```

### Why Not Other Alternatives
- **Downgrade shared_preferences** — works but creates version conflicts
  with supabase_flutter which depends on shared_preferences internally.
- **Replace shared_preferences** — used only for theme mode and staff ID
  persistence. Could use SQLite instead but adds unnecessary complexity.

### How to Make It Better
Use `flutter_secure_storage` for staff ID persistence (more secure than
SharedPreferences) and store theme mode in SQLite alongside app settings.
Eliminates the SharedPreferences dependency entirely.

---

## 11. Home Screen Sync Row Always Showed "All Synced"

### Problem
Home screen showed green "all synced" dot even when 8 movements were pending.
Staff had no visual indication that data needed to sync.

### Root Cause
`_SyncStatusRow` widget received `pending` count as parameter but never
used it — hardcoded green dot and "all synced" text:
```dart
// pending was passed in but ignored
Text('all synced', style: ... color: t.success)
```

### Implemented Solution
```dart
final hasPending = pending > 0;
Container(color: hasPending ? t.warnFg : t.success) // amber vs green dot
Text(hasPending ? '$pending pending' : 'all synced',
     style: ... color: hasPending ? t.warnFg : t.success)
```

### How to Make It Better
Add a pulsing animation on the amber dot when pending > 0 to draw
attention. Also show last sync timestamp: `last synced 2 min ago`.

---

## Summary Table

| # | Issue | Category | Severity | Status |
|---|-------|----------|----------|--------|
| 1 | SQLite deadlock on startup | Architecture | Critical | ✅ Fixed |
| 2 | Duplicate Supabase entries | Data integrity | Critical | ✅ Fixed |
| 3 | Sync button stayed pending | UI/State | High | ✅ Fixed |
| 4 | FK violation on Supabase push | Backend | High | ✅ Fixed |
| 5 | Master data not syncing to other devices | Sync | High | ✅ Fixed |
| 6 | Type cast crash from Supabase | Runtime error | High | ✅ Fixed |
| 7 | No stock validation on movement | Business logic | High | ✅ Fixed |
| 8 | Last admin lockout | Edge case | Medium | ✅ Fixed |
| 9 | connectivity_plus API change | Dependency | Medium | ✅ Fixed |
| 10 | shared_preferences build failure | Build | Medium | ✅ Fixed |
| 11 | Sync row always showed synced | UI bug | Low | ✅ Fixed |

---

## What Could Be Significantly Better

### 1. Replace Sequential IDs with UUIDs
```
Current:  MOV-00001-20260322
Better:   mov_f47ac10b-58cc-4372-a567-0e02b2c3d479
```
Eliminates all duplicate ID issues across devices. Use `uuid` package.

### 2. Drop Supabase Foreign Keys
Supabase is a sync relay, not source of truth.
FK constraints only cause push ordering problems with zero benefit.

### 3. Add DB-Level Stock Validation
Move stock check from UI to `AppDataProvider.addMovement()`.
UI validation can be bypassed; provider-level cannot.

### 4. Use `flutter_secure_storage` for Staff ID
SharedPreferences is unencrypted. Staff PIN + ID stored securely.

### 5. Paginate History Screen
Currently loads all 99999 movements into memory.
For 1 year of data (10 movements/day × 365 = 3650 rows) this is fine.
But at 3+ years it will slow down. Add infinite scroll with `offset`.

### 6. Add Device ID to IDs
```
MOV-D1-00001-20260322  ← D1 = device 1
MOV-D2-00001-20260322  ← D2 = device 2
```
Guarantees no collision even if `id_sequences.db` resets.

### 7. Supabase Row Level Security (RLS)
Currently all devices have full table access.
For v2.0 multi-shop, RLS is essential to isolate shop data.

---

*Checkpoint 1 — March 2026*
*v1.0.0 — Single shop, offline-first, 7 devices*
