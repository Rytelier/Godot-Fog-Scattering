#[compute]
#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;


layout(rgba16f, binding = 0) uniform image2D screen_image_out;
layout(binding = 1) uniform sampler2D texture_input;
layout(binding = 2) uniform sampler2D texture_depth;


layout(binding = 3) uniform Mat {
	mat4 proj_inv;
} mat;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float scatter_size;
	float mix_factor;
	float depth_from;
	float depth_to;
} params;


float remap(float value, float min1, float max1, float min2, float max2) {
  return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}


void main()
{
	vec2 coord = gl_GlobalInvocationID.xy;
	ivec2 size = ivec2(params.raster_size);

	// Prevent reading/writing out of bounds.
	if (coord.x >= size.x || coord.y >= size.y) {
		return;
	}
	
	vec2 offset = vec2(1.0) / params.raster_size;
	vec2 uv = (coord + vec2(0.5)) * offset;
	vec2 o = 0.5 / size * params.scatter_size * 4.0;

	vec4 blurred = texture(texture_input, uv);

	vec4 screen = imageLoad(screen_image_out, ivec2(coord));

	float depth = texture(texture_depth, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = mat.proj_inv * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	linear_depth = remap(linear_depth, params.depth_from, params.depth_to, 0, 1);
	linear_depth = clamp(linear_depth, 0, 1);

	vec4 color_out = mix(screen, blurred, params.mix_factor * linear_depth);

	imageStore(screen_image_out, ivec2(coord), color_out);
	//imageStore(screen_image_out, ivec2(coord), vec4((linear_depth), 0, 0, 1));
}