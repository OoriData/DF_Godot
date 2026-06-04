shader_type canvas_item;

// Tiles the Oori background using screen-space coordinates so every panel
// that uses this shader shares the same global tile origin — no seams.
uniform sampler2D tile_tex : repeat_enable, filter_nearest_mipmap;
uniform vec2 tile_size = vec2(2210.0, 1604.0); // physical px size of the source image
uniform float scale = 1.0; // lower = bigger tiles on screen; default 1.0 = one tile per tile_size px

void fragment() {
    vec2 uv = FRAGCOORD.xy / (tile_size * scale);
    COLOR = texture(tile_tex, uv);
}
