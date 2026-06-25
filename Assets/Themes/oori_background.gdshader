shader_type canvas_item;

// Tiles the Oori background using screen-space coordinates so every panel
// that uses this shader shares the same global tile origin — no seams.
uniform sampler2D tile_tex : repeat_enable, filter_nearest_mipmap;
uniform vec2 tile_size = vec2(2210.0, 1604.0); // physical px size of the source image
uniform float scale = 1.0; // lower = bigger tiles on screen; default 1.0 = one tile per tile_size px
uniform vec2 offset = vec2(0.0); // px shift; lets a thin bar land on a chosen band of the pattern
uniform float use_local = 0.0; // 0 = screen-space (FRAGCOORD, aligns panels); 1 = rect-local (static on resize)

varying vec2 v_local; // CanvasItem-local pixel position (anchored to the rect's top-left)

void vertex() {
    v_local = VERTEX;
}

void fragment() {
    vec2 base = use_local > 0.5 ? v_local : FRAGCOORD.xy;
    vec2 uv = (base + offset) / (tile_size * scale);
    COLOR = texture(tile_tex, uv);
}
