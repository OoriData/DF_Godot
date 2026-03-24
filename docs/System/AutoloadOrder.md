# Autoload Order

Recommended order in [project.godot](../project.godot) under `[autoload]`:

1) Utilities:
- [Scripts/System/tools.gd](../Scripts/System/tools.gd)
- [Scripts/System/date_time_util.gd](../Scripts/System/date_time_util.gd)
- [Scripts/System/error_translator.gd](../Scripts/System/error_translator.gd)
- [Scripts/System/settings_manager.gd](../Scripts/System/settings_manager.gd)

2) Transport:
- [Scripts/System/api_calls.gd](../Scripts/System/api_calls.gd)

3) Events/State:
- [Scripts/System/Services/signal_hub.gd](../Scripts/System/Services/signal_hub.gd)
- [Scripts/System/Services/game_store.gd](../Scripts/System/Services/game_store.gd)

4) Domain services:
- Map, Convoy, User, Vendor, Mechanics, Route, Warehouse, RefreshScheduler (under [Scripts/System/Services](../Scripts/System/Services))

5) UI managers:
- [Scripts/Menus/menu_manager.gd](../Scripts/Menus/menu_manager.gd), UI scale manager, TutorialManager
