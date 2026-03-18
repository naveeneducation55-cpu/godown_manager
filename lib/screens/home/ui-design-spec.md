# 📦 Inventory App — Minimal UI Design Spec

## 🎯 Design Philosophy

* Minimal
* Fast interaction (≤ 5 seconds per entry)
* Low cognitive load
* Works for low-tech users
* Clean developer-style aesthetic
* Theme adaptive (Light / Dark)

---

# 🎨 Theme System

```ts
type Theme = "light" | "dark";
```

## Auto Theme Detection

```ts
const theme = window.matchMedia("(prefers-color-scheme: dark)")
  ? "dark"
  : "light";
```

---

## 🎨 Color Palette

### Light Theme

```ts
const lightTheme = {
  background: "#F8FAFC",
  surface: "#FFFFFF",
  primary: "#2563EB",
  secondary: "#64748B",
  text: "#0F172A",
  border: "#E2E8F0",
  success: "#16A34A",
  error: "#DC2626"
};
```

---

### Dark Theme

```ts
const darkTheme = {
  background: "#0F172A",
  surface: "#1E293B",
  primary: "#3B82F6",
  secondary: "#94A3B8",
  text: "#F1F5F9",
  border: "#334155",
  success: "#22C55E",
  error: "#EF4444"
};
```

---

# 🔤 Typography (TypeScript Style)

```ts
font-family: "Inter", "Segoe UI", monospace;
```

Hierarchy:

```ts
Heading: 18px / 600
Body: 14px / 400
Label: 12px / 500
```

---

# 📦 Layout System

```ts
padding: 12px
border-radius: 12px
gap: 10px
```

---

# 🧩 Components

---

## 🔘 Button

```ts
<Button variant="primary" />

styles:
{
  padding: "10px",
  borderRadius: "10px",
  fontWeight: 500,
  border: "1px solid",
}
```

### Variants

```ts
primary   → blue
secondary → gray
danger    → red
```

---

## 🧾 Input Field

```ts
<Input label="Quantity" />
```

Styles:

```ts
border: 1px solid theme.border
border-radius: 10px
padding: 10px
background: theme.surface
```

---

## 📦 Card

```ts
<Card>
  content
</Card>
```

Styles:

```ts
background: theme.surface
border: 1px solid theme.border
border-radius: 12px
padding: 12px
```

---

# 🏠 Home Screen UI

## Layout

```
+----------------------+
| 📦 Inventory App     |
+----------------------+

[ + Add Movement ]
[ 📊 View Stock  ]
[ 🕘 History     ]
[ ⚙ Manage Data ]

```

---

## Home Screen Code

```ts
<HomeScreen>
  <Header title="Inventory App" />

  <Button icon="➕" text="Add Movement" />
  <Button icon="📊" text="View Stock" />
  <Button icon="🕘" text="History" />
  <Button icon="⚙" text="Manage Data" />
</HomeScreen>
```

---

# ➕ Add Movement Screen

```
Item        [ Rice ▼ ]
Quantity    [ 50 ]
From        [ Godown A ▼ ]
To          [ Shop ▼ ]

[ SAVE ]
```

---

## Code Structure

```ts
<AddMovementScreen>
  <Dropdown label="Item" />
  <Input label="Quantity" />
  <Dropdown label="From" />
  <Dropdown label="To" />

  <Button variant="primary" text="Save" />
</AddMovementScreen>
```

---

# 📊 Stock Screen

```
Rice

Godown A : 350
Godown B : 120
Shop     : 40
```

---

## Code

```ts
<StockScreen>
  <Card>
    <Text>Rice</Text>
    <Text>Godown A : 350</Text>
    <Text>Godown B : 120</Text>
  </Card>
</StockScreen>
```

---

# 🕘 History Screen

```
10:45 AM
Rice 50
A → Shop
Staff: Ramesh

Edited: Yes
```

---

## Code

```ts
<HistoryItem>
  <Text>Rice 50</Text>
  <Text>A → Shop</Text>
  <Text>Edited</Text>
</HistoryItem>
```

---

# ⚙ Manage Screen

```
[ Add Item ]
[ Add Godown ]
```

---

# ⚠️ Error Handling UI

```ts
<ErrorMessage>
  "Invalid Quantity"
</ErrorMessage>
```

Style:

```ts
color: theme.error
font-size: 12px
```

---

# 🔄 Loading State

```ts
<Loader />
```

Example:

```
Loading...
```

---

# 📱 Interaction Rules

* Max 3 taps to complete action
* Large clickable areas
* No scrolling required for main actions
* Dropdowns instead of typing where possible

---

# 🌍 Localization Ready

```ts
Item → सामान
Quantity → मात्रा
From → कहाँ से
To → कहाँ तक
```

---

# ⚡ Performance Rules

* Instant UI response
* Offline-first
* Sync in background
* No blocking UI

---

# 📐 Spacing System

```ts
xs: 4px
sm: 8px
md: 12px
lg: 16px
```

---

# ✅ Final UI Principles

* Clean borders
* No clutter
* Consistent spacing
* High contrast text
* Fast actions
* Easy for non-technical users

---

# 🚀 Result

This design ensures:

* Minimal learning curve
* Fast usage
* Clean modern look
* Scalable UI system
* Easy implementation in Flutter / React Native

---
