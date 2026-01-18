#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;


layout(set = 0, binding = 0, rgba32f) uniform image2D texture_out;
layout(set = 0, binding = 1) uniform sampler2D texture_in;


void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(texture_out);
	if (texel.x >= size.x || texel.y >= size.y) {
		return;
	}
	vec2 uv = (vec2(texel) + 0.5) / size;
	vec2 o = 0.5 / size * 3;

	vec4 color = vec4(0.0);
	
	// Sample 4 edge centers with 1x weight each
	color += texture(texture_in, uv + vec2(-o.x * 2.0, 0.0)); // left
	color += texture(texture_in, uv + vec2( o.x * 2.0, 0.0)); // right
	color += texture(texture_in, uv + vec2(0.0, -o.y * 2.0)); // bottom
	color += texture(texture_in, uv + vec2(0.0,  o.y * 2.0)); // top
	
	// Sample 4 diagonal corners with 2x weight each
	color += texture(texture_in, uv + vec2(-o.x,  o.y)) * 2.0; // top-left
	color += texture(texture_in, uv + vec2( o.x,  o.y)) * 2.0; // top-right
	color += texture(texture_in, uv + vec2(-o.x, -o.y)) * 2.0; // bottom-left
	color += texture(texture_in, uv + vec2( o.x, -o.y)) * 2.0; // bottom-right

	color /= 12.0;

	imageStore(texture_out, texel, color);
}
