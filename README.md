
# Godown Manager

Real-time inventory management app built for Sri Baba Traders — a wholesale textile business running 9 warehouses across 7 staff devices.

Built to replace paper registers with instant, accurate, offline-first stock tracking.

---

## What it does

- Records every stock movement instantly across 9 godowns
- Syncs across 7 Android devices in under 1 second via Supabase Realtime
- Works completely offline — syncs automatically on reconnect
- Full movement history with staff name, timestamp, quantity, and route
- Role-based access — Admin and Staff with separate permissions
- Stock calculated from movements — never stored directly (double-entry bookkeeping)

---

## Tech Stack

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-07405E?style=for-the-badge&logo=sqlite&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)

| Layer | Technology |
|---|---|
| Frontend | Flutter 3.x |
| Local database | SQLite via sqflite |
| Cloud sync | Supabase (PostgreSQL + Realtime) |
| State management | Provider |
| Distribution | APK via WhatsApp |

---

## Architecture

```
User Action
    ↓
AppDataProvider (in-memory state + validation)
    ↓
DatabaseHelper (SQLite — source of truth)
    ↓
SyncService (push pending → pull remote → merge)
    ↓
SupabaseService (WebSocket + HTTP)
    ↓
Supabase Cloud (relay — NOT source of truth)
    ↓
Other Devices (realtime merge → UI update)
```

**Key principle:** SQLite is always written first. Supabase is a sync relay, not the data authority. Every write gets `sync_status = 'pending'` — the queue survives crashes, restarts, and days offline.

---

## Data Model

Stock is never stored directly. It is always calculated:

```sql
stock at location X = total moved INTO X − total moved OUT OF X
```

Every movement is an immutable event. This gives:
- Full audit trail for free
- No sync conflicts on stock numbers
- Self-verifying data — sum across all locations always equals total received from supplier

---

## Screens

| Screen | Purpose |
|---|---|
| Login | PIN-based staff authentication |
| Home | Navigation + live sync status |
| Add Movement | Record stock transfer between locations |
| Stock | Real-time stock levels by item and location |
| History | Full movement log with edit capability |
| Manage | Admin CRUD for items, locations, staff |
| Sync | Pending count + manual sync trigger |

---

## Sync Architecture

```
Movement saved → pushNow() immediately
Master data changed → markMasterDirty() → push immediately
Incoming changes → Supabase Realtime WebSocket (instant)
Fallback → pull every 5 min (catches missed realtime events)
On reconnect → pushNow() drains entire pending queue
On app resume → reconnectRealtime() + pushNow()
Cold start → delta pull (only records changed since last sync)
```

No 30-second polling. Every push is event-driven.

---

## Key Engineering Decisions

**Offline-first over cloud-first**
Warehouses have patchy internet. App must work with zero connectivity. SQLite write always happens before any network call.

**Supabase over Firebase**
Relational schema with foreign keys maps naturally to PostgreSQL. Firestore's document model adds complexity for no benefit. Supabase Realtime via WebSocket — no polling needed.

**Provider over Riverpod/Bloc**
Single `AppDataProvider` is sufficient for this scope. Complexity of Riverpod not justified for a single-shop v1.0.

**Human-readable IDs over UUIDs**
Format: `MOV-00001-20260322`. Staff verbally reference IDs. A UUID is unusable in a warehouse conversation.

**Delta sync**
`last_sync_at` persisted to SQLite `app_settings` table. Cold start pulls only records changed since last sync. Scales as data grows — more data means more efficient, not slower.

---

## Notable Bugs Fixed

| Bug | Root Cause | Fix |
|---|---|---|
| SQLite deadlock on startup | `_seedData()` called inside `_onCreate()` transaction — blocked IdGenerator | Moved seed call after transaction closes |
| Duplicate entries in Supabase | No dirty tracking — pushed all records every sync | Added `_masterDataDirty` flag |
| Fresh install showed fake data | 3 bugs stacked: wrong init order, seed before Supabase check, bool return type | Fixed init order + `SyncFirstResult` enum |
| WebSocket never reconnected | `onResubscribe` never wired, no lifecycle observer, no heartbeat | Wired callback + `WidgetsBindingObserver` + 30s heartbeat |
| Stock wrong after remote movement | `_refreshStockCache()` missing from `mergeRemoteMovement()` | Added cache refresh after every remote merge |
| Dropdown crash during realtime sync | Stale object references in widget state | Re-resolve all selected values by ID on every `build()` |
| Release APK white screen | Missing `INTERNET` permission in `AndroidManifest.xml` | Added permission — Flutter injects it in debug but not release |

Full bug log with root cause analysis documented in [`docs/`](./docs).

---

## Project Status

```
✅ Offline-first sync        ✅ Real-time across 7 devices
✅ Stock calculation          ✅ Full movement history
✅ Role-based access          ✅ Delta sync
✅ WebSocket auto-reconnect   ✅ Release APK distributed
```

**v1.0** — Single shop, 7 devices, production use daily.
**v2.0 planned** — Multi-shop SaaS with Row Level Security and Shop Admin auth.

---

## Contact

Built by **NAVEEN KUMAR DUGAR**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/naveen-kumar-dugar-b23713169/)
[![Gmail](https://img.shields.io/badge/Gmail-D14836?style=for-the-badge&logo=gmail&logoColor=white)](mailto:nkumardugar@gmail.com)
[![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/naveeneducation55-cpu)

