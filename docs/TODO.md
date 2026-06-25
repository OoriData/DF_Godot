This document will serve as a flowing state of things needed in the project, what resources are needed for each task.

---

## Bugs

### Settings emoji not rendering on map overlay options tab (mobile)
The settings icon/emoji on the map overlay options tab fails to render on mobile (portrait and landscape). Desktop appears unaffected. Likely a font/emoji fallback issue on mobile renderers — check if the character is supported in the loaded font or needs to be replaced with a texture-based icon.

### Auto zoom (Fit Convoy Route) clips city labels
When Fit Convoy Route auto-zoom triggers, city labels are visible but clipped at the edges of the viewport. Labels exist, they're just cut off. Likely the zoom calculation fits the route geometry without accounting for label overflow outside node bounds — need to add padding to the fit rect so labels have room.

### Settlement menu lag on open (iOS)
Noticeable hitch when opening the settlement menu on iOS. First noticed on device but may affect other platforms. Investigate whether the lag is in layout building (node instantiation/resizing on open) or data fetching. Likely candidate: layout recalculation on first open — consider deferring heavy layout work or pre-building the scene.

### Dynamic Island / notch safe area not respected
UI elements (including map options overlay) are rendering underneath the Dynamic Island or notch area on devices where it's open. Reserve that space using iOS safe area insets so nothing interactive or informational sits beneath the cutout.

---

## Improvements

### Increase portrait map zoom-out limit (~3x current max)
The current maximum zoom-out in portrait mode is too restrictive. Increase the zoom-out limit to approximately 3x the current maximum so players can see more of the map at once in portrait orientation.

### Vendor menu — restructure top controls
The vendor settings panel is proportionally fluid and visually inconsistent with the other controls. Restructure as follows:
- **Warehouse button** → move into the bottom nav bar alongside the other menu-switching buttons
- **Top Up button** → move to the Base Convoy Menu (main convoy overview screen)
- **Settings** → replace the inline settings panel with an expandable side drawer so it's out of the way until needed

This clears the top of the vendor menu of clutter and makes the settings feel intentional rather than crammed in.

### Menu close animation shows outside map bounds (portrait)
When closing a menu in portrait, the camera briefly renders outside the map bounds during the closing animation, then snaps back once the animation completes. Investigate whether the map camera constraints are being released or bypassed during the transition — the snap suggests the bounds are re-applied at the end but not enforced mid-animation.

### Cargo menu portrait layout — item card reorganization
In portrait mode, item cards in the cargo list are wide and flat with excessive vertical padding and small text, leaving a lot of dead space in the middle of each card. The double-scaling font migration may have made text smaller without the padding adjusting to match. Investigate whether this is a padding/margin issue or a layout reorganization — cards may benefit from a tighter, more information-dense layout in portrait (e.g. tighter vertical rhythm, better use of horizontal space).

### Cargo menu top buttons cramped in portrait
The action buttons at the top of the cargo menu are stacked too tightly together in portrait. Spread them out — either increase spacing between them or rearrange into a layout that breathes better at portrait widths.

### Cargo menu sort toggle labels are unclear
The "Sort by Vehicle" and "Sort by Type" toggles sort correctly but the labels don't make the distinction obvious enough. Rework the labels so it's immediately clear what each toggle does.

### Select Convoy dropdown too small in portrait (top nav bar)
The Select Convoy control in the top nav bar is currently a small dropdown roughly the same width as the button. Expand it into a wider panel so the full convoy card is visible when selecting. Scrollable list of cards stacked vertically.

### Settlement Preview — remove item count from tab labels
The tabs in Settlement Preview show a count in parentheses e.g. "(10)". Remove these numbers entirely — the count adds noise without value at that point in the flow.

### Journey plotting — add loading bar while API works
While the API is plotting the journey route there's no feedback. Add a loading bar or progress indicator during this wait. A loading screen may exist somewhere in the deprecated code — search the codebase for it as a starting point. A simple animated loading bar overlaid on the journey menu is the target feel.

### Journey confirmation screen — resource label/value gap (landscape)
In the journey confirmation screen on landscape, the resource labels and their corresponding stat values are far apart with a lot of dead space between them. Tighten the table layout so labels and values feel connected — reduce column gap or align values closer to their labels.

### Replace Godot default baby blue with Oori theme colors
Buttons and modals throughout the game are rendering with Godot's default baby blue color, indicating the global Oori theme isn't applied everywhere. Audit all menus for this blue bleed-through and replace with the correct Oori palette colors (defined in `Assets/df_theme.tres` and `Scripts/System/ui_theme.gd`). This is a visible symptom of incomplete theme migration.

### Convoy menu stats — tap to open breakdown modal
Stats displayed in the convoy menu should be tappable, opening the same kind of breakdown modal that already exists for parts and vehicles. Gives players the same level of detail for stats that they get elsewhere in the menu.
