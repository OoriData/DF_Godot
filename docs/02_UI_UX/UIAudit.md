---
type: ui-ux
tags:
  - ui
  - ux
  - codex/ui_audit
aliases:
  - "UI Element Audit"
created: 2026-05-21
---

# UI Element Audit — Desolate Frontiers

> [!IMPORTANT]
> This is the **single source of truth** for all UI element inventory in Desolate Frontiers.
> Before implementing any UI change, check the relevant section here first.
> After any structural change, update the affected section.

This document catalogs every UI element in the project: its scene file, owning script, visual style source, data connections, known issues, and open design questions.

---

## Related Documentation

| Doc | Contents |
|---|---|
| [UISystemIndex](UISystemIndex.md) | High-level UI system overview and script mapping |
| [SceneArchitecture](SceneArchitecture.md) | Viewport layer diagram and MainScreen hierarchy |
| [MenuBase Contract](MenuBase.md) | Lifecycle, signals, Oori background, and margin rules |
| [MenuManager](MenuManager.md) | Navigation stack, transitions, persistence cache |
| [DesignSystem](DesignSystem.md) | Color palette, typography, touch targets, animation rules |
| [DeviceState](DeviceState.md) | Orientation detection and `layout_mode_changed` signal flow |
| [ui_system](ui_system.md) | `UIScaleManager` deep-dive and responsive layout rules |
| [ConvoyMenu](ConvoyMenu.md) | Convoy Overview: vendor preview, debounce, mission sort |
| [ConvoyCargoMenu](ConvoyCargoMenu.md) | Cargo: sorting, grouping, inspector, debounce guard |
| [JourneyMenu](JourneyMenu.md) | Journey: route selection, resource projection, travel state |
| [VehicleMenu](VehicleMenu.md) | Vehicles: stats, parts, damage display |
| [SettlementMenu](SettlementMenu.md) | Settlement: service hub, dynamic capabilities |
| [WarehouseMenu](WarehouseMenu.md) | Warehouse: dual-column layout, tabs, runtime restructure |
| [MechanicsMenu](MechanicsMenu.md) | Mechanics: repair UI, slot management, condition warnings |
| [VendorPanel Overview](VendorPanel/VendorPanelOverview.md) | Full vendor trade panel reference |

---

## Quick Reference

### Core Script Mapping

| Node | Script | Role |
|---|---|---|
| `Main` (MapView root) | `Scripts/System/main.gd` | Scene mediator, camera occlusion, modal triggers |
| `UIManager` | `Scripts/UI/UI_manager.gd` | In-world settlement + convoy labels |
| `UIScaleManager` | `Scripts/UI/UI_scale_manager.gd` | Logical resolution authority (`content_scale_size`) |
| `MenuManager` | `Scripts/Menus/menu_manager.gd` | Navigation stack, transitions, static bottom nav |
| `MapInteractionManager` | `Scripts/Map/map_interaction_manager.gd` | Touch/mouse input → camera |
| `ConvoyVisualsManager` | `Scripts/Map/convoy_visuals_manager.gd` | Convoy sprites + route rendering |
| `UserInfoDisplay` | `Scripts/UI/user_info_display.gd` | TopBar — self-managed, not under MenuManager |
| `DeviceStateManager` | *(autoload)* | Orientation state + `layout_mode_changed` signal |

### Implementation Patterns

**Convoy Context** — All convoy menus operate on a `convoy_id`. They are initialized via `initialize_with_data(convoy_id)` and subscribe to `GameStore.convoys_changed` to stay in sync without polling. Never pass stale full dictionaries — pass the ID and let the menu fetch fresh data from the store.

**Mobile-First Standard**
- Touch targets: minimum **70px** height in portrait, **50px** in landscape
- Safe areas: always use `SafeRegionContainer`; never hardcode top/bottom margins
- Fluid labels: `SIZE_EXPAND_FILL` + `AUTOWRAP` on all text that might overflow
- Logical pixels: use `get_viewport_rect().size` not `DisplayServer.window_get_size()`

**Adding a New Menu**
1. Create scene in `Scenes/`, script in `Scripts/Menus/` extending `MenuBase`
2. Preload in `menu_manager.gd` and add an `open_*` method
3. Add `menu_type` label to `MENU_ORDER` if it needs slide transitions
4. Wire navigation signals in `_show_menu()` under the `is_convoy_submenu` block
5. Add entry to [UISystemIndex.md](UISystemIndex.md) Available Menus and [UIAudit.md](UIAudit.md) Audit Status

---

```
SettingsMenu (CanvasLayer, layer=100)         ← floats above everything
├─ DimBackground (ColorRect, alpha=0.47)
└─ Panel (PanelContainer, centered, 800×600 min)

MenuManager (Control, z_index=150 when active)
├─ MenuWrapperVBox
│   ├─ MenuContentArea   ← active menu node lives here
│   └─ StaticBottomNav (PanelContainer)
│       └─ NavButtonsHBox (HFlowContainer)
│           ├─ VehicleMenuButton
│           ├─ JourneyMenuButton
│           ├─ SettlementMenuButton
│           └─ CargoMenuButton

MainScreen (Control, full rect)
├─ BackgroundLayer (TextureRect, z=-10)
└─ SafeRegionContainer (MarginContainer + safe_area_handler.gd)
    ├─ SafeFrame (Panel, debug border, mouse=ignore)
    ├─ MainContainer (VBoxContainer)
    │   ├─ TopBar = UserInfoDisplay.tscn
    │   └─ MainContent (HBoxContainer)
    │       └─ MapAndMenuContainer (Control)
    │           ├─ Main = MapView.tscn
    │           └─ MenuContainer (PanelContainer, slides in/out)
    └─ ModalLayer (Control, visible=false by default)
        ├─ Scrim (ColorRect, alpha=0.5)
        └─ DialogHost (CenterContainer)

MapView (Control, fills MapAndMenuContainer)
├─ UIManager (CanvasLayer)
├─ MapContainer (Node2D)
│   └─ SubViewport (2650×1790)
│       ├─ TerrainTileMap
│       ├─ MapCamera (Camera2D)
│       ├─ SettlementLabelContainer
│       ├─ ConvoyLabelContainer  ← convoy_label_manager.gd
│       ├─ ConvoyConnectorLinesContainer
│       └─ CameraDebugOverlay
├─ MapInteractionManager → MapCameraController
└─ ConvoyVisualsManager
```

---

## 1. TopBar / Navbar — `UserInfoDisplay.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/UserInfoDisplay.tscn` |
| **Script** | `Scripts/UI/user_info_display.gd` |
| **Base type** | `PanelContainer` |
| **Parent in tree** | `MainScreen/SafeRegionContainer/MainContainer/TopBar` |
| **Managed by** | Nobody — self-managed via `_ready()` |
| **Data source** | `GameStore.user_changed`, `SignalHub.user_refresh_requested` |

### Child Elements

| Node | Type | Content | Notes |
|---|---|---|---|
| `UserChip` | `PanelContainer` | Contains `UsernameLabel` | Dark grey stylebox, 3px grey border |
| `UsernameLabel` | `Label` | Player username | font_size 30 (desktop), 32 (portrait mobile) |
| `VSeparator` | `VSeparator` | Visual divider | |
| `SettingsButton` | `MenuButton` | "Options" dropdown | Opens popup: Settings, Discord, Connect Accounts, Highlights & Tips |
| `ReportBugButton` | `Button` | "Feedback" | Red Oori styling; triggers screenshot + `BugReportWindow` |
| `LeftSpacer` | `Control` | Flex spacer | `SIZE_EXPAND_FILL` |
| `MoneyChip` | `PanelContainer` | Contains `UserMoneyLabel` | Deep dark stylebox, Oori yellow text |
| `UserMoneyLabel` | `Label` | Formatted money amount | `#f3d54e` yellow |
| `RightSpacer` | `Control` | Flex spacer | |
| `ConvoyListPanel` | Instanced scene | Convoy selector dropdown | See §2 below |
| `RightPadding` | `Control` | 16px fixed | |

### Sizing
- **Desktop**: `custom_minimum_size.y = 80`
- **Mobile Portrait**: `custom_minimum_size.y = 200`
- **Mobile Landscape**: `custom_minimum_size.y = 96`

### Visual Style
- Background: tiled `Oori Backround.png` via `TextureRect` (`OoriBackground`)
- Panel stylebox: transparent bg, 2px `#393d47` bottom border
- Chips: `#25282a` solid fill, 3px `#393d47` rounded border (radius 4)

### Known Issues / Gaps
- ❌ Extends `PanelContainer` directly — not under `MenuBase` or `MenuManager` lifecycle
- ❌ `custom_minimum_size.y = 80` hardcoded in `.tscn` as `offset_bottom = 68` (vestigial but overridden by script)
- ❌ `main_screen.gd` connects to this via fragile `find_child("ConvoyMenuButton", true, false)`
- ❌ No signal emitted when height changes — `MapView` has no formal notification
- ❌ Contains duplicate Oori color palette `const` values (also in `convoy_list_panel.gd`, `menu_base.gd`)
- ❌ Options dropdown uses `add_theme_font_size_override` with manual mobile multiplier (`int(16 * 2.2)`)

### Open Design Questions
- [ ] Should the TopBar collapse to icon-only in mobile portrait?
- [ ] Should it emit a `navbar_height_changed(px)` signal?
- [ ] Should the convoy button route through `SignalHub` instead of direct wiring?

---

## 2. Convoy Selector — `ConvoyListPanel.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/ConvoyListPanel.tscn` |
| **Script** | `Scripts/UI/convoy_list_panel.gd` |
| **Base type** | `VBoxContainer` |
| **Parent in tree** | `UserInfoDisplay/HBoxContent/ConvoyListPanel` |
| **Data source** | `GameStore.convoys_changed`, `SignalHub.convoy_selection_changed` |

### Child Elements

| Node | Type | Content | Notes |
|---|---|---|---|
| `ToggleButton` | `Button` | BBCode convoy name + arrow | `custom_minimum_size` = 300×56 (desktop), 400×110 (portrait) |
| `ConvoyPopup` | `PopupPanel` | Contains convoy list | Uses `DisplayServer.window_get_size()` for sizing ❌ |
| `ListScrollContainer` | `ScrollContainer` | Scroll wrapper | |
| `ConvoyItemsContainer` | `VBoxContainer` | Dynamically built convoy buttons | |

### Convoy Item Buttons (Built Dynamically)
Each button (`Button`) is named `ConvoyButton_{convoy_id}` and contains:
- `name_label` — convoy name, white text
- `dest_label` — "to {destination}", cyan `#29b6f6`
- `prog_label` — "(XX%)", light yellow

### Visual Style
- Toggle button: `#393d47` fill, 3px border, 5px bottom border, radius 4
- Popup: `#1e2123` fill (dark grey + black lerp), 2px `#393d47` border, radius 6
- Active/selected convoy: `Color.LIGHT_SKY_BLUE` modulate

### Known Issues / Gaps
- ❌ `convoy_list_panel.gd:92` calls `DisplayServer.window_get_size()` — violates logical pixel rule
- ❌ Contains duplicate Oori color palette `const` values
- ❌ `_get_font_size()` duplicates `DeviceStateManager.get_scaled_base_font_size()` logic
- ❌ `ToggleButton` in `.tscn` has `custom_minimum_size = Vector2(280, 80)` but script overrides to 300×56 or 400×110

---

## 3. Static Bottom Navigation Bar

| Property | Value |
|---|---|
| **Scene** | Built dynamically in `menu_manager.gd::_setup_static_bottom_nav()` |
| **Script** | `Scripts/Menus/menu_manager.gd` |
| **Base type** | `PanelContainer` (created at runtime) |
| **Parent in tree** | `MenuContainer/MenuWrapperVBox/StaticBottomNav` |
| **Visibility** | Only shown when a convoy submenu or overview is active |

### Nav Buttons

| Node Name | Label | Opens | Active Highlight |
|---|---|---|---|
| `VehicleMenuButton` | "Vehicles" | `convoy_vehicle_submenu` | Subtle yellow bg, gold border bottom-3 |
| `JourneyMenuButton` | "Journey" | `convoy_journey_submenu` | Same |
| `SettlementMenuButton` | "Settlement" | `convoy_settlement_submenu` | Same |
| `CargoMenuButton` | "Cargo" | `convoy_cargo_submenu` | Same |

### Sizing
- **Portrait**: `custom_minimum_size.y = 140`, font 28pt, bar_margin 14px
- **Mobile Landscape**: `custom_minimum_size.y = 85`, font 22pt, bar_margin 6px
- **Desktop**: `custom_minimum_size.y = 90`, font 28pt, bar_margin 0

### Visual Style
- Bar background: `Color(0.18, 0.18, 0.18, 0.95)`, top radius 6, 1px top border `#474747`
- Active button: bg `Color(0.72, 0.72, 0.65)`, 3px bottom border gold `rgba(0.85,0.75,0.2,0.9)`
- Inactive button: bg `#b0b0b0`, 1px black border
- Font color: always `#000000`

### Known Issues / Gaps
- ❌ Light grey button style on dark menu panel creates strong visual contrast — intentional?
- ❌ No shadow/depth on the nav bar itself relative to the menu content
- ❌ `SettlementMenuButton` is hidden when convoy is on a journey via `MenuBase._update_navigation_bar_visibility()` — but `ConvoyMenu.tscn` also has a *separate, legacy* `BottomMenuButtonsHBox` with its own buttons (see §4)

---

## 4. Convoy Overview Menu — `ConvoyMenu.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/ConvoyMenu.tscn` |
| **Script** | `Scripts/Menus/convoy_menu.gd` |
| **Extends** | `MenuBase` |
| **Menu Type Key** | `convoy_overview` |
| **Transition** | Vertical swipe down (enters over submenus) |

### Top-Level Structure
```
ConvoyMenu (Control, 450px wide default)
└─ MainVBox (VBoxContainer, 10px margins)
    ├─ TopBarHBox
    │   ├─ BackButton (120×34 min)
    │   ├─ TitleLabel (font 22)
    │   └─ RightSpacer (120px fixed — balances back button)
    ├─ ScrollContainer
    │   └─ ContentVBox
    │       ├─ ResourceStatsHBox  [Water, Food, Fuel] — ProgressBar + Label overlaid
    │       ├─ HSeparator
    │       ├─ PerformanceStatsHBox  [Speed, Offroad, Efficiency] — PanelContainer chips
    │       ├─ HSeparator
    │       ├─ CargoBarsHBox  [CargoVolume, CargoWeight] — ProgressBar + Label
    │       ├─ HSeparator
    │       └─ VendorPreviewPanel
    │           └─ VendorPreviewVBox
    │               ├─ PreviewTitleLabel ("Settlement Preview")
    │               ├─ VendorTabsHBox [Convoy | Settlement | Parts | Journey] — ButtonGroup toggle
    │               └─ VendorContentPanel → VendorContentScroll → ContentWrapper
    │                   ├─ JourneyInfoVBox (hidden by default)
    │                   │   ├─ JourneyDestLabel
    │                   │   ├─ JourneyProgressBar + JourneyProgressLabel (overlaid)
    │                   │   └─ JourneyETALabel
    │                   └─ VendorItemContainer → VendorItemGrid (GridContainer, columns=999)
    └─ BottomBarPanel (PanelContainer)       ← LEGACY — duplicates StaticBottomNav
        └─ BottomMenuButtonsHBox (HFlowContainer)
            ├─ VehicleMenuButton (110×34)
            ├─ JourneyMenuButton (110×34)
            ├─ SettlementMenuButton (110×34)
            └─ CargoMenuButton (110×34)
```

### Known Issues / Gaps
- ❌ **Duplicate nav bar**: `BottomBarPanel/BottomMenuButtonsHBox` mirrors the `StaticBottomNav` in MenuManager. These are styled differently (unstyled default buttons vs the themed StaticBottomNav). Only one should exist.
- ❌ `offset_right = 450` hardcoded in scene root — ignored at runtime since `MenuManager` sets `PRESET_FULL_RECT`, but misleading
- ❌ Vendor tab row (`Convoy | Settlement | Parts | Journey`) uses plain `Button` with `ButtonGroup` — no visual design (no custom stylebox)
- ❌ Resource stats overlaid label+bar approach uses manual layering, not a custom component

### Open Design Questions
- [ ] Remove `BottomBarPanel` entirely? (StaticBottomNav is the canonical implementation)
- [ ] Should vendor tabs use a tab bar component or styled toggle buttons?

---

## 5. Convoy Sub-Menus (Vehicles, Journey, Settlement, Cargo)

All extend `MenuBase`. Scenes are minimal scaffolding; UI is built in script. Full docs linked per-menu.

| Menu | Scene | Script | Full Doc |
|---|---|---|---|
| Vehicles | `ConvoyVehicleMenu.tscn` | `convoy_vehicle_menu.gd` | [VehicleMenu.md](VehicleMenu.md) |
| Journey | `ConvoyJourneyMenu.tscn` | `convoy_journey_menu.gd` | [JourneyMenu.md](JourneyMenu.md) |
| Settlement | `ConvoySettlementMenu.tscn` | `convoy_settlement_menu.gd` | [SettlementMenu.md](SettlementMenu.md) |
| Cargo | `ConvoyCargoMenu.tscn` | `convoy_cargo_menu.gd` | [ConvoyCargoMenu.md](ConvoyCargoMenu.md) |

### Common Structure (All Submenus)
- Root: `Control` extending `MenuBase`
- `MenuManager` sets `PRESET_FULL_RECT` + `offset_top = user_info_display.size.y`
- `MenuBase._ready()` applies Oori background texture and standard margins (14px portrait, 0 landscape)
- `MenuBase.setup_convoy_top_banner()` generates the breadcrumb banner at runtime
- Navigation signals (`open_vehicle_menu_requested`, etc.) are wired by `MenuManager._show_menu()` at instantiation time

### Notable Per-Menu Details

**Vehicles** — [`VehicleMenu.md`](VehicleMenu.md)
- Renders health, fuel efficiency, weight capacities, speed ratings
- Transitions to Mechanics menu for part install/removal

**Journey** — [`JourneyMenu.md`](JourneyMenu.md)
- Route selection from `RouteService`
- Resource consumption projections (fuel, food, water)
- Calls `RouteSelectionMenu.tscn` as a sub-dialog for embark confirmation (see §16)

**Settlement** — [`SettlementMenu.md`](SettlementMenu.md)
- Service hub: springs to Vendor panels, Warehouse, and refueling
- Dynamically enables/disables buttons based on `sett_type`

**Cargo** — [`ConvoyCargoMenu.md`](ConvoyCargoMenu.md)
- 5-metric sort system (`ui.cargo_sort_metric` persisted to `SettingsManager`)
- Group by Vehicle or by Type toggle
- Inline inspector panels per item; debounced refresh guard (`_suppress_refresh_until_msec`)
- Mobile: fonts scale to 2.8× desktop; option buttons expand to 100px height

### Known Issues / Gaps (Shared)
- ❌ Top banner is generated procedurally — no scene-level placeholder to inspect in editor
- ❌ `offset_top` set via `user_info_display.size.y` — stale if `UserInfoDisplay` height changes without signaling

---

## 6. Warehouse Menu — `WarehouseMenu.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/WarehouseMenu.tscn` |
| **Script** | `Scripts/Menus/warehouse_menu.gd` |
| **Extends** | `MenuBase` |
| **Menu Type Key** | `warehouse_submenu` |
| **Opens from** | Settlement menu → "Warehouse" button |
| **Full Doc** | [WarehouseMenu.md](WarehouseMenu.md) |

### States
| State | Condition | UI Shown |
|---|---|---|
| No Warehouse | `_warehouse` dict empty | Buy card + price info + `BuyButton` |
| Owned Warehouse | `_warehouse` populated | Dual-column layout: Overview + Cargo/Vehicles tabs |

### Runtime Layout Restructure
`_setup_dual_column_layout()` runs in `_ready()` and **restructures the scene tree at runtime** — moves `Overview` tab into a left `LeftPanel`, leaving Cargo and Vehicles tabs in the right `RightColumn`. Node paths in the `.tscn` do not reflect the runtime tree.

### Tabs (Owned State)
- **Overview**: Radial gauge (`radial_progress_gauge.gd`), vehicle slot bar, Expand Cargo/Vehicle buttons
- **Cargo**: Store/retrieve dropdowns, quantity spinbox, scrollable inventory grid (cards clickable to auto-select retrieve)
- **Vehicles**: Store/retrieve vehicle dropdowns, spawn new vehicle (name + convoy selector)

### Portrait Responsive Sizing
- `OptionButton` height: **120px** portrait vs **50px** desktop
- Tab bar height: **100px** portrait vs **40px** desktop
- Layout: `Columns.vertical = true` in portrait

### Known Issues / Gaps
- ❌ Runtime tree restructure means `find_child()` is required for all node access — hardcoded paths will break
- ❌ `radial_progress_gauge.gd` stored via node metadata (`get_meta("radial_gauge")`) — not inspectable in editor

---

## 7. Mechanics Menu — `MechanicsMenu.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/MechanicsMenu.tscn` |
| **Script** | `Scripts/Menus/mechanics_menu.gd` |
| **Extends** | `MenuBase` |
| **Menu Type Key** | `mechanics_submenu` |
| **Gate** | Only opens if convoy is at a settlement (`in_settlement` flag or coord lookup) |
| **Full Doc** | [MechanicsMenu.md](MechanicsMenu.md) |

### Responsibilities
- Repair UI: apply repair kits or spend credits to restore vehicle/part health
- Slot management: view and swap compatible parts per vehicle slot
- Condition warnings: alerts for incompatible weight, type mismatch, missing items

### Known Issues / Gaps
- ❌ Gate logic (`_has_settlement_at_coords`) lives in `menu_manager.gd` — not in the menu itself
- ❌ Shallow stub doc (`MechanicsMenu.md`) — scene-level audit not yet complete

---

## 8. Vendor Trade Panel — `VendorTradePanel.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/VendorTradePanel.tscn` |
| **Script** | `Scripts/Menus/vendor_trade_panel.gd` |
| **Opens from** | Settlement menu, Warehouse menu |
| **Full Doc** | [VendorPanel Overview](VendorPanel/VendorPanelOverview.md) |

The Vendor system has its own dedicated sub-documentation set in `docs/02_UI_UX/VendorPanel/`:

| Doc | Contents |
|---|---|
| [VendorPanelOverview.md](VendorPanel/VendorPanelOverview.md) | Architecture overview |
| [Data.md](VendorPanel/Data.md) | Vendor data shape and sourcing |
| [Lifecycle.md](VendorPanel/Lifecycle.md) | Panel open/close and data binding |
| [Transactions.md](VendorPanel/Transactions.md) | Buy/sell flow and confirmation |
| [UI_Inspector.md](VendorPanel/UI_Inspector.md) | Item inspector panel layout |
| [ConvoyStats.md](VendorPanel/ConvoyStats.md) | Convoy capacity display within vendor |
| [Mechanics.md](VendorPanel/Mechanics.md) | Parts filtering and compatibility |
| [Checklist.md](VendorPanel/Checklist.md) | Implementation checklist |

---

## 9. Map Overlay Settings Panel

| Property | Value |
|---|---|
| **Scene** | Built dynamically in script |
| **Script** | `Scripts/UI/map_overlay_settings_panel.gd` |
| **Parent in tree** | Added to `MapAndMenuContainer` at runtime by `main_screen.gd::_ready()` |
| **Purpose** | Floating toggle panel for map overlay layers |

### Known Issues / Gaps
- ❌ Added to `MapAndMenuContainer` directly by `main_screen.gd` — not in scene tree, hard to inspect

---

## 9b. Route Selection / Embark Confirmation — `RouteSelectionMenu.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/RouteSelectionMenu.tscn` |
| **Script** | `Scripts/Menus/route_selection_menu.gd` |
| **Base type** | `Control` (full-rect) |
| **Opens from** | Journey menu → "Select Route" / Embark flow |

### Layout
```
RouteSelectionMenu (Control, full-rect)
├─ Background (ColorRect, black alpha=0.78)   ← dim scrim built into scene
└─ MainVBox
    ├─ TitleLabel ("Journey Details", font 28)
    ├─ HSeparator
    ├─ ColumnsHBox (BoxContainer, vertical=true default)
    │   ├─ LeftColumn — Resource Expenses
    │   │   ├─ ExpensesGrid [Fuel / Water / Food] (GridContainer, 2 cols)
    │   │   └─ VehicleExpensesVBox (ScrollContainer, ResponsiveListAdapter)
    │   └─ RightColumn — Journey Details
    │       └─ DetailsGrid [Destination / Distance / ETA] (GridContainer, 2 cols)
    ├─ HSeparator
    └─ ButtonsHBox
        ├─ BackButton ("Cancel")
        └─ EmbarkButton ("Embark")
```

### Known Issues / Gaps
- ❌ Not in the `UISystemIndex.md` or `DocumentationHome.md` — previously undocumented scene
- ❌ `ColumnsHBox.vertical = true` is set in the scene — always stacked, no landscape split-column adaptation
- ❌ No `MenuBase` — extends `Control` directly; no Oori background or standard margins

---

## 9c. New Convoy Dialog — `NewConvoyDialog.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/NewConvoyDialog.tscn` |
| **Script** | `Scripts/UI/new_convoy_dialog.gd` |
| **Base type** | `PanelContainer` (1000×480 min, centered via offsets) |
| **Opens from** | Onboarding / first-time player flow |

### Layout
- Dark panel (`#1a1a1f`, alpha 0.95), radius 6, shadow
- Title: Roboto 48pt — "Welcome to Desolate Frontiers!"
- `NameEdit` (LineEdit, 80px height, max 40 chars)
- `ErrorLabel` (hidden by default, pink-red)
- `CreateButton` (240×80, `SuccessButton` theme variation)

### Known Issues / Gaps
- ❌ Uses `Roboto-VariableFont_wdth,wght.ttf` directly — not the project's standard `main_font.tres`
- ❌ Centered via `offset_left = -500` / `offset_top = -240` (absolute offsets) — same brittle pattern as modals
- ❌ `custom_minimum_size = Vector2(1000, 480)` — very wide; will be problematic on portrait mobile
- ❌ `SuccessButton` theme variation is used but not documented in `DesignSystem.md`

---

## 10. Settings Menu — `SettingsMenu.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/SettingsMenu.tscn` |
| **Script** | `Scripts/Menus/settings_menu.gd` |
| **Base type** | `CanvasLayer` (layer=100) |
| **Opens from** | UserInfoDisplay Options dropdown → "Settings" |
| **Closes via** | "Close" button, not `MenuManager.go_back()` |

### Layout
- Full-screen dim background `ColorRect(0,0,0,0.47)`
- Centered `PanelContainer` (800×600 min): `#1f1f1f` fill, 1px `#4d4d4d` border, radius 12
- Internal `ScrollContainer` with sections: Display, UI, Controls, Gameplay & Accessibility
- Bottom row: Log Out (red), Reset to Defaults, Close

### Settings Controls

| Control | Type | Setting |
|---|---|---|
| Fullscreen | `CheckButton` | Display mode |
| Dynamic Scaling (Auto) | `CheckButton` | `ui.auto_scale` |
| UI Scale | `HSlider` (0.75–2.0, step 0.05) | `ui.scale` |
| Menu Width Ratio | `HSlider` (1.2–3.5, step 0.1) | `ui.menu_ratio` |
| Invert Pan | `CheckButton` | Camera pan direction |
| Invert Zoom | `CheckButton` | Camera zoom direction |
| Enable Touch Gestures | `CheckButton` | Gesture support |
| High Contrast Labels | `CheckButton` | Accessibility |

### Visual Style
- Uses per-element `StyleBoxFlat` sub-resources defined in the `.tscn` — not shared
- Toggle buttons: subtle white-5% fill, radius 8
- Log Out: `Color(0.44, 0.15, 0.15)` dark red

### Known Issues / Gaps
- ❌ Opened by `UserInfoDisplay` via `load()` + `get_tree().root.add_child()` — bypasses `MenuManager` entirely
- ❌ `CanvasLayer` with `layer=100` means it floats above everything including tutorials
- ❌ Panel is 800px wide minimum — may clip on narrow mobile portrait without adjustment
- ❌ UI Scale slider (0.75–2.0) exposes the S/M/L preference — but as documented, portrait mode silently overrides it

---

## 11. Modals (Post-Journey, Premium, Tips)

### 11a. AutoSell Receipt Modal — `AutoSellReceiptModal.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/UI/AutoSellReceiptModal.tscn` |
| **Script** | `Scripts/UI/auto_sell_receipt_modal.gd` |
| **Opens from** | `main_screen.gd::_on_auto_sell_receipt_ready()` |
| **Base type** | `Control` (full-rect) + centered `Panel` (600×700 min) |

Visual: teal accent `#48b8a8` for title + divider lines, 14px caption text, scrollable item list.

#### Known Issues / Gaps
- ❌ `custom_minimum_size = Vector2(600, 700)` — fixed physical-ish size; will overflow on narrow portrait without `content_scale_size` doing the work
- ❌ Panel centered via `offset_left = -300` / `offset_top = -350` (absolute offsets from center anchor) — brittle if content_scale_size changes dramatically
- ❌ Not styled with Oori theme — uses Godot default `Panel` and raw `Color()` overrides

### 11b. Premium Upgrade Modal — `PremiumUpgradeModal.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/UI/PremiumUpgradeModal.tscn` |
| **Script** | `Scripts/UI/premium_upgrade_modal.gd` |
| **Base type** | `Control` (full-rect) + centered `Panel` (500×400 min) |

Minimal design — title, description, price label, Buy/Close buttons. No Oori theme applied.

#### Known Issues / Gaps
- ❌ Close button positioned via `anchors_preset = 1` (top-right corner) at `-40, 0` — fragile positioning
- ❌ No dim-behind scrim; relies on ModalLayer scrim in MainScreen (which is currently alpha=0)

### 11c. Returning Player Tips Modal — `ReturningPlayerTipsModal.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/UI/ReturningPlayerTipsModal.tscn` |
| **Script** | `Scripts/UI/returning_player_tips_modal.gd` |
| **Base type** | `Control` (full-rect) + centered `Panel` (800×600 min) |

Content sections: Early Access, Feedback & Community, Quick Tips. Tutorial section hidden by default.

#### Known Issues / Gaps
- ❌ Same hardcoded center-anchor pattern as AutoSellReceiptModal

---

## 12. Toast Notifications

| Scene | Script | Base Type | Notes |
|---|---|---|
| `Scenes/UI/ToastNotification.tscn` | `Scripts/UI/toast_notification.gd` | Not scene-audited | Brief dismissable message; shown at top of screen |
| `Scenes/UI/PushToast.tscn` | `Scripts/UI/push_toast.gd` | Not scene-audited | Push notification variant; triggered by `PushNotificationManager` |

**Owner**: Both are instantiated by `main_screen.gd` and added to the `ModalLayer` or directly to the root.

> [!NOTE]
> Scene-level audit pending. These are small scenes; the main interest is z-index placement relative to the tutorial overlay and `SettingsMenu` (layer=100).

---

## 13. Login Screen — `LoginScreen.tscn`

| Property | Value |
|---|---|
| **Scene** | `res://Scenes/LoginScreen.tscn` |
| **Script** | `Scripts/UI/login_screen.gd` |
| **Managed by** | `GameRoot.tscn` (scene switcher) |
| **Base type** | Not `MenuBase` — standalone pre-game screen |

Pre-game OAuth login screen. Includes a dev-only "Skip Login" button gated by `app_config.cfg::active_env == "dev"`. Not part of the in-game `MainScreen` / `MenuManager` stack.

### Known Issues / Gaps
- ❌ Scene-level audit pending (4300 bytes)
- ❌ "Skip Login" button visibility uses `app_config.cfg` read at `_ready()` — not integrated with the formal `SettingsManager`

---

## 14. Map UI Layer (In-World)

These live inside `MapView/MapContainer/SubViewport` — rendered by the `Camera2D`, not the 2D Control tree.

| Element | Container | Script | Purpose |
|---|---|---|---|
| Settlement labels | `SettlementLabelContainer` | `UI_manager.gd` | Settlement name chips on map |
| Convoy labels | `ConvoyLabelContainer` | `convoy_label_manager.gd` | Convoy name/status bubbles |
| Route connector lines | `ConvoyConnectorLinesContainer` | `UI_manager.gd` | Lines connecting convoy to destination |
| Camera debug overlay | `CameraDebugOverlay` | `map_camera_debug_overlay.gd` | Dev-only |

These are **not Control nodes** — they are `Node2D` children drawn in world space. They do not participate in the `content_scale_size` logical coordinate system; they scale with the Camera2D zoom instead.

---

## 15. Component Inventory — Non-Scene UI Scripts

| Script | Role | Owner |
|---|---|---|
| `UI_scale_manager.gd` | Logical resolution authority (`content_scale_size`) | Autoload |
| `safe_area_handler.gd` | Applies `DisplayServer.get_display_safe_area()` margins | `SafeRegionContainer` |
| `UI_manager.gd` | Manages in-world settlement + convoy labels | `MapView/UIManager` |
| `convoy_label_manager.gd` | Convoy bubble lifecycle + pinned state | `ConvoyLabelContainer` |
| `responsive_list_adapter.gd` | Adapts list item sizes to device | `ConvoyListPanel/ConvoyItemsContainer` |
| `error_dialog.gd` | Inline + modal error display | Instantiated by `ErrorManager` |
| `quantity_widget.gd` | Reusable +/- quantity selector | Used in vendor panels |
| `radial_progress_gauge.gd` | Circular progress indicator | Used in vehicle cards |
| `target_resolver.gd` | Resolves tutorial node paths | `TutorialManager` |

---

## Cross-Cutting Issues Summary

| # | Issue | Severity | Affects |
|---|---|---|---|
| 1 | Oori color palette defined as `const` in 3+ scripts | Medium | Maintainability |
| 2 | `DisplayServer.window_get_size()` in `convoy_list_panel.gd:92` | Medium | Hi-DPI popup sizing |
| 3 | Duplicate legacy nav bar in `ConvoyMenu.tscn/BottomBarPanel` | Medium | Visual consistency |
| 4 | Modals use hardcoded absolute center offsets (not `CenterContainer`) | Low–Medium | Small/portrait screens |
| 5 | `SettingsMenu` opened outside `MenuManager` via `CanvasLayer` | Low | Lifecycle inconsistency |
| 6 | `UserInfoDisplay` height changes not signaled to layout | Low | Potential offset stale |
| 7 | `main_screen.gd` finds convoy button via `find_child()` | Low | Fragile wiring |
| 8 | S/M/L scale preference overridden silently in portrait | Medium | User settings |
| 9 | No `UIConstants` file — breakpoints/colors scattered | Medium | Maintainability |
| 10 | `AutoSellReceiptModal` not styled with Oori theme | Low | Visual inconsistency |

---

## Audit Status

| Section | Last Audited | Scene Read | Script Read | Doc Linked |
|---|---|---|---|---|
| TopBar / UserInfoDisplay | 2026-05-21 | ✅ | ✅ | — (no standalone doc) |
| ConvoyListPanel | 2026-05-21 | ✅ | ✅ | — (no standalone doc) |
| StaticBottomNav | 2026-05-21 | N/A (runtime) | ✅ | [MenuManager.md](MenuManager.md) |
| ConvoyMenu (Overview) | 2026-05-21 | ✅ | — | [ConvoyMenu.md](ConvoyMenu.md) ✅ |
| Convoy Vehicle Submenu | 2026-05-21 | Shallow | — | [VehicleMenu.md](VehicleMenu.md) ✅ |
| Convoy Journey Submenu | 2026-05-21 | Shallow | — | [JourneyMenu.md](JourneyMenu.md) ✅ |
| Convoy Settlement Submenu | 2026-05-21 | Shallow | — | [SettlementMenu.md](SettlementMenu.md) ✅ |
| Convoy Cargo Submenu | 2026-05-21 | Shallow | — | [ConvoyCargoMenu.md](ConvoyCargoMenu.md) ✅ |
| WarehouseMenu | 2026-05-21 | — | — | [WarehouseMenu.md](WarehouseMenu.md) ✅ |
| MechanicsMenu | 2026-05-21 | — | — | [MechanicsMenu.md](MechanicsMenu.md) ✅ |
| VendorTradePanel | 2026-05-21 | — | — | [VendorPanel/](VendorPanel/VendorPanelOverview.md) ✅ |
| RouteSelectionMenu | 2026-05-21 | ✅ | — | — (no standalone doc) |
| NewConvoyDialog | 2026-05-21 | ✅ | — | — (no standalone doc) |
| MapOverlaySettingsPanel | 2026-05-21 | N/A (runtime) | — | — (no standalone doc) |
| SettingsMenu | 2026-05-21 | ✅ | — | — (no standalone doc) |
| AutoSellReceiptModal | 2026-05-21 | ✅ | — | — (no standalone doc) |
| PremiumUpgradeModal | 2026-05-21 | ✅ | — | — (no standalone doc) |
| ReturningPlayerTipsModal | 2026-05-21 | ✅ | — | — (no standalone doc) |
| Toast Notifications | 2026-05-21 | — | — | — (no standalone doc) |
| LoginScreen | 2026-05-21 | — | — | — (no standalone doc) |
| Map UI (in-world) | 2026-05-21 | ✅ | — | [UISystemIndex.md](UISystemIndex.md) ✅ |

---

## Pending Standalone Docs

These UI elements are fully audited here but have no dedicated documentation file. Create these if the component becomes a change target:

| Element | Priority | Notes |
|---|---|---|
| `UserInfoDisplay` + `ConvoyListPanel` | High | Most-touched; cross-cutting issues |
| `SettingsMenu` | Medium | Settings controls and `UIScaleManager` interaction |
| `RouteSelectionMenu` | Medium | Missing from all other docs; no `MenuBase` |
| `NewConvoyDialog` | Low | Onboarding-only; rarely changed |
| Toast Notifications | Low | Small scenes; z-index placement is the main concern |
