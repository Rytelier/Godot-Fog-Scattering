#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;


layout(set = 0, binding = 0, rgba16f) uniform image2D texture_out;
layout(set = 0, binding = 1) uniform sampler2D texture_in;

layout(push_constant, std430) uniform Params {
	float weight;
} params;

void main() {
	ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(texture_out);
	if (texel.x >= size.x || texel.y >= size.y) {
		return;
	}
	vec2 uv = (vec2(texel) + 0.5) / size;
	vec2 o = 0.5 / size * 3;

	vec4 color = vec4(0.0);

	// Sample 4 diagonal corners with 2x weight each
	color += texture(texture_in, uv + vec2(-o.x,  o.y)) * 2.0; // top-left
	color += texture(texture_in, uv + vec2( o.x,  o.y)) * 2.0; // top-right
	color += texture(texture_in, uv + vec2(-o.x, -o.y)) * 2.0; // bottom-left
	color += texture(texture_in, uv + vec2( o.x, -o.y)) * 2.0; // bottom-right

	color /= 8.0;
	color = mix(imageLoad(texture_out, texel), color, 1 - params.weight);

	imageStore(texture_out, texel, color);
}
