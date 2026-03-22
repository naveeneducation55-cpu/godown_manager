# 📦 Offline Godown Inventory Management App

### Simple Real-Time Stock Tracking System

Version: 1.0  
Goal: Replace paper + register workflow with a simple mobile app that
records stock movements in real time.

\---

# 1\. Problem Statement

Current workflow:

Staff takes goods from godown  
↓  
Writes on paper  
↓  
End of day entry in register  
↓  
Stock becomes incorrect  
↓  
Godown mismatches occur

Problems:

* delayed entries
* human errors
* incorrect stock data
* difficult reconciliation
* no real time visibility

\---

# 2\. Solution Overview

Build a simple mobile inventory app where staff records every stock
movement instantly.

Example workflow:

Open App  
↓  
Select Item  
↓  
Enter Quantity  
↓  
Select From Location  
↓  
Select To Location  
↓  
Press SAVE

Stock updates instantly.

\---

# 3\. Core Requirements

### Functional Requirements

The system must allow:

1. Add stock movement
2. Edit stock movement
3. Track movement history
4. Display real-time stock
5. Work offline
6. Sync across devices
7. Show edited records
8. Track who edited and when

\---

# 4\. Main Entities

System contains:

* Items
* Locations (Godowns + Shop)
* Stock Movements
* Staff

\---

# 5\. Database Design

Use SQLite locally.

Optional cloud sync using Firebase or Supabase.

## Items Table

column       type

\---

item\_id      integer (PK)
item\_name    text
unit         text
created\_at   datetime
updated\_at   datetime
is\_deleted   boolean

Example:

item\_id   name    unit

\---

1         Rice    kg
2         Sugar   kg

\---

## Locations Table

column          type

\---

location\_id     integer
location\_name   text
type            text (godown/shop)
created\_at      datetime
updated\_at      datetime
is\_deleted      boolean

Example:

id   name

\---

1    Godown A
2    Godown B
3    Shop

\---

## Staff Table

column       type

\---

staff\_id     integer
staff\_name   text
pin          text
created\_at   datetime

Example:

id   name

\---

1    Ramesh
2    Suresh

\---

## Stock Movements Table

column          type

\---

movement\_id     integer
item\_id         integer
quantity        number
from\_location   integer
to\_location     integer
staff\_id        integer
created\_at      datetime
updated\_at      datetime
edited          boolean
edited\_by       integer
sync\_status     text

\---

# 6\. Movement Example

Item: Rice  
Qty: 50  
From: Godown A  
To: Shop  
Staff: Ramesh  
Time: 10:40 AM

Database representation:

item\_id: 1  
qty: 50  
from\_location: 1  
to\_location: 3  
staff\_id: 1  
created\_at: 2026-03-15 10:40  
edited: false

\---

# 7\. Edit Behaviour

Original entry:

Rice 50  
Godown A → Shop

Edited entry:

Rice 60  
Godown A → Shop

Database update:

edited = true  
edited\_by = staff\_id  
updated\_at = timestamp

History screen must show:

Edited by Ramesh  
15:42 PM

\---

# 8\. Stock Calculation Logic

Stock is calculated.

Stock = Incoming - Outgoing

Example for Godown A Rice:

Incoming:

200 from supplier  
50 from Godown B

Outgoing:

80 to shop  
40 to Godown C

Stock:

250 - 120 = 130

\---

# 9\. User Interface

The UI must be extremely simple.

Large buttons.  
Minimal text.

\---

# 10\. Main Screens

## Home Screen

ADD MOVEMENT  
VIEW STOCK  
HISTORY  
MANAGE ITEMS  
MANAGE GODOWNS

\---

## Add Movement Screen

Item \[Rice ▼]

Quantity \[50]

From \[Godown A ▼]

To \[Shop ▼]

\[SAVE]

\---

## Stock Screen

Rice

Godown A : 350  
Godown B : 120  
Shop : 40

\---

## History Screen

10:40 AM  
Rice 50  
Godown A → Shop  
Staff: Ramesh

Edited: No

\---

# 11\. Offline Capability

All data stored locally using SQLite.

When internet is available:

Local DB → Sync Service → Cloud DB → Other Devices Sync

\---

# 12\. Sync Rules

Each movement has sync\_status.

Values:

pending  
synced

Process:

create movement  
save locally  
sync queue  
push to server  
mark synced

\---

# 13\. Conflict Handling

If two devices edit same record:

latest updated\_at wins

\---

# 14\. Technology Stack

Mobile App: Flutter

Local Database: SQLite (sqflite package)

Backend Sync: Firebase or Supabase

\---

# 15\. Development Phases

## Phase 1 --- Project Setup

Create Flutter project  
Install packages  
sqflite  
state management

\---

## Phase 2 --- Database Layer

Create tables:

items  
locations  
staff  
movements

Implement CRUD operations.

\---

## Phase 3 --- Add Movement Screen

Features:

item dropdown  
qty input  
from location  
to location  
save button

Save to SQLite.

\---

## Phase 4 --- Stock Calculation

Implement queries to calculate stock per location.

\---

## Phase 5 --- History Screen

Show movement list including:

item  
qty  
from  
to  
staff  
time  
edited

\---

## Phase 6 --- Edit Movement

Allow staff to edit entries.

Update metadata fields.

\---

## Phase 7 --- Manage Items

Admin can:

add item  
edit item  
delete item

\---

## Phase 8 --- Manage Godowns

Admin can:

add location  
edit location  
delete location

\---

## Phase 9 --- Staff Login

Simple login:

staff name  
PIN

\---

## Phase 10 --- Offline Sync

Background service:

check internet  
sync pending records

\---

# 16\. Performance

Add indexes on:

item\_id  
from\_location  
to\_location  
created\_at

\---

# 17\. Security

Track:

created\_by  
edited\_by  
timestamp

\---

# 18\. Future Improvements

Barcode scanning  
Supplier tracking  
Purchase entries  
Invoice generation  
Stock alerts  
Analytics dashboard

\---

# 19\. Example Daily Workflow

Open App  
↓  
Add Movement  
↓  
Select Rice  
↓  
Enter 50  
↓  
From Godown A  
↓  
To Shop  
↓  
Save

Time taken: < 5 seconds

\---

# 20\. Benefits

Real time stock  
Zero register work  
Less human error  
Fast audits  
Full traceability

\---

# 21\. Deployment

Install APK on:

7 staff phones

Optional:

1 tablet in shop

\---