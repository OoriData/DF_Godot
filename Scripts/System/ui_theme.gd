extends Node
## UITheme — single source of truth for Desolate Frontiers UI color + spacing tokens.
##
## Aesthetic: rugged-rusted industrial reclaimed by life (solarpunk hybrid).
## Dark weathered-metal structure, Oori White text, warm brass/cappuccino accents,
## and verdigris as the "living growth" signal. Replaces the palette consts that were
## duplicated across user_info_display.gd, convoy_list_panel.gd, vendor_trade_panel.gd, etc.
##
## Registered as an autoload named `UITheme`. Access tokens statically, e.g.
##   panel.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)

# ---------------------------------------------------------------------------
# Core Oori brand palette
# ---------------------------------------------------------------------------
const METAL_DARK   := Color("#1a1a1f")  ## Deepest shadow / recessed wells
const METAL_BASE   := Color("#25282a")  ## Oori Dark Grey — primary container fill
const METAL_EDGE   := Color("#393d47")  ## Oori Grey — borders, bevels, dividers
const SURFACE_WARM := Color("#633f33")  ## Cappuccino — warm rugged surfaces (leather/wood/rust)

const TEXT_PRIMARY := Color("#dbe2e9")  ## Oori White — primary text + light elements
const TEXT_MUTED   := Color("#8b929c")  ## Desaturated Oori White — captions, secondary
const TEXT_ON_LIGHT := Color("#25282a") ## Dark text for use on light/brass surfaces

const ACCENT_BRASS     := Color("#f3d54e")  ## Oori Yellow — primary accent, currency, active state
const ACCENT_VERDIGRIS := Color("#5aa192")  ## Sanctioned extension — living/growth/resource signal
const DANGER           := Color("#8a2b2b")  ## Oori Red — critical, errors, empty

# ---------------------------------------------------------------------------
# Semantic status (resource/capacity bars, thresholds)
# Traffic-light signal for convoy limits — kept Material-bright on purpose;
# functional readability wins over brand tint here (user preference).
# ---------------------------------------------------------------------------
const STATUS_GOOD := Color("#66bb6a")  ## Material Green 400 — healthy / full
const STATUS_WARN := Color("#ffee58")  ## Material Yellow 400 — low / caution
const STATUS_CRIT := Color("#ef5350")  ## Material Red 400 — critical / empty

# ---------------------------------------------------------------------------
# Derived metal shades (hover / pressed surfaces)
# ---------------------------------------------------------------------------
const METAL_HOVER  := Color("#31353a")  ## Button hover fill
const METAL_ACTIVE := Color("#3a3f47")  ## Pressed / selected fill

# ---------------------------------------------------------------------------
# Spacing system — base unit 8px (audit cross-cutting issue #9)
# ---------------------------------------------------------------------------
const SPACE_XS  := 4
const SPACE_SM  := 8
const SPACE_MD  := 12
const SPACE_LG  := 16
const SPACE_XL  := 24
const SPACE_XXL := 32

# ---------------------------------------------------------------------------
# Corner radii — softened, hand-rebuilt feel (not pristine sci-fi)
# ---------------------------------------------------------------------------
const RADIUS_SM := 4
const RADIUS_MD := 6
const RADIUS_LG := 8

# ---------------------------------------------------------------------------
# Border widths
# ---------------------------------------------------------------------------
const BORDER_THIN  := 1
const BORDER_ACCENT := 3  ## Active-state accent edge (brass bottom border, etc.)


## Returns the threshold color for a 0..1 fill ratio (resource/capacity bars).
func status_for_ratio(ratio: float) -> Color:
	if ratio <= 0.20:
		return STATUS_CRIT
	elif ratio <= 0.45:
		return STATUS_WARN
	return STATUS_GOOD

# ---------------------------------------------------------------------------
# Oori background — screen-space tiled texture
# ---------------------------------------------------------------------------
const OORI_BG_TEXTURE  := "res://Assets/Themes/Oori Backround.png"
const OORI_BG_SHADER   := "res://Assets/Themes/oori_background.gdshader"
## Physical pixel dimensions of the source tile image.
const OORI_BG_TEX_SIZE := Vector2(2210.0, 1604.0)
## Scale factor: fraction of the source image that equals one tile on screen.
## 0.5 ≈ one tile per 1105×802 physical px — adjust to taste.
const OORI_BG_SCALE    := 0.5

## Returns a ShaderMaterial that tiles the Oori background using FRAGCOORD so
## every panel sharing this material stays perfectly aligned with neighbours.
## Call once and reuse the result — ShaderMaterial is safe to share.
##
## scale_override: pass a value > 0 to use a different on-screen tile size than the
##   shared OORI_BG_SCALE (e.g. a thin bar wants a denser tile so it fills evenly
##   instead of showing one arbitrary slice). -1 keeps the global default.
## offset_px: pixel shift, lets a thin bar centre on a chosen band.
## use_local: true tiles from the rect's own top-left in logical px so the pattern
##   stays put when the window is stretched (instead of sliding/scaling in screen
##   space). Leave false for full-screen/menu backgrounds that want panels aligned.
func make_oori_bg_material(scale_override: float = -1.0, offset_px: Vector2 = Vector2.ZERO, use_local: bool = false) -> ShaderMaterial:
	var shader = load(OORI_BG_SHADER) as Shader
	if not shader:
		push_warning("UITheme: could not load Oori background shader at %s" % OORI_BG_SHADER)
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var tex = load(OORI_BG_TEXTURE) as Texture2D
	mat.set_shader_parameter("tile_tex", tex)
	mat.set_shader_parameter("tile_size", OORI_BG_TEX_SIZE)
	mat.set_shader_parameter("scale", OORI_BG_SCALE if scale_override <= 0.0 else scale_override)
	mat.set_shader_parameter("offset", offset_px)
	mat.set_shader_parameter("use_local", 1.0 if use_local else 0.0)
	return mat

## Applies the Oori tile shader to a TextureRect in-place.
## Sets the texture, expand/stretch mode, and material so every call site is
## a one-liner: UITheme.apply_oori_bg(my_texture_rect)
## See make_oori_bg_material() for scale_override / offset_px / use_local.
func apply_oori_bg(rect: TextureRect, scale_override: float = -1.0, offset_px: Vector2 = Vector2.ZERO, use_local: bool = false) -> void:
	if not is_instance_valid(rect):
		return
	var tex = load(OORI_BG_TEXTURE) as Texture2D
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Local mode needs a single quad (VERTEX = rect-local px); screen-space mode is
	# unaffected by stretch_mode since it samples by FRAGCOORD.
	rect.stretch_mode = TextureRect.STRETCH_SCALE if use_local else TextureRect.STRETCH_TILE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = make_oori_bg_material(scale_override, offset_px, use_local)
