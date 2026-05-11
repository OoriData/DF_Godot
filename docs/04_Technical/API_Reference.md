# Backend API Reference

This document defines the communication contract between the *Desolate Frontiers* Godot client and the backend simulation server.

## 1. Base URL
- **Development**: `http://127.0.0.1:1337`
- **Production**: Defined in `app_config.cfg` or `DF_API_BASE_URL` environment variable.

## 2. Authentication
All protected endpoints require an `Authorization: Bearer <JWT>` header.

### `GET /auth/me`
Resolves the current session to a User ID.
- **Response**: `{ "user_id": "uuid", "username": "string" }`

### `GET /auth/status?state=<uuid>`
Polls the status of an external OAuth flow (Discord, Steam, Google).
- **Status 200**: Auth complete. Returns session JWT.
- **Status 202**: Still pending.
- **Status 409**: Conflict. Account exists on another provider (returns `merge_token`).

---

## 3. World & Convoys

### `GET /map/get`
Fetches tile and settlement data.
- **Params**: `x_min`, `x_max`, `y_min`, `y_max` (optional bounding box).
- **Response**: Binary stream (`application/octet-stream`) for tiles or JSON for settlements.

### `GET /user/get?user_id=<uuid>`
The primary "Sync" endpoint. Fetches the user profile and all their active convoys.
- **Response**: `{ "user": {...}, "convoys": [...] }`

### `PATCH /user/update_metadata?user_id=<uuid>`
Persists UI state or tutorial progress.
- **Body**: `{ "tutorial": 5, "last_selected_convoy": "uuid" }`

---

## 4. Vendor & Trading

### `GET /vendor/get?vendor_id=<uuid>`
Fetches the current inventory and price list for a settlement vendor.

### `PATCH /vendor/cargo/buy` / `sell`
Transfers items between a Convoy and a Vendor.
- **Params**: `vendor_id`, `convoy_id`, `cargo_id`, `quantity`

### `PATCH /vendor/resource/buy` / `sell`
Specific routes for liquid/bulk resources like Fuel or Supplies.
- **Params**: `resource_type` (fuel, supplies), `quantity`

---

## 5. Journey Planning

### `POST /convoy/journey/find_route`
Calculates multiple pathfinding options based on speed vs. fuel efficiency.
- **Params**: `convoy_id`, `dest_x`, `dest_y`
- **Response**: `Array` of `journey` objects containing `path`, `eta`, and `cost`.

### `PATCH /convoy/journey/send`
Commits a convoy to a specific journey ID.
- **Params**: `convoy_id`, `journey_id`

---

## 6. Warehouse & Mechanics

### `PATCH /warehouse/cargo/store` / `retrieve`
Moves items between a Convoy and the local Settlement Warehouse.
- **Params**: `warehouse_id`, `convoy_id`, `cargo_id`, `quantity`

### `GET /vehicle/part/check_compatibility`
Dry-run test to see if a part can be installed on a vehicle.
- **Response**: `{ "can_install": bool, "reason": "string", "stat_diff": {...} }`

### `PATCH /vehicle/part/attach` / `detach`
Commits a part modification to a vehicle.
