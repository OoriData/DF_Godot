---
type: architecture
tags:
  - architecture
  - codex/cookbook
aliases:
  - "Developer Cookbook"
created: 2026-05-18
---

# Developer Cookbook

This document provides step-by-step recipes for common development tasks in *Desolate Frontiers*. Follow these patterns to ensure consistency and maintainability.

## 🍳 Recipe: Create a New Full-Screen Menu

1. **Create the Scene**: Create a new `.tscn` with a `MarginContainer` or `Panel` as the root.
2. **Attach Script**: Inherit from `MenuBase`.
3. **Setup Layout**: Add a `VBoxContainer`. Call `setup_convoy_top_banner("Menu Title")` in your `_initialize_menu` method.
4. **Register**: Add the scene path to `MenuManager.gd` in the `_menu_registry` dictionary.
5. **Open**: Call `MenuManager.open_menu("your_menu_key", convoy_data)`.

---

## 🍳 Recipe: Add a New Domain Signal (SignalHub)

1. **Define in SignalHub**: Open `signal_hub.gd` and add the signal definition (e.g., `signal fuel_exhausted(convoy_id)`).
2. **Emit from Service**: In the relevant service (e.g., `ConvoyService`), call `SignalHub.fuel_exhausted.emit(id)` when the event occurs.
3. **Connect in UI**: In your menu's `_initialize_menu`, connect to the signal:
   ```gdscript
   SignalHub.fuel_exhausted.connect(_on_fuel_exhausted)
   ```

---

## 🍳 Recipe: Add a Responsive "Safe" UI Element

1. **Hierarchy**: Ensure your element is a child of `SafeRegionContainer` (inside `MainScreen`).
2. **Component**: Use the `SafeAreaHandler` component if you need custom margin logic for notches.
3. **Scaling**: Use logical pixel values (based on an 800px width). The `UIScaleManager` will handle the actual screen-space scaling.
4. **Testing**: Toggle the "Simulate Notch" or "Portrait Mode" in the `DeviceStateManager` (or resize the window) to verify it doesn't clip.

---

## 🍳 Recipe: Fetch Data from the Backend

1. **APICalls**: Add the low-level method in `api_calls.gd` (e.g., `get_warehouse_contents()`).
2. **Service**: Wrap it in a service (e.g., `WarehouseService`). This service should:
   - Call the API.
   - On success, update the `GameStore` snapshot.
   - Emit a `SignalHub` event (e.g., `warehouse_updated`).
3. **UI**: The UI should never call `APICalls` directly. It should listen for the `SignalHub` event and refresh its view using the data from `GameStore`.

---

## 🍳 Recipe: Debugging with the Headless Smoke Test

1. **Run Command**: 
   ```bash
   Godot.app/Contents/MacOS/Godot --headless --path . -s res://Scripts/Debug/wiring_smoke_test.gd
   ```
2. **Verify**: Ensure "SignalHub Wires: OK" and "Store Initialization: OK" appear in the console.

---

## 🍳 Recipe: Add Per-Menu Diagnostic Logging (the `_debug_*` Pattern)

Every major menu uses a per-instance boolean flag to gate verbose `print()` calls. This avoids log spam in production without needing a global logger level change.

1. **Declare the flag** at the top of your menu script:
   ```gdscript
   var _debug_my_menu: bool = true  # set false to silence
   ```
2. **Gate all diagnostic prints** behind the flag:
   ```gdscript
   if _debug_my_menu:
       print("[MyMenu][Debug] vendor_id=", vendor_id, " items=", items.size())
   ```
3. **Name the flag consistently** after the menu: `_debug_convoy_menu`, `_debug_cargo_menu`, etc.
4. **Flip to `false`** before committing if the feature is stable. Leave `true` during active development.

> [!TIP]
> For heavier diagnostics (signal wiring verification, node path checks), use a separate `_diag_*` function and connect it as a secondary handler alongside the real one — see `WarehouseMenu._diag_expand_cargo_pressed()` as an example.

---

## 🍳 Recipe: Add a New Item Type

1. **Define the class**: Open `Scripts/Data/Items.gd`. Add a new inner class that extends `CargoItem`:
   ```gdscript
   class MyNewItem extends CargoItem:
       var my_custom_field: String = ""
       static func _looks_like_my_item(d: Dictionary) -> bool:
           return d.has("my_custom_field")
   ```
2. **Register detection**: In `CargoItem.from_dict()`, add a detection branch before the generic fallback:
   ```gdscript
   if MyNewItem._looks_like_my_item(raw):
       return MyNewItem.new(raw)
   ```
3. **Add UI grouping**: In `ConvoyCargoMenu._build_cargo_sections()`, add a new section header for the new type (similar to "Delivery Cargo" for `DeliveryCargoItem`).
4. **Update the Schema**: Add a row to the Cargo Object table in [Schema.md](Schema.md) documenting the new key.

---

## 🍳 Recipe: Debug a Missing or Silent Signal

When a signal fires but nothing responds (or you think it should be firing but isn't):

1. **Verify the signal is defined**: Check `signal_hub.gd` — if it's not there, add it per the "Add a New Domain Signal" recipe.
2. **Check the connection**: Add a temporary one-shot print in `_ready()`:
   ```gdscript
   SignalHub.my_signal.connect(func(arg): print("[DEBUG] my_signal fired: ", arg))
   ```
3. **Verify the emitter**: Search for `.emit(` calls for the signal name. Add a `print` directly before the emit to confirm execution reaches that line.
4. **Check process_mode**: If the signal fires during a paused tree (e.g. modal open), the listener's `process_mode` must be `PROCESS_MODE_ALWAYS`. This is the most common silent-signal cause.
5. **Check is_connected guard**: Many menus guard with `if not signal.is_connected(handler)` before connecting. If the guard is wrong, the connection never fires.
6. **Run the smoke test**: `wiring_smoke_test.gd` validates the core wiring — if it passes but your signal is still missing, the issue is in emission, not wiring.

