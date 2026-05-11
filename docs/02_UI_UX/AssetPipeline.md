# Asset Pipeline & Standards

This document defines the technical standards for adding and managing visual assets in *Desolate Frontiers*.

## 1. Directory Structure

- `Assets/`: Root for all raw assets (PNG, TTF, SVG).
- `Assets/Themes/`: Global UI backgrounds and shared visual elements (e.g., `Oori Backround.png`).
- `Assets/tiles/`: Map terrain textures and tile set definitions.
- `Assets/apple_icons/` / `android_icons/`: Platform-specific launcher icons.

---

## 2. Textures & UI Elements

### Import Settings
- **UI Elements**: Use `compress/mode=0` (Lossless) for UI icons and banners to prevent artifacting.
- **Backgrounds**: Large backgrounds can use `compress/mode=2` (VRAM Compressed) to save memory if necessary, but keep `mipmaps/generate=false` for screen-space UI.
- **Fix Alpha Border**: Should be `true` for all PNGs with transparency to prevent dark outlines during scaling.

### Naming Conventions
- Use PascalCase or snake_case consistently for new assets.
- Append `@2x` or `@3x` if using traditional resolution-aware scaling (though the project prefers logical scaling via `UIScaleManager`).

---

## 3. Typography (Fonts)

### Standard Font
The primary font is **Lexend Light**. It is wrapped in a `FontVariation` resource (`Assets/main_font.tres`) that includes fallbacks for Emojis and Mathematical symbols.

### Standards
- **MSDF (Highly Recommended)**: For labels that need to stay crisp while scaling dynamically (especially on the map), enable `multichannel_signed_distance_field=true` in the `.ttf` import settings.
- **Pixel Range**: Use `8` or `16` for MSDF range to prevent "bleeding" at high zoom levels.
- **Fallbacks**: Always ensure `main_font.tres` is used instead of direct `.ttf` files to preserve emoji support.

---

## 4. Map Tiles

The map system uses a unified `tile_set.tres` located in `Assets/tiles/`.

- **Dimensions**: All tile PNGs should be standardized (e.g., 64x64 or 128x128).
- **Mipmaps**: For map tiles, set `mipmaps/generate=true`. This prevents "shimmering" when the player zooms out to the tactical view.
- **Filter**: Enable `Texture Filter: Linear` for a smooth look or `Nearest` if the project moves toward a retro/pixel-art aesthetic.

---

## 5. Deployment Assets

- **Launch Images**: Must follow Apple/Android specific aspect ratio requirements.
- **App Store Icons**: Ensure no transparency is present in the final App Store icon (Apple requirement).
