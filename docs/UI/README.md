# UI / Map Layer

Subscribers to `GameStore` snapshots and `SignalHub` events.

- Main (MapView): [Scripts/System/main.gd](../../Scripts/System/main.gd)
  - Connect to `GameStore.map_changed`/`convoys_changed`; fetch snapshots on init.

- MapInteractionManager: [Scripts/Map/map_interaction_manager.gd](../../Scripts/Map/map_interaction_manager.gd)
  - Source data from store; emit UI-level events; delegate camera input to MapCameraController.

- ConvoyVisualsManager: [Scripts/Map/convoy_visuals_manager.gd](../../Scripts/Map/convoy_visuals_manager.gd)
  - Subscribe to `convoys_changed`; request color map from `ConvoyService`.

- UIManager: [Scripts/UI/UI_manager.gd](../../Scripts/UI/UI_manager.gd)
  - Keep settlement labels and lines; convoy panel logic lives in `convoy_label_manager.gd`.

Acceptance:
- No direct `GameDataManager` wiring; updates flow via store/hub.
