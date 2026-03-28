# Godown Inventory App — Complete Development Journal
### Sri Baba Traders · Flutter + SQLite + Supabase · Android

> **Purpose of this document**
> A complete record of every technical decision, problem, and solution made
> during development — written to support interview discussions at any depth.
> Each section explains *what* broke, *why* it broke, *what* was chosen and why,
> and *what* a better solution would look like given more time or resources.

---

## Project Overview

| Field | Detail |
|---|---|
| **Client** | Sri Baba Traders — a wholesale textile godown |
| **Problem solved** | Replace paper registers with a real-time digital inventory system |
| **Platform** | Android (APK distributed via WhatsApp) |
| **Stack** | Flutter · Dart · SQLite (sqflite) · Supabase (PostgreSQL + Realtime) |
| **Devices** | 7 staff phones, all syncing the same inventory |
| **Architecture** | Offline-first — works without internet, syncs when connected |

### The Core Business Problem
Staff would take goods from the godown, write it on paper, and enter it into a register at end of day. By then the stock numbers were wrong, mismatches happened, and no one had real-time visibility. The app records every movement instantly and syncs across all 7 devices in under 1 second.

---

## Architecture Decisions (Made Before Writing Code)

### Why Flutter?
- Single codebase for all 7 Android phones (different brands, different OS versions)
- Hot reload speeds up development significantly
- Provider package gives clean state management without complexity of Bloc/Riverpod

### Why SQLite as primary storage?
- App must work completely offline — godowns have poor connectivity
- SQLite is embedded, zero network dependency
- sqflite package is mature and well-tested on Android
- Local-first means staff never sees a loading spinner for basic operations

### Why Supabase over Firebase?
- PostgreSQL backend — standard SQL, easier to reason about than Firestore's document model
- Built-in Realtime via websockets — no polling needed
- Free tier generous enough for 7 devices with moderate traffic
- Row Level Security available for future multi-shop v2.0

### Why Provider over Riverpod/Bloc?
- Single `AppDataProvider` holds all state — simple enough that one provider works
- Team is small, complexity of Riverpod not justified
- Provider is synchronous-by-default which matches SQLite's usage pattern

### Data Flow Architecture
```
User Action
    ↓
AppDataProvider (in-memory state + business logic)
    ↓
DatabaseHelper (SQLite — source of truth)
    ↓
SyncService (push pending → pull remote → merge)
    ↓
SupabaseService (all HTTP/websocket calls)
    ↓
Supabase Cloud (relay — NOT source of truth)
    ↓
Other Devices (realtime → merge → UI update)
```

**Key principle:** SQLite is always the source of truth. Supabase is a relay. Every operation writes to SQLite first, then syncs to Supabase in the background.

---

## ID Design

### Format: `PREFIX-NNNNN-YYYYMMDD`
```
MOV-00001-20260322   ← movement
ITM-00001-20260322   ← item
LOC-00001-20260322   ← location
STF-00001-20260322   ← staff
SUPPLIER             ← special constant for opening stock
```

### Why human-readable IDs instead of UUIDs?
Staff verbally reference IDs: *"Check MOV-00001, something is wrong with it."*
A UUID like `f47ac10b-58cc-4372-a567-0e02b2c3d479` is unusable in conversation.

### Why a separate `id_sequences.db`?
The sequence counter needs its own transaction to increment atomically.
If merged into the main DB, opening a transaction on the main DB while
`_onCreate` is running causes a deadlock (covered in Bug #1 below).

### Known weakness
Two devices could generate `MOV-00001-20260322` independently if both install
on the same day and both start from sequence 0. Fix: add device ID prefix
(`MOV-D1-00001-20260322`). Not implemented yet — acceptable risk for v1.0
since only one device ever starts fresh at a time in practice.

---

## Sync Architecture

```
REALTIME  → Supabase websocket pushes changes in < 1 second
PERIODIC  → Pull every 30 seconds — catches missed realtime events
ON-DEMAND → Manual sync button in SyncScreen
ON-RECONNECT → Fires immediately when internet restores
```

### Conflict resolution
`latest updated_at wins` — if two devices edit the same movement, whichever
had the later timestamp keeps its version. Simple and predictable.

### Offline behaviour
- All writes go to SQLite immediately with `sync_status = 'pending'`
- UI shows pending count — staff knows what hasn't synced yet
- When internet restores, connectivity listener fires → pending records push → status updates to `synced`

---

## Bug Log — Every Problem Faced and Solved

---

### Bug 1 — SQLite Deadlock on App Startup
**Severity:** Critical · **Phase:** Day 1

#### What happened
App hung for 5+ minutes on first launch. No output in terminal. No crash. Just frozen.

#### Root cause
```
_onCreate() opens godown_inventory.db
    → starts transaction
        → calls _seedData()
            → _seedData() calls IdGenerator
                → IdGenerator tries to open id_sequences.db
                    → SQLite locks — waiting for first transaction to finish
                        → DEADLOCK — neither can proceed
```
Two database connections, one waiting for the other to release a lock that never gets released.

#### Solution chosen
Move `_seedData()` call to *after* the transaction closes:
```dart
Future<void> _onCreate(Database db, int version) async {
  await db.transaction((txn) async {
    // CREATE TABLE statements only — no IdGenerator here
  });
  await _seedData(db); // AFTER transaction — IdGenerator can now open freely
}
```

#### Why not alternatives
- **Merge id_sequences into main DB** — creates circular dependency. `DatabaseHelper` initialises `IdGenerator`, `IdGenerator` needs `DatabaseHelper` — infinite loop at construction time.
- **Pre-generate IDs as hardcoded strings** — breaks the sequence counter. Next `idGen.item()` call would return `ITM-00001` again, colliding with seeded data.

#### Better solution
Replace `IdGenerator` entirely with the `uuid` package. UUIDs need no database, no sequences, no locks. Zero deadlock risk. Trade-off: loses human-readable ID format.

---

### Bug 2 — Duplicate Entries in Supabase
**Severity:** Critical · **Phase:** Week 1

#### What happened
Every item appeared twice in Supabase. `60*90 Dabangg` showed up as two separate entries with different IDs — `ITM-00001-20260322-1226` and `ITM-00001-20260322-1542`.

#### Root cause (3 separate causes stacked)
1. `_pushMasterData()` ran on every 60-second periodic sync, pushing ALL records every time — not just changed ones
2. `id_sequences.db` survived app uninstall on OnePlus devices. Reinstalling generated new IDs with different timestamps but same sequence numbers — Supabase saw them as new records
3. Reseed condition `if (_staff.isEmpty)` fired even when items and locations existed — generating a full duplicate set

#### Solution chosen
- Added `_masterDataDirty` flag — master data only pushed when CRUD operations mark it dirty
- Tightened reseed condition: `if (_staff.isEmpty && _items.isEmpty && _locations.isEmpty)` — only truly empty DB
- Seed movements marked `sync_status = 'synced'` — never pushed to Supabase
- `upsertMovementFromRemote()` returns `bool` — skips if local record is same or newer (prevents echo loop)

#### Why not alternatives
- **Full Supabase as source of truth** — requires internet always. Breaks offline-first requirement. Unacceptable.
- **UUIDs** — would eliminate duplicate ID problem entirely. Not chosen because human-readable IDs are a business requirement.

#### Better solution
Add device ID prefix to all generated IDs: `MOV-D1-00001-20260322`. Two devices can never generate the same ID even if their sequence counters both reset. No UUID trade-off.

---

### Bug 3 — Sync Button Stayed "Pending" After Successful Push
**Severity:** High · **Phase:** Week 1

#### What happened
Movements pushed to Supabase successfully. SQLite updated to `synced`. But home screen and sync screen still showed `8 pending`. UI never reflected the actual state.

#### Root cause
```
markMovementsSynced() → updates SQLite ✓
                      → does NOT update _movements list in memory ✗

pendingSyncCount reads from _movements (memory)
                 NOT from SQLite

Memory still has syncStatus = 'pending' → count never drops
```

#### Solution chosen
Added `_onMovementsSynced` callback from `SyncService` → `AppDataProvider`. After marking SQLite, fires callback which updates in-memory list directly:
```dart
void _markMovementsSyncedInMemory(List<String> ids) {
  final idSet = ids.toSet();
  for (final m in _movements) {
    if (idSet.contains(m.id)) m.syncStatus = 'synced';
  }
  _notify();
}
```

#### Why not alternatives
- **Full reload from SQLite on every sync** — loads up to 99,999 rows every 30 seconds on low-end phones. Memory and speed cost too high.
- **Read count directly from SQLite** — `pendingSyncCount` is a synchronous getter. Making it async would require restructuring every screen that reads it.

#### Better solution
Use SQLite streams (reactive queries). A `Stream<List<Movement>>` that auto-notifies when `sync_status` changes would eliminate all manual in-memory tracking. Library: `drift` (formerly moor) supports this out of the box.

---

### Bug 4 — Foreign Key Violation on Supabase Push
**Severity:** High · **Phase:** Week 1

#### What happened
```
PostgrestException: insert or update on table "movements" violates
foreign key constraint "movements_item_id_fkey"
Key is not present in table "items"
```
Movements were being rejected by Supabase.

#### Root cause
Supabase `movements` table had FK constraints referencing `items`, `locations`, `staff`. Push order was: movements first → then items. Items didn't exist yet when movements arrived.

#### Solution chosen
Enforced correct push order:
```
1. Push items first
2. Push locations
3. Push staff
4. Push movements last
```

#### Why not alternatives
- **Batch upsert with transaction** — Supabase HTTP API doesn't support cross-table transactions in a single call. Would require multiple round-trips with manual ordering anyway.

#### Better solution
Drop all FK constraints from Supabase entirely:
```sql
ALTER TABLE movements DROP CONSTRAINT IF EXISTS movements_item_id_fkey;
```
Supabase is a sync relay, not the authority on data integrity. SQLite enforces referential integrity locally. FK constraints on the relay add no value and cause ordering-dependent failures.

---

### Bug 5 — Master Data Not Syncing to Other Devices
**Severity:** High · **Phase:** Week 2

#### What happened
Device A adds a new item. Device B never sees it — even after 10 minutes. Movements synced fine. Items, locations, and staff never appeared on other devices.

#### Root cause
Realtime subscription only watched the `movements` table. `_pullAndMerge()` only pulled movements. Master data (items/locations/staff) was pushed from Device A correctly, but Device B never received a signal to pull it.

#### Solution chosen
- Added realtime subscriptions for `items`, `locations`, `staff` tables in `SupabaseService`
- Added `_pullMasterData()` in `SyncService` — pulls changes since last sync timestamp
- Added `_reloadMasterData()` in `AppDataProvider` — reloads all three tables from SQLite and notifies UI
- Debounced master data reload (500ms) — bulk adds don't trigger 50 reloads

#### Why not alternatives
- **Polling-only (no realtime)** — 30-second delay between Device A adding an item and Device B seeing it. Unacceptable when 7 people work simultaneously.
- **Full app restart to get new data** — obvious non-starter for live inventory.

#### Better solution
Optimistic updates — when Device A pushes an item to Supabase, broadcast it locally immediately via an `EventBus` so Device B's UI updates before the pull cycle even runs.

---

### Bug 6 — Type Cast Crash from Supabase Realtime
**Severity:** High · **Phase:** Week 2

#### What happened
```
SyncService._handleRemoteMovement error:
type 'String' is not a subtype of type 'int' in type cast
```
Realtime events crashed silently. Movements from other devices never merged.

#### Root cause
Original spec defined IDs as integers. Implementation switched to text IDs (`MOV-00001-20260322`). The cast in `upsertMovementFromRemote` was never updated:
```dart
final remoteId = remote['movement_id'] as int; // WRONG — it's a String
```
Also `updated_at` from Supabase arrives as a timestamp object, not a plain String.

#### Solution chosen
Changed all field reads to use `.toString()` and null-safe casts:
```dart
final remoteId = remote['movement_id'].toString();
final remoteTs = remote['updated_at']?.toString() ?? '';
```
Applied this pattern to every field in every `upsertXFromRemote()` method.

#### Why not alternatives
- **Change IDs back to integers** — loses human-readable format. Business requirement: staff reference IDs verbally. `1042` gives no context. `MOV-00001-20260322` tells you exactly what it is.

#### Better solution
Define typed `RemoteMovement`, `RemoteItem` etc. models with a `fromSupabase()` factory:
```dart
class RemoteMovement {
  final String id;
  final String itemId;
  factory RemoteMovement.fromSupabase(Map<String,dynamic> row) {
    return RemoteMovement(
      id:     row['movement_id'].toString(),
      itemId: row['item_id'].toString(),
      // ...
    );
  }
}
```
All type handling in one place. Any new field added to Supabase gets handled consistently.

---

### Bug 7 — Stock Numbers Wrong After Remote Movement
**Severity:** High · **Phase:** Week 3

#### What happened
Device A moves 50 pcs from Godown A to Shop. Device B receives the movement via realtime. Device B's history screen shows the movement — but stock screen still shows old numbers. Stock only updated after manually pressing sync.

#### Root cause
`mergeRemoteMovement()` correctly updated `_movements` list and called `_invalidateCaches()`. But `_refreshStockCache()` was never called after a remote merge. Stock cache stayed stale until the next local mutation triggered a refresh.

#### Solution chosen
Added `_refreshStockCache()` call in `mergeRemoteMovement()`:
```dart
Future<void> mergeRemoteMovement(Map<String,dynamic> row) async {
  // ... merge logic ...
  _invalidateCaches();
  _notify();
  _refreshStockCache(); // ← this was missing
}
```
Also added `onStockInvalidated` callback from `SyncService` so periodic sync pulls also refresh stock.

Also fixed `_refreshStockCache()` to call `_notify()` after computing, so the stock screen widget actually rebuilds.

#### Why not alternatives
- **Recompute stock synchronously on every `getStock()` call** — was doing this before caching was added. On 10,000+ movements, recomputing every rebuild causes jank. Cache is necessary.

---

### Bug 8 — Stock Validation Missing on Movement
**Severity:** High · **Phase:** Week 2

#### What happened
Staff could transfer 500 pcs from Godown A even if Godown A only had 50. App accepted it. Stock went negative. Data integrity was broken.

#### Root cause
`_handleSave()` in `add_movement_screen.dart` validated: item selected, locations selected, qty > 0, from ≠ to. Never checked available stock against requested quantity.

#### Solution chosen
Added stock check before saving:
```dart
final available = stockEntry.isEmpty ? 0.0 : stockEntry.first.balance;
if (qty > available) {
  showError(context, 'Not enough stock. Available: $available ${item.unit} in ${from.name}');
  return;
}
```
Special case: `SUPPLIER` as from-location always passes — that's opening stock entry, not a transfer.

#### Better solution
Move validation to `AppDataProvider.addMovement()` as well. UI validation can be bypassed (e.g., by calling the provider method directly in tests). Provider-level validation is the safety net. Defence in depth.

---

### Bug 9 — Last Admin Lockout
**Severity:** Medium · **Phase:** Week 2

#### What happened
Admin could change their own role to `staff`. App then had zero admins. No way to recover without uninstalling — which caused duplicate Supabase entries on reinstall.

#### Root cause
No guard in the staff edit UI. Role dropdown was always enabled for everyone.

#### Solution chosen
Three enforced rules in `manage_screen.dart`:
1. Cannot delete yourself
2. Cannot delete the last admin
3. Cannot change role if you are the last admin or if you are editing yourself

Role selector visually greyed out with explanation badge when locked.

#### Why not alternatives
- **Hardcode a super-admin in code** — inflexible. If Ramesh (the hardcoded admin) leaves, his replacement can't be promoted without a code change and APK rebuild.
- **Emergency recovery PIN** — adds complexity. The three-rule approach covers all realistic scenarios without extra UX.

#### Better solution
"Transfer admin" flow — when the last admin tries to demote themselves, show a modal: *"Select a new admin first."* Forces clean handover rather than hard block.

---

### Bug 10 — Fresh Install Shows Hardcoded Data (Critical Architecture Bug)
**Severity:** Critical · **Phase:** Week 4

#### What happened
New phone installs APK via WhatsApp. Opens app. Sees Ramesh, Suresh, Dinesh, Godown A, Godown B — hardcoded seed data — instead of the real Supabase data that other phones have been using for weeks.

#### Root cause (layered)

**Layer 1 — Wrong initialisation order in `main.dart`:**
```dart
// WRONG ORDER
final dataProvider = AppDataProvider();
await dataProvider.initialize();   // ← calls firstSyncFromRemote() here
await SupabaseService.initialize(); // ← Supabase not ready yet!
```
`firstSyncFromRemote()` ran before Supabase was initialised → every call failed silently → fell through to seed data.

**Layer 2 — `_seedData()` called automatically from `_onCreate()`:**
```dart
Future<void> _onCreate(Database db, int version) async {
  // ... create tables ...
  await _seedData(db); // ← ran on EVERY fresh install, before Supabase check
}
```
Even after fixing the init order, `_seedData()` had already written hardcoded data during `openDatabase()`, before `_loadAll()` even ran its empty-check.

**Layer 3 — `firstSyncFromRemote()` returned `bool` not enum:**
```dart
final synced = await SyncService.instance.firstSyncFromRemote(); // returned bool
if (synced) { ... }
else { await db.reseed(); } // ← couldn't distinguish "Supabase empty" from "unreachable"
```
If Supabase was unreachable, it fell into `else` and reseeded with hardcoded data. There was no way to say "don't seed, just retry."

#### Solution chosen

**Fix 1 — Correct init order:**
```dart
await SupabaseService.initialize(); // FIRST
final dataProvider = AppDataProvider();
await dataProvider.initialize();    // SECOND
```

**Fix 2 — Remove seed from `_onCreate()`:**
`_onCreate()` now creates empty tables only. No seed data. Tables start completely empty.

**Fix 3 — Replace `bool` return with `SyncFirstResult` enum:**
```dart
enum SyncFirstResult { success, supabaseEmpty, unreachable }
```
- `success` → Supabase had real data → use it
- `supabaseEmpty` → Supabase is reachable but empty → first device ever → seed locally
- `unreachable` → Cannot reach Supabase → retry, never seed

**Fix 4 — Retry loop with UI feedback:**
```dart
for (int i = 2; i <= 8; i++) {
  // show "Attempt i of 8" on screen
  await Future.delayed(Duration(seconds: 3));
  final result = await SyncService.instance.firstSyncFromRemote();
  if (result == SyncFirstResult.success) { ... return; }
  if (result == SyncFirstResult.supabaseEmpty) { ... return; }
  // unreachable — keep trying
}
// All 8 failed → show error screen with Retry button
// NEVER write hardcoded data
```

**Fix 5 — `_seedAndLoad()` calls `db.seedData()` directly, not `db.reseed()`:**
`reseed()` drops tables then calls `_onCreate()` which no longer seeds — leaving the DB permanently empty. `seedData()` writes directly into the already-open empty tables.

#### Why this approach
The enum makes intent explicit. Code can never accidentally fall into seed-on-failure because the three outcomes are structurally separate. The retry loop with progressive UI feedback gives users transparency instead of a frozen screen. The error screen gives them agency (Retry button) instead of silent failure.

#### Better solution
Background retry with exponential backoff after the error screen:
- Retry after 1 min → 2 min → 4 min → until success
- App shows an empty state (no data) rather than blocking login
- Staff can still use the app locally and sync later

---

### Bug 11 — `is_deleted` Type Cast Crash (Supabase Bool vs SQLite Int)
**Severity:** High · **Phase:** Week 4

#### What happened
```
SyncService.firstSyncFromRemote error:
type 'bool' is not a subtype of type 'int?' in type cast
DatabaseHelper.upsertItemFromRemote (database_helper.dart:268)
```
First sync would reach Supabase, pull data successfully, then crash while writing items to SQLite. Returned `unreachable`. Retried 20 times. Showed error screen.

#### Root cause
```dart
'is_deleted': remote['is_deleted'] == true ? 1 : (remote['is_deleted'] as int? ?? 0),
```
Supabase stores `is_deleted` as PostgreSQL `boolean` → arrives in Dart as `bool` (`false`).
SQLite stores it as `INTEGER` (0 or 1).
The cast `as int?` on a `bool` value throws at runtime.

#### Solution chosen
```dart
'is_deleted': (remote['is_deleted'] == true || remote['is_deleted'] == 1) ? 1 : 0,
```
Handles both cases: Supabase `bool` and SQLite `int`. No cast — direct comparison.
Applied identically to `upsertItemFromRemote`, `upsertLocationFromRemote`.

#### Why this matters architecturally
This is a **type boundary problem** — the place where two different type systems meet (PostgreSQL booleans → Dart → SQLite integers). Every field crossing this boundary needs explicit conversion. The lesson: never use `as TypeName` when reading from external APIs. Always use explicit conversion with fallback.

#### Better solution
Define a mapper layer between Supabase responses and SQLite inserts. A `SupabaseMapper` class that handles all type conversions in one place. Makes boundary bugs visible and testable.

---

### Bug 12 — Pending Sync Not Flushing on Network Restore
**Severity:** Medium · **Phase:** Week 3

#### What happened
Staff records a movement while offline. Internet comes back. App still shows pending for 30+ seconds instead of syncing immediately.

#### Root cause
`_connectivitySub` fired `sync(silent: true)` on reconnect — correct.
But `_isReachableCached()` returned the cached `false` from 30 seconds ago.
Sync immediately bailed out before making any network call.

```dart
final reachable = await _isReachableCached(); // returns cached false
if (!reachable) return; // exits immediately — never syncs
```

#### Solution chosen
Clear the reachability cache immediately on connectivity restore:
```dart
_connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
  final online = result != ConnectivityResult.none;
  if (online) {
    _invalidateReachabilityCache(); // ← clears cached false
    sync(silent: true);             // ← now actually checks Supabase
  }
});
```

---

### Bug 13 — Movements Missed After Long Offline Gap
**Severity:** Medium · **Phase:** Week 3

#### What happened
Device goes offline for 2 hours. Comes back online. Periodic sync runs. But movements made by other devices during the 2-hour gap don't appear.

#### Root cause
Pull window was `lastSyncAt - 2 minutes`. If a device was offline for 2 hours, it only pulled the last 2-minute overlap — missing everything from the gap.

#### Solution chosen
Increased overlap buffer to 5 minutes:
```dart
final since = _lastSyncAt != null
    ? _lastSyncAt!.subtract(const Duration(minutes: 5))
    : DateTime.now().subtract(const Duration(days: 30));
```
First sync ever pulls 30 days of history.

#### Better solution
Track `lastSyncAt` in SQLite (persistent across app restarts). If device was offline for 6 hours and restarts, `lastSyncAt` would be 6 hours ago and the pull window would be correct. Currently `lastSyncAt` is in-memory — resets to null on app restart, which triggers the 30-day fallback (correct but expensive).

---

### Bug 14 — `connectivity_plus` 5.x Breaking API Change
**Severity:** Medium · **Phase:** Week 1

#### What happened
App crashed on network state change. Background sync stopped working entirely.

#### Root cause
`connectivity_plus` 5.x changed `onConnectivityChanged` to emit `List<ConnectivityResult>` instead of single `ConnectivityResult`. Code was written for the old API — treating a List as a single value.

#### Solution chosen
Checked installed version (5.0.2) — on Android 5.0.2 still emits a single value despite the API contract change. Used single-value check:
```dart
_connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
  final online = result != ConnectivityResult.none;
});
```
Pinned version in pubspec.yaml to prevent accidental upgrade.

---

### Bug 15 — Home Screen Sync Dot Always Green
**Severity:** Low · **Phase:** Week 2

#### What happened
Home screen showed green "all synced" dot even when 8 movements were pending. Staff had no visual indication that data hadn't uploaded.

#### Root cause
`_SyncStatusRow` received `pending` count as a parameter but hardcoded the green dot and "all synced" text — never used the parameter.

#### Solution chosen
```dart
final hasPending = pending > 0;
// Amber dot + "8 pending" when hasPending
// Green dot + "all synced" when !hasPending
```

---

### Bug 16 — Dropdown Crash After Realtime Sync (Stale Object Reference)
**Severity:** High · **Phase:** Week 4 · **Screen:** AddMovementScreen + EditSheet

#### What happened
```
Failed assertion: line 1830 pos 10:
'items == null || items.isEmpty || ... items.where((item) =>
item.value == (initialValue ?? value)).length == 1'
```
App crashed whenever a realtime sync fired while the user had the Add Movement screen open, or while the edit sheet was open in History. The selected location in the dropdown would cause an assertion failure.

#### Root cause
When `_reloadMasterData()` runs after a realtime event:
```dart
_locations..clear()..addAll(_safeParseLocations(results));
notifyListeners();
```
This creates **brand new `LocationModel` objects** from fresh DB rows — same IDs, different objects in memory. Flutter then calls `build()` on every listening widget.

Inside `AddMovementScreen.build()`, `_selectedFrom` still holds the **old** `LocationModel` instance. Flutter's `DropdownButton` iterates the items list comparing each item's value with the selected value using `==`, which defaults to **object identity** (`identical()`) since `LocationModel` doesn't override `==`.

```
_selectedFrom  = LocationModel@0x1a2b  (OLD instance, from before sync)
items list     = [LocationModel@0x3c4d, LocationModel@0x5e6f, ...]  (NEW instances)

OLD == any NEW → false for all → 0 matches found → assertion: must be exactly 1 → CRASH
```

The same crash occurs in the history screen edit sheet with `_fromLoc` and `_toLoc`.

#### Why the existing safeValue guard wasn't enough
`AddMovementScreen._buildLocationField()` had:
```dart
final safeValue = available.any((l) => l.id == value?.id) ? value : null;
```
This correctly detects the mismatch and returns `null` — but `null` clears the user's selection visually. Worse, on the first build frame after the sync the guard runs *after* Flutter has already begun validating the dropdown, so the assertion fires before the guard can prevent it.

#### Solution chosen
Re-resolve selected values from the **live list by ID** at the very start of every `build()`, before any widget is constructed:

```dart
@override
Widget build(BuildContext context) {
  final data = context.watch<AppDataProvider>();
  final locs = data.locations;

  // Re-resolve on every build — realtime sync creates new object instances
  if (_selectedFrom != null) {
    final fresh = locs.where((l) => l.id == _selectedFrom!.id).firstOrNull;
    if (fresh != null && !identical(fresh, _selectedFrom)) _selectedFrom = fresh;
    else if (fresh == null) _selectedFrom = null; // deleted remotely
  }
  if (_selectedTo != null) {
    final fresh = locs.where((l) => l.id == _selectedTo!.id).firstOrNull;
    if (fresh != null && !identical(fresh, _selectedTo)) _selectedTo = fresh;
    else if (fresh == null) _selectedTo = null;
  }
  // Same for _selectedItem from data.items
```

Applied identically in:
- `add_movement_screen.dart` — `_selectedFrom`, `_selectedTo`, `_selectedItem`
- `history_screen.dart` edit sheet — `_fromLoc`, `_toLoc`

#### Why this works
By the time any `DropdownButton` widget is built, the selected value is guaranteed to be the exact same object instance that exists in the items list. `==` comparison finds exactly one match. Assertion passes.

If the location was deleted on another device while this screen was open, `fresh == null` → selected value set to null → dropdown shows unselected cleanly instead of crashing.

#### Why not override `==` on LocationModel?
It seems simpler — just make `LocationModel == LocationModel` compare by ID:
```dart
@override
bool operator ==(Object other) => other is LocationModel && other.id == id;
```
This works but has a hidden risk: two stale objects with the same ID but different `name` or `type` fields would compare as equal, masking bugs where the UI shows outdated data. The re-resolution approach is more explicit and guarantees the UI always shows the current object, not just an ID-matching one.

#### The general lesson
Any Flutter screen that holds a `ChangeNotifier` object reference as local state (`_selectedFrom = someModel`) will crash if the notifier replaces its list with new instances. The correct pattern:

```
Never store ChangeNotifier objects directly in widget state.
Store the ID. Resolve the object from the live list on every build.
```

Or: make your models immutable with value equality (`freezed` package), so `==` compares by field value and object identity doesn't matter.

---

## Performance Optimisations

### P1 — Stock Cache
Stock is calculated from the full movements list. Recalculating on every UI rebuild (which happens on every `notifyListeners()`) would be O(items × locations × movements). Added a cache that invalidates only on mutations.

### P2 — Background Isolate Parsing
Model parsing (converting `Map<String,dynamic>` rows to typed models) runs in a separate Dart isolate via `compute()`. Main thread never blocks on startup data load.

### P3 — Debounced Notify
Batch rapid `notifyListeners()` calls into one per 16ms frame. Prevents multiple rebuilds when 10 realtime events arrive in quick succession.

### P4 — SQL Stock Calculation
Stock was originally computed in Dart: triple nested loop over items, locations, movements — O(n³). Replaced with a single SQL query using `SUM(CASE WHEN ...)` — runs in O(1) indexed SQL.

### P5 — Sorted Movements Cache
`sortedMovements` was re-sorting the full list on every build. Cached with dirty flag — only re-sorts when `_movements` changes.

---

## What I Would Do Differently (Honest Reflection)

| Decision | What I Did | What I'd Do With More Time |
|---|---|---|
| ID generation | Sequential + separate DB | UUID package — no DB, no deadlocks |
| Type boundaries | `.toString()` everywhere | Typed mapper models per table |
| State management | Single Provider | Riverpod — better code splitting, testable |
| Sync engine | Custom SyncService | drift + Supabase realtime — reactive streams |
| Error handling | try/catch + debugPrint | Proper error model + Sentry/Crashlytics |
| Testing | None | Unit tests for SyncService, integration tests for fresh install flow |
| Security | SharedPreferences for staff ID | flutter_secure_storage |
| Models | Mutable classes, no `==` override | `freezed` package — immutable + value equality, eliminates stale reference crashes |

---

## Design Decision — Real-Time Stock Tracking Per Location

### The Question
Once the app was working, the natural next requirement was: *"How do we know how much of each item is in each location in real time?"*

The instinctive answer for most developers is to add a column:

```sql
items table: item_id | item_name | current_location | quantity
```

This feels simple. It is wrong.

---

### Why a "current_location" Column Fails

| Scenario | Why it breaks |
|---|---|
| 100 pcs of item X split across Godown A (60 pcs) and Godown B (40 pcs) | One column cannot hold two locations simultaneously |
| Partial transfer — move 30 out of 60 pcs from Godown A | Which location is "current"? The item still exists in both |
| Two devices update simultaneously | Race condition — last write wins, quantity is silently lost |
| You need audit history | Column shows only now — you can never reconstruct how it got there |
| Stock reconciliation | No way to verify the number is correct — no trail to audit against |

This is a fundamental data modelling mistake: storing a **derived value** (current stock) instead of the **source events** (movements) that produce it.

---

### The Correct Approach — Event Sourcing via Movements

The architecture already in place is the right one:

```
Stock at a location = Total moved INTO that location
                    − Total moved OUT OF that location
```

This is **double-entry bookkeeping** — the same principle accountants have used for 500 years, and the same model used by every serious inventory system (SAP, Tally, Zoho, QuickBooks).

Every stock movement is an immutable event:
```
Movement: item=60*90 Dabangg, qty=80, from=Godown A, to=Shop, by=Ramesh, at=10:40
```

Stock is always **calculated**, never **stored**. This means:
- Stock is always correct by definition — derived from the actual event log
- Full audit trail included for free — every movement is traceable
- No sync conflict possible on stock numbers — only movements sync, and they use last-write-wins on `updated_at`

---

### The SQL That Makes It Work

```sql
SELECT
  i.item_name,
  l.location_name,
  SUM(CASE WHEN m.to_location   = l.location_id THEN m.quantity ELSE 0 END) AS incoming,
  SUM(CASE WHEN m.from_location = l.location_id
           AND m.from_location != 'SUPPLIER'    THEN m.quantity ELSE 0 END) AS outgoing,
  incoming - outgoing AS balance
FROM items i
CROSS JOIN locations l
LEFT JOIN movements m ON m.item_id = i.item_id
WHERE i.is_deleted = 0 AND l.is_deleted = 0
GROUP BY i.item_id, l.location_id
HAVING incoming > 0 OR outgoing > 0
ORDER BY l.location_name, i.item_name
```

**`CROSS JOIN`** — pairs every item with every location. This is intentional: we need to check all combinations to find where each item exists.

**`SUPPLIER` exclusion** — opening stock arrives from a special `from_location = 'SUPPLIER'` constant. It is excluded from outgoing calculations because SUPPLIER is not a real location — it's the origin point for initial inventory.

**`HAVING incoming > 0 OR outgoing > 0`** — filters out the empty combinations. No row returned for items that have never touched a location.

---

### Concrete Example

```
Opening stock entry:  SUPPLIER → Godown A,  200 pcs (60*90 Dabangg)
Transfer:             Godown A → Shop,        80 pcs
Transfer:             Godown A → Godown B,    50 pcs

SQL result:
  Godown A | 60*90 Dabangg | incoming=200 | outgoing=130 | balance=70  ✅
  Shop     | 60*90 Dabangg | incoming=80  | outgoing=0   | balance=80  ✅
  Godown B | 60*90 Dabangg | incoming=50  | outgoing=0   | balance=50  ✅
  Total    |               |              |              | balance=200 ✅ (200 in = 200 accounted for)
```

The total across all locations always equals the total brought in from SUPPLIER. This is the self-verification property of double-entry bookkeeping — you can always audit correctness.

---

### How Real-Time Sync Works for Stock

When Device A records a movement:
```
1. Write movement to local SQLite immediately (sync_status = 'pending')
2. Recalculate stock from movements table → UI updates instantly on Device A
3. Push movement to Supabase in background
4. Supabase Realtime fires → Device B receives the movement record
5. Device B upserts movement into its local SQLite
6. Device B calls _refreshStockCache() → stock recalculated
7. Device B stock screen rebuilds → shows correct numbers
```

No separate stock table in Supabase. No sync conflicts on stock numbers. Stock is always a view computed from movements — and movements are the only thing that syncs.

---

### Why This Scales

- **Add a new location?** No migration needed. Old movements still calculate correctly because they reference location IDs, not names.
- **Delete an item?** Soft delete — movements still exist, historical stock is preserved.
- **10,000 movements?** SQL with indexes on `item_id`, `from_location`, `to_location` handles this in milliseconds. The calculation runs on SQLite's background thread.
- **Multiple devices recording simultaneously?** Each movement is an independent record. No two movements share a primary key (human-readable ID with sequence + date). Merge is always safe.

---

### Interview Talking Point
> *"How do you track where inventory is located in real time?"*

**Answer:** We don't store location on the item — we derive it. Every stock movement is recorded as an immutable event: item, quantity, from-location, to-location, staff, timestamp. Current stock at any location is calculated as total-in minus total-out from the movements table. This is double-entry bookkeeping — the same model accounting software has used for decades. It gives us a full audit trail for free, eliminates sync conflicts on stock numbers entirely, and makes the data self-verifying: the sum of stock across all locations always equals the total received from suppliers.

---

## Key Interview Talking Points

### "Tell me about a hard bug you faced."
**The fresh install duplicate data bug.** Three independent bugs stacked on each other — wrong initialisation order, seed running before Supabase check, and a boolean return type that couldn't distinguish "empty" from "unreachable." Had to trace the full execution path from `main()` through `DatabaseHelper._onCreate()` to find all three. The fix required an enum (`SyncFirstResult`) to make the three outcomes structurally separate so no future code could accidentally conflate them.

### "How did you handle offline-first sync?"
SQLite is always written first. Movements get `sync_status = 'pending'`. A background `SyncService` pushes pending records when online, pulls remote changes since last sync, and subscribes to Supabase Realtime for instant updates. The key design decision: Supabase is a relay, not source of truth. This means the app works with zero connectivity and gracefully degrades.

### "What would you do differently?"
Replace the custom ID generator with the `uuid` package — eliminates the deadlock risk and the duplicate-ID-on-reinstall bug in one move. Replace the manual in-memory sync tracking with reactive SQLite streams via `drift` — `pendingSyncCount` becomes a `Stream<int>` that auto-updates. Use typed mapper models at the Supabase boundary to catch type mismatches at compile time instead of runtime crashes.

### "How do you handle conflicts when two devices edit the same record?"
Last-write-wins based on `updated_at` timestamp. `upsertMovementFromRemote()` checks local `updated_at` against remote — if remote is newer, overwrite; if local is same or newer, skip. This is a conscious trade-off: simple and predictable, but could overwrite a valid local edit if clocks are skewed. Better solution for v2.0: vector clocks or operational transforms, but overkill for 7 devices in the same building.

### "How do you handle UI state when realtime data changes under the user?"
Realtime sync replaces model lists with new object instances. Any widget holding a direct reference to an old instance crashes Flutter's `DropdownButton` assertion — it expects the selected value to be `==` to exactly one item in the list, and `==` defaults to object identity. The fix: re-resolve all selected values from the live list by ID at the start of every `build()`. If an item was deleted remotely while the user had it selected, it gracefully clears the selection instead of crashing. The deeper lesson: never store `ChangeNotifier` object references in widget state — store the ID and resolve the object on demand. The proper long-term fix is using the `freezed` package to make models immutable with value equality, so object identity doesn't matter at all.

### "How did you approach debugging with no access to the device terminal?"
Added a visible debug overlay on the loading screen — shows sync status, URL presence, and retry attempt count directly on screen. This let me diagnose issues on phones receiving APKs over WhatsApp without USB connection. For USB-connected debugging: `adb logcat -s flutter` gives the full log stream. For simulating fresh install without uninstalling: `adb shell pm clear com.example.godown_inventory` clears all app data including SQLite.

### "How do you track where each item is located in real time?"
We don't store location on the item record — we derive it from movements. Every transfer is recorded as an immutable event: item, quantity, from-location, to-location, staff, timestamp. Stock at any location is calculated as total-in minus total-out. This is double-entry bookkeeping — the same model used by SAP, Tally, and every serious inventory system. The naive approach — adding a `current_location` column to the items table — breaks immediately when an item is split across two locations, or when two devices update the same record simultaneously (race condition, silent data loss). The event-sourcing approach is conflict-free by design, self-auditing (sum of all locations always equals total received from supplier), and gives complete movement history for free.

---

### Bug 17 — `is_deleted` Bool/Int Cast Crash on Fresh Install
**Severity:** Critical · **Phase:** Checkpoint 3

#### What happened
```
SyncService.firstSyncFromRemote error:
type 'bool' is not a subtype of type 'int?' in type cast
DatabaseHelper.upsertItemFromRemote (database_helper.dart:268)
```
Fresh install would reach Supabase, pull data successfully, then crash while writing items to SQLite. Returned `unreachable`. Retried 20 times. Showed error screen. Real data never loaded.

#### Root cause
```dart
'is_deleted': remote['is_deleted'] == true ? 1 : (remote['is_deleted'] as int? ?? 0),
```
Supabase stores `is_deleted` as PostgreSQL `boolean` → arrives in Dart as `bool` (`false`). SQLite stores it as `INTEGER`. The cast `as int?` on a `bool` value throws at runtime. Same problem in `upsertLocationFromRemote`.

#### Solution
```dart
'is_deleted': (remote['is_deleted'] == true || remote['is_deleted'] == 1) ? 1 : 0,
```
Handles both cases — Supabase `bool` and SQLite `int`. No cast. Applied to `upsertItemFromRemote` and `upsertLocationFromRemote`.

#### The lesson
This is a type boundary problem — the place where PostgreSQL booleans meet Dart meet SQLite integers. Never use `as TypeName` when reading from external APIs. Always use explicit comparison with fallback.

---

### Bug 18 — Release APK Shows Blank/White Screen
**Severity:** Critical · **Phase:** Distribution

#### What happened
Debug APK via USB worked perfectly. Release APK sent via WhatsApp showed a completely blank white screen on other phones. No crash, no error visible to the user.

#### Root cause — Two separate issues discovered

**Issue 1 — Wrong assumption:** Initially suspected the APK was crashing. Connected the phone via USB and ran `adb logcat | Select-String "flutter"`. Logs showed the app was running, loading screen was working, but:
```
Failed host lookup: 'jbkbwqprwbkqoduwghjp.supabase.co'
errno = 7 — No address associated with hostname
```
20 retries, all failed → error screen shown. Not a white screen crash — it was the loading/error screen working correctly but taking 100 seconds (20 × 5s).

**Issue 2 — Missing INTERNET permission in AndroidManifest.xml:** The real root cause. `android/app/src/main/AndroidManifest.xml` had no INTERNET permission:
```xml
<!-- This was missing -->
<uses-permission android:name="android.permission.INTERNET"/>
```

#### Why debug worked but release didn't
Flutter's debug builds automatically merge `android/app/src/debug/AndroidManifest.xml` which Flutter injects INTERNET permission into for development convenience. Release builds only use `src/main/AndroidManifest.xml` — no automatic injection. Android silently blocks all DNS lookups rather than throwing a "permission denied" error, which manifests as `Failed host lookup` — the same error as having no internet at all.

#### Solution
Added to `android/app/src/main/AndroidManifest.xml`:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        ...
```

Rebuilt release APK → installed → connected to Supabase on first attempt.

#### Does SQLite need storage permission?
No. `sqflite` uses the app's internal private storage at `/data/data/com.package.name/`. Android permissions are only required for shared external storage (Downloads, SD card). Internal app storage is always accessible without any permission.

#### Interview talking point
> *"What's different between debug and release APKs in Flutter?"*

Several things: debug uses JIT compilation (slower, enables hot reload), release uses AOT (faster, smaller). Debug builds automatically inject the INTERNET permission and enable debugging tools. Release builds are stripped of debug symbols and only include what's explicitly declared. The most common gotcha: INTERNET permission works in debug because Flutter injects it, but the release APK can't reach the network until you add it to the main manifest yourself. `debugPrint()` statements are completely silent in release — no performance impact, no output.

---

### Bug 19 — Splash/Loading Screen Showing on Every Launch
**Severity:** Medium · **Phase:** Checkpoint 3

#### What happened
Loading screen condition in `main.dart`:
```dart
if (data.isLoading || (!data.syncFailed && data.staff.isEmpty))
```
On existing devices (not fresh install), SQLite already has data. `data.staff.isEmpty` is briefly `true` while `_loadAll()` runs. This caused a flash of the loading screen on every app launch even when data was already present.

#### Solution
`data.isLoading` covers the loading period correctly. The `data.staff.isEmpty` condition is only needed for fresh install detection which is already handled inside `_handleFreshInstall()`. The loading screen shows only while `isLoading = true` — which is set to `false` in the `finally` block of `initialize()` after all data is loaded.

---

## Current Working State (Checkpoint 3 — March 2026)

```
✅ Fresh install: connects to Supabase, loads real data, shows login
✅ Existing install: loads SQLite instantly, shows login  
✅ Realtime sync: movements appear on all devices in < 1 second
✅ Stock calculation: derived from movements, always correct
✅ Offline mode: works without internet, syncs when reconnected
✅ Loading screen: blue branded screen with GI logo + retry dots
✅ Error screen: shown after 20 failed retries with Retry button
✅ Release APK: builds and distributes correctly via WhatsApp
✅ INTERNET permission: added to AndroidManifest.xml
✅ Dropdown crash: fixed — stale references re-resolved on every build
```

---

## Tech Stack Reference

```yaml
# pubspec.yaml (key dependencies)
sqflite: 2.4.2              # SQLite — local database
path: 1.9.1                 # File path utilities
provider: 6.1.5+1           # State management
supabase_flutter: 2.12.0    # Cloud sync + realtime
connectivity_plus: 5.0.2    # Network detection (pinned — 6.x breaking)
intl: 0.19.0                # Date formatting
shared_preferences: 2.5.4   # Login persistence (staff ID)
```

---

## App Screens

| Screen | Purpose |
|---|---|
| Login | PIN-based staff authentication |
| Home | Navigation hub + sync status indicator |
| Add Movement | Record stock transfer between locations |
| Stock | Real-time stock levels by location and item |
| History | Full movement log with edit capability |
| Manage | Admin CRUD for items, locations, staff |
| Sync | Pending/synced counts + manual sync trigger |

---

*Document version: Checkpoint 3 — March 2026*
*App version: v1.0.0 — Single shop · 7 devices · Offline-first*
*Last updated: Bugs 17-19 added · INTERNET permission fix · Release APK working*