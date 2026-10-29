shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float clock = 0.0;
uniform float pixel_grid = 24.0;
uniform float opacity = 1.0;
void fragment() {
    vec2 p=(floor(UV*pixel_grid)+0.5)/pixel_grid-0.5;
    float angle=atan(p.y,p.x);
    float flame=0.035*sin(angle*7.0-clock*17.0)+0.025*sin(angle*11.0+clock*11.0);
    float radius=length(p);
    if(radius>0.435+flame) discard;
    float flicker=0.018*sin(p.x*53.0+p.y*37.0-clock*23.0);
    vec3 color=vec3(0.85,0.12,0.035);
    if(radius<0.35+flame) color=vec3(1.0,0.32,0.055);
    if(radius<0.24+flicker) color=vec3(1.0,0.64,0.14);
    if(radius<0.12+flicker) color=vec3(1.0,0.91,0.48);
    ALBEDO=color;
    EMISSION=color*0.18;
    ALPHA=opacity;
}
