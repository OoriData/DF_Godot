# Menus

Common API and service-backed wiring.

- Contract: menus extend `MenuBase` and implement `initialize_with_data(data_or_id: Variant, extra: Variant = null)` plus `_update_ui(convoy: Dictionary)`. `data_or_id` can be a full convoy `Dictionary` or a `String convoy_id` (preferred for performance). The base class provides the `back_requested` signal, guards store subscriptions, and resolves IDs to snapshots via `GameStore`.
- MenuManager: [Scripts/Menus/menu_manager.gd](../../Scripts/Menus/menu_manager.gd)
  - Listens to selection via SignalHub and convoy updates via GameStore; standardizes open/close.
  - Passes `convoy_id` strings to menus; avoid deep copies in meta.

Menus:
- ConvoyMenu: [Scripts/Menus/convoy_menu.gd](../../Scripts/Menus/convoy_menu.gd)
- ConvoyVehicleMenu: [Scripts/Menus/convoy_vehicle_menu.gd](../../Scripts/Menus/convoy_vehicle_menu.gd)
- ConvoyCargoMenu: [Scripts/Menus/convoy_cargo_menu.gd](../../Scripts/Menus/convoy_cargo_menu.gd)
- ConvoySettlementMenu: [Scripts/Menus/convoy_settlement_menu.gd](../../Scripts/Menus/convoy_settlement_menu.gd)
- MechanicsMenu: [Scripts/Menus/mechanics_menu.gd](../../Scripts/Menus/mechanics_menu.gd)
- RouteSelectionMenu: [Scripts/Menus/route_selection_menu.gd](../../Scripts/Menus/route_selection_menu.gd)
- VendorTradePanel: [Scripts/Menus/vendor_trade_panel.gd](../../Scripts/Menus/vendor_trade_panel.gd) → see [VendorTradePanel.md](VendorTradePanel.md). Note: this panel extends `Control` (not `MenuBase`) and exposes `initialize(vendor, convoy, settlement, all_settlements)`.
