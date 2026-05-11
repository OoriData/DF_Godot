# Items & Mission Domain

Desolate Frontiers uses a **Unified Item Model**. "Missions" are not a separate engine system; they are specialized Cargo Items that represent a delivery obligation.

## 1. The Unified Model (`CargoItem`)

All cargo in the game (Convoys, Vendors, Warehouses) is parsed into `CargoItem` objects. This provides type safety and standardizes units (Weight/Volume).

### Sub-Classes
- **`PartItem`**: Items with a `.slot` (e.g., "Engine", "Tires"). They contain `modifiers` that affect vehicle performance.
- **`ResourceItem`**: Consumables like `fuel`, `water`, and `food`.
- **`VehicleItem`**: Complete vehicle records (typically found in Vendor inventories).
- **`MissionItem`**: Delivery cargo (see below).

---

## 2. Mission Detection Logic

A `CargoItem` is classified as a **Mission** if it passes the "Looks like a mission" check in `Items.gd`.

### Criteria for Mission Detection
The `MissionItem._looks_like_mission_dict()` function checks for:
1.  **Recipient Field**: Presence of `recipient`, `recipient_vendor_id`, or `recipient_settlement_name`.
2.  **Delivery Reward**: Any item with a `delivery_reward > 0`.
3.  **Explicit Flag**: The `is_mission: true` metadata.

### Data Signature
```json
{
  "cargo_id": "uuid",
  "name": "Emergency Medical Supplies",
  "recipient_vendor_id": "vendor-uuid",
  "recipient_vendor_name": "Dr. Aris",
  "delivery_reward": 500,
  "is_mission": true
}
```

---

## 3. UI Display Patterns

### Convoy Cargo Menu
Missions are always grouped at the top of the cargo list under the **"Delivery Cargo"** section. This ensures players can easily distinguish between their own property and items they are being paid to transport.

### Vendor Trade Panel
When trading with a vendor who is the **recipient** of a mission item:
- The UI highlights the item in the "Delivery" bucket.
- The "Sell" action is replaced with "Deliver".
- The value displayed is the `delivery_reward`, not the market price.

---

## 4. Implementation Guidelines

- **Adding a new Part**: Ensure it has a `slot` property and `modifiers` (e.g., `top_speed_add`).
- **Adding a new Mission**: Ensure the backend payload includes a `recipient_vendor_id`. The client will automatically categorize it as a mission.
- **Data Safety**: Always use `CargoItem.from_dict(raw)` to ensure units and categories are normalized before using them in UI math.
