# Domain Services

Autoloads and thin domain wrappers over APICalls. Services emit domain events and write to `GameStore`.

Autoloads:
- SignalHub: [Scripts/System/Services/signal_hub.gd](../../Scripts/System/Services/signal_hub.gd)
- GameStore: [Scripts/System/Services/game_store.gd](../../Scripts/System/Services/game_store.gd)

Services:
- MapService: requests map; emits `map_changed`; updates store.
- ConvoyService: refreshes all/single; selection; provides color map; emits `convoys_changed`, `selected_convoy_changed`.
- UserService: refresh/update money/tutorial; emits `user_changed`.
- VendorService: vendor data, panel/preview, buy/sell wrappers; emits vendor events.
- MechanicsService: cargo detail, compat checks, swaps; emits mechanics events.
- RouteService: choices request/ready/error; journey start/cancel.
- WarehouseService: warehouse create/get/expand/store/retrieve/spawn.
- RefreshScheduler: owns polling; intervals configured via [config/app_config.cfg](../../config/app_config.cfg).
- ConvoySelectionService: resolves selection intent to confirmed selection.
