# Scenes Docs

Primary scenes:
- [Scenes/MapView.tscn](MapView.tscn): SubViewport map render, driven by `main.gd` and Map layer scripts.
- [Scenes/GameRoot.tscn](GameRoot.tscn): Ensure `SignalHub` and `GameStore` autoloads init before listeners.

Verification:
- Re-save [Scenes/ConvoyMenu.tscn](ConvoyMenu.tscn) and [Scenes/ConvoyVehicleMenu.tscn](ConvoyVehicleMenu.tscn) to refresh ext_resource UIDs and remove fallback warnings.

Autoload order guidance: see [docs/AutoloadOrder.md](../docs/AutoloadOrder.md).
