shader_type canvas_item;

uniform vec4 target_color : source_color;
uniform bool rainbow_mode = false;

// RGB to HSV conversion
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// HSV to RGB conversion
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
    vec4 original_color = texture(TEXTURE, UV);
    if (original_color.a < 0.01) discard;
    
    // Convert current pixel to HSV
    vec3 hsv_base = rgb2hsv(original_color.rgb);
    
    vec3 hsv_target;
    if (rainbow_mode) {
        // Striped rainbow effect based on UV.x
        float hue = fract(UV.x * 2.5); 
        hsv_target = vec3(hue, 0.8, 1.0);
    } else {
        hsv_target = rgb2hsv(target_color.rgb);
    }
    
    // Apply target hue and saturation while preserving sprite luminosity
    vec3 out_hsv = vec3(hsv_target.x, hsv_target.y, hsv_base.z * hsv_target.z);
    
    vec3 final_rgb = hsv2rgb(out_hsv);
    float final_alpha = original_color.a * (rainbow_mode ? 1.0 : target_color.a);
    
    COLOR = vec4(final_rgb, final_alpha);
}
