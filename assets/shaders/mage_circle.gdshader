shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 circle_color : source_color = vec4(0.95,0.12,0.055,1.0);
uniform float intensity = 0.0;
uniform float warning_progress = 0.0;
float ring(float radius, float at, float width) {return 1.0-step(width,abs(radius-at));}
void fragment() {
    vec2 p = (floor(UV*96.0)+0.5)/96.0-0.5;
    float r=length(p);
    float a=atan(p.y,p.x);
    float pattern=max(ring(r,0.46,0.008),ring(r,0.385,0.007));
    // Original geometric glyphs: radial strokes and short angular crossbars.
    float wedge=abs(mod(a+3.141593,0.785398)-0.392699);
    pattern=max(pattern,step(0.404,r)*step(r,0.442)*(1.0-step(0.035,wedge)));
    pattern=max(pattern,ring(r,0.425,0.006)*(1.0-step(0.12,wedge)));
    float hex=cos(mod(a+0.523599,1.047198)-0.523599)*r;
    pattern=max(pattern,ring(hex,0.25,0.007));
    pattern=max(pattern,ring(r,0.13,0.008));
    pattern=max(pattern,(1.0-step(0.012,abs(p.x)))*step(abs(p.y),0.08));
    pattern=max(pattern,(1.0-step(0.012,abs(p.y)))*step(abs(p.x),0.08));
    if(pattern<0.5 || intensity<=0.001) discard;
    vec3 color=mix(circle_color.rgb,vec3(1.0,0.38,0.14),step(r,0.28)*0.55);
    ALBEDO=color;
    EMISSION=color*(0.12+0.28*warning_progress);
    ALPHA=intensity*(0.65+0.25*warning_progress);
}
