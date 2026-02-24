shader_type canvas_item;

uniform vec4 target_color : source_color;

// RGB to HSV conversion from Godot documentation/community snippets
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
    
    // Convert current pixel to HSV
    vec3 hsv_base = rgb2hsv(original_color.rgb);
    // Convert target color to HSV
    vec3 hsv_target = rgb2hsv(target_color.rgb);
    
    // Apply target hue and saturation
    // We keep the original 'Value' (brightness) to preserve shading/details
    // We also multiply by target brightness to allow for dark/bright variations
    vec3 out_hsv = vec3(hsv_target.x, hsv_target.y, hsv_base.z * hsv_target.z);
    
    vec3 final_rgb = hsv2rgb(out_hsv);
    
    COLOR = vec4(final_rgb, original_color.a * target_color.a);
}
