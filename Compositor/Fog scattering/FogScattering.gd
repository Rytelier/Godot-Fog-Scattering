@tool
extends CompositorEffect
class_name FogScattering

const path_downscale = "res://Compositor/Fog scattering/blur_downscale.glsl"
const path_upscale = "res://Compositor/Fog scattering/blur_upscale.glsl"
const path_compose = "res://Compositor/Fog scattering/Fog_scattering_compose.glsl"

const file_downscale = preload(path_downscale)
const file_upscale = preload(path_upscale)
const file_compose = preload(path_compose)

@export_range(2, 7, 1) var radius: int = 5
@export_range(0, 1, 0.001) var opacity: float = 0.5
#@export var depth_auto: bool
@export var depth_from: float = 20
@export var depth_to: float = 50


var rd: RenderingDevice

var shader_downscale: RID
var pipeline_downscale: RID
var shader_upscale: RID
var pipeline_upscale: RID
var shader_compose: RID
var pipeline_compose: RID

var textures: Array[RID]

var layers_tmp: int = -1
var size_tmp: Vector2i = Vector2i(-1, -1)

var sampler: RID


func _init() -> void:
	rd = RenderingServer.get_rendering_device()
	
	_initialize_compute()
	if (Engine.is_editor_hint() and not EditorInterface.get_resource_filesystem().resources_reimported.is_connected(reload.bind())):
		EditorInterface.get_resource_filesystem().resources_reimported.connect(reload.bind())


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if shader_compose.is_valid():
			rd.free_rid(shader_compose)
			rd.free_rid(shader_downscale)
			rd.free_rid(shader_upscale)
			rd.free_rid(sampler)
			for tex in textures:
				rd.free_rid(tex)
		
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().resources_reimported.disconnect(reload.bind())


func _initialize_compute() -> void:
	shader_downscale = rd.shader_create_from_spirv(file_downscale.get_spirv())
	shader_upscale = rd.shader_create_from_spirv(file_upscale.get_spirv())
	shader_compose = rd.shader_create_from_spirv(file_compose.get_spirv())
	
	pipeline_downscale = rd.compute_pipeline_create(shader_downscale)
	pipeline_upscale = rd.compute_pipeline_create(shader_upscale)
	pipeline_compose = rd.compute_pipeline_create(shader_compose)
	
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler = rd.sampler_create(sampler_state)


func reload(files : PackedStringArray):
	if files.has(path_compose) or files.has(path_downscale) or files.has(path_upscale):
		_initialize_compute()

func _render_callback(effect_callback_type_: int, render_data: RenderData) -> void:
	if rd and effect_callback_type_ == effect_callback_type:
		var render_scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
		if render_scene_buffers:
			var size := render_scene_buffers.get_internal_size()
			
			if size.x == 0 and size.y == 0:
				return
			
			if radius != layers_tmp or size != size_tmp:
				setup_buffers(size.x, size.y)
			
			@warning_ignore("integer_division")
			var x_groups := (size.x - 1) / 8 + 1
			@warning_ignore("integer_division")
			var y_groups := (size.y - 1) / 8 + 1
			var z_groups := 1
			
			var view_count := render_scene_buffers.get_view_count()
			for view in range(view_count):
				if radius < 1:
					return
				
				var color_image := render_scene_buffers.get_color_layer(view)
				var depth_texture := render_scene_buffers.get_depth_texture()
				
				#var push_constant: PackedFloat32Array = [0, 0, 0, 0]
				
				## Prepare screen color
				var uniform_set_in := rd.uniform_set_create([
					get_sampler_uniform(color_image, 1), # Out
					get_image_uniform(textures[0], 0)], # In
					shader_downscale, 0)
				run_compute(uniform_set_in, pipeline_downscale, x_groups, y_groups, z_groups)
				
				## Downscale
				for layer in range(radius - 1):
					var uniform_set = rd.uniform_set_create(
						[get_sampler_uniform(textures[layer], 1), # Out
						get_image_uniform(textures[layer + 1], 0)], # In
						shader_downscale, 0)
					run_compute(uniform_set, pipeline_downscale, x_groups, y_groups, z_groups)
					
				## Upscale
				for layer in range(radius - 1, 0, -1):
					var uniform_set = rd.uniform_set_create(
						[get_sampler_uniform(textures[layer], 1), # Out
						get_image_uniform(textures[layer - 1], 0)], # In
						shader_downscale, 0)
					run_compute(uniform_set, pipeline_upscale, x_groups, y_groups, z_groups)
				
				## Compose
				var render_scene_data = render_data.get_render_scene_data()
				var view_proj = render_scene_data.get_view_projection(view).inverse()
				var inv_proj_mat: PackedFloat32Array = [
					view_proj.x.x, view_proj.x.y, view_proj.x.z, view_proj.x.w, 
					view_proj.y.x, view_proj.y.y, view_proj.y.z, view_proj.y.w, 
					view_proj.z.x, view_proj.z.y, view_proj.z.z, view_proj.z.w, 
					view_proj.w.x, view_proj.w.y, view_proj.w.z, view_proj.w.w, 
				]
				var mat_bytes = PackedByteArray()
				mat_bytes.append_array(inv_proj_mat.to_byte_array())
				var mat_buffer: RID = rd.uniform_buffer_create(64, mat_bytes)
				
				var uniform_set_out = rd.uniform_set_create([
					get_sampler_uniform(textures[0], 1), # Out
					get_image_uniform(color_image, 0), # In
					get_sampler_uniform(depth_texture, 2),
					get_buffer_uniform(mat_buffer, 3)
					], shader_compose, 0)
				size = render_scene_buffers.get_internal_size()
				
				var push_constant = [size.x, size.y, radius, opacity, depth_from, depth_to, 0, 0,]
				
				@warning_ignore("integer_division")
				x_groups = (size.x - 1) / 8 + 1
				@warning_ignore("integer_division")
				y_groups = (size.y - 1) / 8 + 1
				
				run_compute_c(uniform_set_out, push_constant, pipeline_compose, x_groups, y_groups, z_groups)


#region Helpers
func run_compute(uniform_set: RID, pipeline: RID, x_groups: int, y_groups: int, z_groups: int) -> void:
	var compute_list: = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	rd.compute_list_end()


func run_compute_c(uniform_set: RID, push_constant: PackedFloat32Array, pipeline: RID, x_groups: int, y_groups: int, z_groups: int) -> void:
	var compute_list: = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	rd.compute_list_end()


func get_image_uniform(image : RID, binding : int = 0) -> RDUniform:
	var uniform : RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(image)
	
	return uniform


func get_sampler_uniform(image : RID, binding : int = 0) -> RDUniform:
	var uniform : RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = binding
	uniform.add_id(sampler)
	uniform.add_id(image)
	
	return uniform


func get_buffer_uniform(buffer: RID, binding: int = 0) -> RDUniform:
	var uniform : RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	return uniform


func setup_buffers(w: int, h: int) -> void:
	# Free buffers and textures
	for t in textures: rd.free_rid(t)
	
	textures.clear()
	
	layers_tmp = radius
	size_tmp = Vector2i(w, h)
	
	for i in radius:
		w = maxi(1, w >> 1)
		h = maxi(1, h >> 1)
		
		var texture_format := get_texture_format(w, h)
		
		var texture := rd.texture_create(texture_format, RDTextureView.new())
		textures.push_back(texture)


func get_texture_format(width: int, height: int) -> RDTextureFormat:
	var texture_format := RDTextureFormat.new()
	texture_format.width = width
	texture_format.height = height
	texture_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	texture_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	)
	return texture_format
#endregion
