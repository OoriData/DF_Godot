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
