# Architecture Overview

Event flow:
- APICalls → Services → GameStore/SignalHub → UI
- UI → Services → APICalls

Autoloads:
- Hub: [Scripts/System/Services/signal_hub.gd](../Scripts/System/Services/signal_hub.gd)
- Store: [Scripts/System/Services/game_store.gd](../Scripts/System/Services/game_store.gd)

Canonical domain events via Hub/Store:
- Map: `map_changed(tiles, settlements)`
- Convoys: `convoys_changed(convoys)`, `convoy_updated(convoy)`, `selected_convoy_changed(id)`
- User/Auth: `user_changed(user)`, `auth_state_changed(state)`, `user_refresh_requested`
- Vendors: `vendor_updated(vendor)`, `vendor_panel_ready(data)`, `vendor_preview_ready(data)`
- Routing: `route_choices_request_started`, `route_choices_ready`, `route_choices_error`
- Errors: `error_occurred(domain, code, message, inline)`
- Lifecycle: `initial_data_ready()`

## Identity & Auth

The system supports multiple providers (Steam, Discord) with a unified session model. Detailed documentation is in [Identity.md](System/Identity.md).

- **Login Flow**: External provider (Steam ID or Discord OAuth) → API → JWT Session Token.
- **Persistence**: Token stored in `user://session.cfg` for auto-login.
- **Linking**: Connected accounts can be linked via `/auth/steam/link` or `/auth/discord/link_code`.
- **Merging**: Flow for account collisions: `/auth/merge/preview` → `/auth/merge/commit`.

Services (thin, domain-focused):
- Map, Convoy, User, Vendor, Mechanics, Route, Warehouse, RefreshScheduler, ConvoySelectionService

State:
- `GameStore` holds snapshots: tiles, settlements, convoys, user, color_map; emits `*_changed`.

Logging & Errors:
- Central Logger ([Scripts/System/logger.gd](../Scripts/System/logger.gd)) gates debug/info/warn.
- ErrorTranslator maps backend messages to friendly UI ([Scripts/System/error_translator.gd](../Scripts/System/error_translator.gd)).
