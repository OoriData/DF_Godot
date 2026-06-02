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
