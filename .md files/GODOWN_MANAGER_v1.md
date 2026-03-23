# Sri Baba Traders — Godown Inventory App
## Project Progress & Reference Document

**App Name:** Godown Inventory  
**Package:** `com.example.godown_inventory`  
**Version:** v1.0.0  
**Stack:** Flutter + SQLite (sqflite) + Supabase  
**Platform:** Android  

---

## Project Structure

```
D:\godown_manager\
├── lib/
│   ├── main.dart
│   ├── app_theme.dart
│   ├── common_widgets.dart
│   ├── router.dart
│   ├── theme_provider.dart
│   ├── config/
│   │   ├── app_config.dart
│   │   └── secrets.dart              ← Supabase keys (never commit)
│   ├── database/
│   │   └── database_helper.dart      ← All SQLite SQL
│   ├── providers/
│   │   └── app_data_provider.dart    ← State + all business logic
│   ├── screens/
│   │   ├── home/home_screen.dart
│   │   ├── login/login_screen.dart
│   │   ├── movement/add_movement_screen.dart
│   │   ├── history/history_screen.dart
│   │   ├── stock/stock_screen.dart
│   │   ├── items/manage_screen.dart
│   │   └── sync/sync_screen.dart
│   ├── services/
│   │   ├── supabase_service.dart     ← All Supabase API calls
│   │   └── sync_service.dart         ← Sync orchestration
│   └── utils/
│       └── id_generator.dart         ← ID format: MOV-00001-20260322
├── assets/
│   └── images/
│       └── app_logo.jpg              ← Sri Baba Traders logo
└── pubspec.yaml
```

---

## Key Files Reference

| File | Purpose | Critical Notes |
|------|---------|----------------|
| `database_helper.dart` | SQLite CRUD, seed data | `_seedData()` runs OUTSIDE transaction to avoid IdGenerator deadlock |
| `app_data_provider.dart` | In-memory state, all CRUD | Must be in `lib/providers/` — imports use `../` not `../../` |
| `sync_service.dart` | Push/pull/realtime orchestration | `markMasterDirty()` triggers master data push |
| `supabase_service.dart` | All Supabase API calls | Realtime subscribed to movements + items + locations + staff |
| `id_generator.dart` | Generates human-readable IDs | Uses separate `id_sequences.db` — DO NOT merge with main DB |
| `secrets.dart` | Supabase URL + anon key | In `.gitignore` — never push to GitHub |

---

## Database Schema

### SQLite Tables (local on device)

```sql
items        — item_id, item_name, unit, created_at, updated_at, is_deleted
locations    — location_id, location_name, type(godown/shop), created_at, updated_at, is_deleted
staff        — staff_id, staff_name, pin, role(admin/staff), created_at
movements    — movement_id, item_id, quantity, from_location, to_location,
               staff_id, created_at, updated_at, edited, edited_by,
               sync_status(pending/synced), remark
id_sequences — prefix, last_seq  ← in separate id_sequences.db
```

### ID Format
```
ITM-00001-20260322   ← items
LOC-00001-20260322   ← locations
STF-00001-20260322   ← staff
MOV-00001-20260322   ← movements
SUPPLIER             ← special constant for opening stock from_location
```

---

## Supabase Setup

**Project URL:** `https://jbkbwqprwbkqoduwghjp.supabase.co`

**Tables required:** `items`, `locations`, `staff`, `movements`

**Realtime must be enabled on:** items, locations, staff, movements

**Important:** No foreign key constraints on movements table — causes push failures when items don't exist yet in Supabase.

**RLS:** Currently disabled — all devices have full access.

---

## Seeded Data (First Launch)

Automatically created on fresh install:

**Items:** 60\*90 Dabangg, 60\*90 Jio Vip, 90\*100 Sonata White, 90\*100 Khubsurat Set, 108\*108 Flora Bedsheet, 70\*90 Metro, 90\*100 Metro, 60\*90 Metro

**Locations:** Godown A, Godown B, Godown C, Shop

**Staff:** Ramesh (admin/1234), Suresh (staff/5678), Dinesh (staff/9012)

**Note:** Seed movements are marked `sync_status = 'synced'` — never pushed to Supabase.

---

## Sync Architecture

```
Device A                    Supabase                    Device B
   │                           │                           │
   │── add movement ──────────►│                           │
   │                           │── realtime event ────────►│
   │                           │                           │── merge movement
   │                           │                           │── update UI
   │                           │                           │
   │── edit item ─────────────►│ (markMasterDirty)         │
   │                           │── realtime event ────────►│
   │                           │                           │── reload items
   │                           │                           │
   │◄── periodic pull (60s) ───│                           │
```

**Sync flow on each periodic sync:**
1. Push master data (items/locations/staff) — only if `_masterDataDirty = true`
2. Push pending movements
3. Pull master data changes since last sync
4. Pull movements since last sync

---

## Key Business Rules

- **Stock validation:** Cannot transfer more quantity than available in from-location
- **SUPPLIER:** Special `from_location` value for opening stock — not editable
- **Last admin protection:** Cannot delete or change role of last admin
- **Self-edit protection:** Cannot change own role
- **Soft deletes:** Items and locations use `is_deleted` flag — never physically deleted
- **Hard delete:** Staff is physically deleted from both SQLite and Supabase

---

## Dependencies

```yaml
sqflite: 2.4.2          # Local SQLite
path: 1.9.1             # File paths
provider: 6.1.5+1       # State management
supabase_flutter: 2.12.0 # Cloud sync
connectivity_plus: 5.0.2 # Network detection
intl: 0.19.0            # Date formatting
shared_preferences: 2.5.4 # Login persistence
```

**SDK:** Dart 3.11.1 / Flutter 3.41.0

---

## GitHub Structure

```
Repository: github.com/naveeneducation55-cpu/godown_manager

Branches:
  main     ← v1.0.0 tagged — production code only
  develop  ← integration branch — merge features here first
  master   ← old branch, ignore

Workflow:
  1. git checkout develop
  2. git checkout -b feature/what-you-are-building
  3. Make changes + commit
  4. Merge into develop
  5. Merge develop → main only for releases
  6. Tag release: git tag -a v1.1.0 -m "description"
```

---

## Bugs Fixed in v1.0.0

| Bug | File | Fix |
|-----|------|-----|
| `fromLocationId == -1` type mismatch | `history_screen.dart` | Changed to `== 'SUPPLIER'` |
| SQL outgoing calc used `!= -1` | `database_helper.dart` | Changed to `!= 'SUPPLIER'` |
| Sync button stayed "pending" | `sync_service.dart` | Added `_markMovementsSyncedInMemory` callback |
| Items/locations/staff not syncing to Supabase | `app_data_provider.dart` | Added `markMasterDirty()` on every CRUD |
| Duplicate Supabase entries | `database_helper.dart` | Seed moved outside transaction, reseed condition tightened |
| Realtime echo loop | `sync_service.dart` | `upsertMovementFromRemote` returns bool, skips echo |
| `connectivity_plus` 5.x crash | `sync_service.dart` | Single `ConnectivityResult` not List |
| IdGenerator deadlock | `database_helper.dart` | `_seedData` moved outside `_onCreate` transaction |
| `upsertMovementFromRemote` type cast crash | `database_helper.dart` | All fields use `.toString()` |
| Home sync row always green | `home_screen.dart` | Shows real pending count with amber dot |
| Stock numbers wrong for opening stock | `database_helper.dart` | SQL excludes `SUPPLIER` from outgoing |
| Foreign key violation on movements push | Supabase | Drop FK constraints on movements table |
| Items/locations/staff not realtime | `supabase_service.dart` | Added realtime subscriptions for all tables |

---

## Known Issues / TODO

| Issue | Priority | Notes |
|-------|----------|-------|
| `reseed()` uses wrong table names (`tMovements` vs `movements`) | Low | Rarely called |
| `items_screen.dart` — Phase 1 dead code | Low | Unused, safe to delete |
| `locations_screen.dart` — stub file | Low | Unused, safe to delete |
| Supabase edits get overwritten by sync | By design | Local SQLite is source of truth — edit only via app |

---

## APK Build & Distribution

```powershell
# Build
flutter build apk --release --tree-shake-icons

# Location
D:\godown_manager\build\app\outputs\flutter-apk\app-release.apk

# Push to device
adb push app-release.apk /sdcard/Download/

# Share via WhatsApp or Google Drive link
```

**Receiving phones:** Enable "Install from unknown sources" in Settings → Security

---

## Reset / Debug Commands

```powershell
# Delete local SQLite (force fresh seed on next launch)
adb shell run-as com.example.godown_inventory rm -f /data/data/com.example.godown_inventory/databases/godown_inventory.db
adb shell run-as com.example.godown_inventory rm -f /data/data/com.example.godown_inventory/databases/id_sequences.db

# Clean build
flutter clean
cd android && .\gradlew clean && cd ..
flutter pub get
flutter run

# Kill background processes
taskkill /F /IM dart.exe
taskkill /F /IM java.exe

# Check package name
adb shell pm list packages | findstr godown

# View logs
flutter logs
```

---

## Planned — v2.0

- Multi-shop support with `shop_id` on all tables
- Supabase Row Level Security (RLS) per shop
- Subscription model — 1500rs/month activated via Supabase dashboard
- `subscriptions` table: `shop_id, active, expires_at, activated_by`
- App locks on expiry, shows payment screen

---

*Last updated: March 2026 — v1.0.0 released*