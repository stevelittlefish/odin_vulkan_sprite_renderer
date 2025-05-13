package game

import "base:runtime"
import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:time"
import "core:math"
import "core:math/rand"
import "core:slice"
import "core:math/linalg/glsl"
import "core:c"
import sdl "vendor:sdl3"

import vk "vendor:vulkan"

import "vkx"

// Struct for vertex based geometry (i.e. the tiles)
Vertex :: struct {
	pos: glsl.vec3,
	tex_coord: glsl.vec2,
}

// Struct for the uniform buffer object for all shaders
UniformBufferObject :: struct #packed {
	// Time to use in shaders
	t: f32,
	
	// Alignment issues...
	_: f32,
	_: f32,
	_: f32,

	// Matrices for sprites
	// This is basically the limit to fit the ubo in 64k
	mvps: [1000]glsl.mat4,
}

// This struct stores a sprite in a vertex array
VertexBufferSprite :: struct {
	// RGBA colour for rendering
	color: glsl.vec4,
	// Texture coordinates
	uv: glsl.vec2,
	uv2: glsl.vec2,
	// Texture index
	texture_index: u32,
	// Index into arrays in ubo
	sprite_index: u32,
}

// Push constants used by the tilemap (default) renderer
PushConstants :: struct {
	// Single combined model view projection matrix
	mvp: glsl.mat4,
	// RGBA colour for rendering
	color: glsl.vec4,
	// Texture index
	texture_index: u32,
}

// Monster struct for game logic
Monster :: struct {
	pos: glsl.dvec3,
	spd: glsl.dvec2,
	color: glsl.vec4,
	texture: u32,
}

// Texture indices
Texture :: enum {
	TEX_TILES,
	TEX_MONSTERS,
	TEX_MONSTERS2,
	TEX_MONSTERS3,
	TEX_MONSTERS4,
}

TILESET_X_TILES :: 3
TILESET_Y_TILES :: 3

TILESET_TOTAL_TILES :: (TILESET_X_TILES * TILESET_Y_TILES)
EMPTY :: TILESET_TOTAL_TILES

X_TILES :: 32
Y_TILES :: 24

TOTAL_TILES :: (X_TILES * Y_TILES)

NUM_MONSTERS :: 1000

LIMIT_FPS :: false
MIN_FRAME_TIME :: 1.0 / 120.0

SCREEN_WIDTH :: X_TILES * 32
SCREEN_HEIGHT :: Y_TILES * 32

DEFAULT_WIDTH :: X_TILES * 32
DEFAULT_HEIGHT :: Y_TILES * 32

limit_fps :: false
min_frame_time :: 1.0 / 120.0

// SDL Window handle
window: ^sdl.Window = nil

// Single descriptor pool for the whole app
descriptor_pool: vk.DescriptorPool
// Descriptor sets for the main pipelines
descriptor_sets: [vkx.FRAMES_IN_FLIGHT]vk.DescriptorSet
// Descriptor sets for the screen pipeline
screen_descriptor_sets: [vkx.FRAMES_IN_FLIGHT]vk.DescriptorSet

// Which frame in the frames in flight are we rendering?
current_frame: u32 = 0

// Tile data - which visual tile to display (or EMPTY)
tiles: [TOTAL_TILES]u8

// Vertices for the tilemap geometry
vertices: [dynamic]Vertex

// Indices for the tilemap geometry
vertex_indices: [dynamic]u16

// "Vertices" for the sprites
vertex_sprites: [dynamic]VertexBufferSprite

// Buffers to feed the pipelines
vertex_buffer: vkx.Buffer
index_buffer: vkx.Buffer
sprite_vertex_buffer: vkx.Buffer

// Monster data
monsters: [NUM_MONSTERS]Monster

// Tile pipeline draws the tiles from the vertex data
tile_pipeline: vkx.Pipeline
// Screen pipeline for blitting offscreen image to the swapchain
screen_pipeline: vkx.Pipeline
// Sprite pipeline generates its own vertices in the shader
sprite_pipeline: vkx.Pipeline

// Textures to render (sprites and tiles)
textures: [dynamic]vkx.Image
texture_sampler: vk.Sampler

// Offscreen image for rendering to
offscreen_images: [vkx.FRAMES_IN_FLIGHT]vkx.Image
depth_images: [vkx.FRAMES_IN_FLIGHT]vkx.Image

// Uniform buffer used in all pipelines
uniform_buffers: [vkx.FRAMES_IN_FLIGHT]vkx.Buffer
uniform_buffers_mapped: [vkx.FRAMES_IN_FLIGHT]rawptr

// Matrices for rendering
projection_matrix: glsl.mat4
view_matrix: glsl.mat4

// The current time
t: f64
// Timestamp of the previous frame
t_last: f64
// Rolling FPS count
frame_count: int
// Timestamp of last FPS print
last_fps_time: f64

// If the swap chain is suboptimal, we record how many cycles it was suboptimal for
// in this variable as some older graphics cards occasionally report this for just
// a single cycle and recreating the swap chain causes more problems than it solves
// in that particular situation
suboptimal_swapchain_count := 0
SUBOPTIMAL_SWAPCHAIN_THRESHOLD :: 10

// Used to recreate swap chain on resize
framebuffer_resized := false

// Are we running in fullscreen mode?
fullscreen := false

get_binding_description :: proc() -> vk.VertexInputBindingDescription {
	binding_description := vk.VertexInputBindingDescription{
		binding = 0,
		stride = size_of(Vertex),
		inputRate = .VERTEX,
	}

	return binding_description
}

get_attribute_descriptions :: proc() -> [2]vk.VertexInputAttributeDescription {
	attribute_descriptions := [2]vk.VertexInputAttributeDescription {
		{
			binding = 0,
			location = 0,
			format = .R32G32B32_SFLOAT,
			offset = cast(u32) offset_of(Vertex, pos),
		},
		{
			binding = 0,
			location = 1,
			format = .R32G32_SFLOAT,
			offset = cast(u32) offset_of(Vertex, tex_coord),
		}
	}
	return attribute_descriptions
}

get_sprite_binding_description :: proc() -> vk.VertexInputBindingDescription {
	binding_description := vk.VertexInputBindingDescription {
		binding = 0,
		stride = size_of(VertexBufferSprite),
		inputRate = .VERTEX,
	}

	return binding_description
}

get_sprite_attribute_descriptions :: proc() -> [5]vk.VertexInputAttributeDescription {
	attribute_descriptions := [5]vk.VertexInputAttributeDescription {
		{
			binding = 0,
			location = 0,
			format = .R32G32B32A32_SFLOAT,
			offset = cast(u32) offset_of(VertexBufferSprite, color),
		},
		{
			binding = 0,
			location = 1,
			format = .R32G32_SFLOAT,
			offset = cast(u32) offset_of(VertexBufferSprite, uv),
		},
		{
			binding = 0,
			location = 2,
			format = .R32G32_SFLOAT,
			offset = cast(u32) offset_of(VertexBufferSprite, uv2),
		},
		{
			binding = 0,
			location = 3,
			format = .R32_UINT,
			offset = cast(u32) offset_of(VertexBufferSprite, texture_index),
		},
		{
			binding = 0,
			location = 4,
			format = .R32_UINT,
			offset = cast(u32) offset_of(VertexBufferSprite, sprite_index),
		},
	}
	
	return attribute_descriptions
}

create_texture_sampler :: proc() {
	// Query the physical device limits
	properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(vkx.instance.physical_device, &properties)

	sampler_info := vk.SamplerCreateInfo {
		sType = .SAMPLER_CREATE_INFO,
		magFilter = .NEAREST,
		minFilter = .LINEAR,
		addressModeU = .CLAMP_TO_EDGE,
		addressModeV = .CLAMP_TO_EDGE,
		addressModeW = .CLAMP_TO_EDGE,
		anisotropyEnable = true,
		maxAnisotropy = properties.limits.maxSamplerAnisotropy,
		borderColor = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
		compareEnable = false,
		compareOp = .ALWAYS,
		mipmapMode = .LINEAR,
		mipLodBias = 0.0,
		minLod = 0.0,
		maxLod = 0.0,
	}
	
	if vk.CreateSampler(vkx.instance.device, &sampler_info, nil, &texture_sampler) != .SUCCESS {
		fmt.eprintf("failed to create texture sampler!\n")
		os.exit(1)
	}
}


/*
 * Return the index of the tile at (x, y)
 */
get_tile_index :: proc(x, y: int) -> int {
	return x + y * X_TILES
}

create_tiles :: proc() {
	// The number of occupied tiles
	num_tiles := 0

	// Generate a random set of tiles
	for y := Y_TILES - 1; y >= 0; y -= 1 {
		for x := 0; x < X_TILES; x += 1 {
			idx := get_tile_index(x, y)

			if x == 0 || x == X_TILES - 1 || y == 0 || y == Y_TILES - 1 {
				// Edge tiles are always occupied
				tiles[idx] = 0
			} else if(rand.int_max(3) >= 2) {
				// 2/3 of the rest are empty
				tiles[idx] = u8(rand.int_max(TILESET_TOTAL_TILES))
			} else {
				tiles[idx] = EMPTY
			}

			if (tiles[idx] != EMPTY) {
				num_tiles += 1
			}

			// Debug test stuff
			if (tiles[idx] == EMPTY) {
				fmt.print("-- ")
			}
			else {
				if (tiles[idx] < 10) {
					fmt.print("0")
				}
				fmt.printf("%d ", tiles[idx])
			}
		}
		fmt.print("\n")
	}
	
	// Generate the mesh for the tilemap
	
	// First let's allocate some memory for the vertices and indices
	// We need 4 vertices per tile, and 6 indices per tile
	vertices = make([dynamic]Vertex, num_tiles * 4)
	vertex_indices = make([dynamic]u16, num_tiles * 6)

	// Loop through and add the geometry for each tile
	vertex_idx := 0
	index_idx := 0

	for x := 0; x < X_TILES; x += 1 {
		for y := 0; y < Y_TILES; y += 1 {
			idx := get_tile_index(x, y)
			if tiles[idx] == EMPTY {
				continue
			}

			// We need to calculate the grid coords of the texture tile
			tileset_idx := tiles[idx]
			tileset_x := tileset_idx % TILESET_X_TILES
			tileset_y := tileset_idx / TILESET_X_TILES

			// Tiles are 1x1, so we can just use the x and y coordinates as the vertex positions
			// We can leave all z coordinates as 0.0f. We'll update colours later
			
			// Bottom left
			vertices[vertex_idx].pos[0] = f32(x)
			vertices[vertex_idx].pos[1] = f32(y)
			vertices[vertex_idx].tex_coord[0] = f32(tileset_x) / TILESET_X_TILES
			vertices[vertex_idx].tex_coord[1] = f32(tileset_y) / TILESET_Y_TILES + 1.0 / TILESET_Y_TILES
			vertex_idx += 1

			// Bottom right
			vertices[vertex_idx].pos[0] = f32(x) + 1.0
			vertices[vertex_idx].pos[1] = f32(y)
			vertices[vertex_idx].tex_coord[0] = f32(tileset_x) / TILESET_X_TILES + 1.0 / TILESET_X_TILES
			vertices[vertex_idx].tex_coord[1] = f32(tileset_y) / TILESET_Y_TILES + 1.0 / TILESET_Y_TILES
			vertex_idx += 1

			// Top right
			vertices[vertex_idx].pos[0] = f32(x) + 1.0
			vertices[vertex_idx].pos[1] = f32(y) + 1.0
			vertices[vertex_idx].tex_coord[0] = f32(tileset_x) / TILESET_X_TILES + 1.0 / TILESET_X_TILES
			vertices[vertex_idx].tex_coord[1] = f32(tileset_y) / TILESET_Y_TILES
			vertex_idx += 1

			// Top left
			vertices[vertex_idx].pos[0] = f32(x)
			vertices[vertex_idx].pos[1] = f32(y) + 1.0
			vertices[vertex_idx].tex_coord[0] = f32(tileset_x) / TILESET_X_TILES
			vertices[vertex_idx].tex_coord[1] = f32(tileset_y) / TILESET_Y_TILES
			vertex_idx += 1

			// Now we need to add the indices for this tile
			vertex_indices[index_idx] = u16(vertex_idx - 4)      // Bottom left
			vertex_indices[index_idx + 1] = u16(vertex_idx - 3)  // Bottom right
			vertex_indices[index_idx + 2] = u16(vertex_idx - 2)  // Top right
			vertex_indices[index_idx + 3] = u16(vertex_idx - 2)  // Top right
			vertex_indices[index_idx + 4] = u16(vertex_idx - 1)  // Top left
			vertex_indices[index_idx + 5] = u16(vertex_idx - 4)  // Bottom left
			index_idx += 6
		}
	}
}

create_monsters :: proc() {
	// Create the array to hold sprite data (6 "vertices" per monster)
	vertex_sprites = make([dynamic]VertexBufferSprite, NUM_MONSTERS * 6)

	// Create the monsters and their and their "sprites"
	for i := 0; i < NUM_MONSTERS; i += 1 {
		monsters[i].pos[0] = rand.float64_range(0, X_TILES)
		monsters[i].pos[1] = rand.float64_range(0, Y_TILES)
		// Half of the monsters will be in front of the tiles and half
		// will be behind
		monsters[i].pos[2] = rand.float64_range(1, 19)

		monsters[i].spd[0] = rand.float64_range(-5, 5)
		monsters[i].spd[1] = rand.float64_range(-5, 5)
		
		// Fade to blue as the monsters z coord puts them in the background
		blue_fade: f32 = cast(f32) monsters[i].pos[2] / 20.0
		monsters[i].color[0] = 1.0 - blue_fade
		monsters[i].color[1] = 1.0 - blue_fade
		monsters[i].color[2] = 1.0 - blue_fade * 0.6
		monsters[i].color[3] = 1.0

		monsters[i].texture = u32(Texture.TEX_MONSTERS) + u32((i / 16) % 4)

		assert(monsters[i].texture < len(Texture))
		assert(monsters[i].texture >= u32(Texture.TEX_MONSTERS))

		// Create the sprite vertices
		for j := 0; j < 6; j += 1 {
			idx := i * 6 + j
			assert(idx < len(vertex_sprites))

			for k := 0; k < 4; k += 1 {
				vertex_sprites[idx].color[k] = monsters[i].color[k]
			}
			// Calculate uv index base on 8x8 grid of sprites
			sprite_x := i % 4
			sprite_y := (i % 16) / 4
			uv_scale: f32 = 1.0 / 4.0

			vertex_sprites[idx].uv[0] = uv_scale * f32(sprite_x)
			vertex_sprites[idx].uv[1] = uv_scale * f32(sprite_y)
			vertex_sprites[idx].uv2[0] = vertex_sprites[idx].uv[0] + uv_scale
			vertex_sprites[idx].uv2[1] = vertex_sprites[idx].uv[1] + uv_scale
			vertex_sprites[idx].texture_index = monsters[i].texture
			vertex_sprites[idx].sprite_index = u32(i)

			assert(vertex_sprites[idx].uv[0] >= 0.0)
			assert(vertex_sprites[idx].uv[0] <= 1.0)
			assert(vertex_sprites[idx].uv[1] >= 0.0)
			assert(vertex_sprites[idx].uv[1] <= 1.0)
			assert(vertex_sprites[idx].uv2[0] >= 0.0)
			assert(vertex_sprites[idx].uv2[0] <= 1.0)
			assert(vertex_sprites[idx].uv2[1] >= 0.0)
			assert(vertex_sprites[idx].uv2[1] <= 1.0)
		}
	}
}

init_vulkan :: proc() {
	// ----- Initialise the vulkan instance and devices -----
	vkx.init_instance(window)

	// ----- Create the swap chain -----
	vkx.create_swap_chain()
	
	// ----- Create the tile graphics pipeline -----
	// Vertex input bindng and attributes
	binding_description := get_binding_description()
	attribute_descriptions := get_attribute_descriptions()
	
	// Push constants for pushing matrices etc.
	push_constant_range := vk.PushConstantRange {
		stageFlags = {.VERTEX, .FRAGMENT},
		offset = 0,
		size = size_of(PushConstants),
	}

	tile_pipeline = vkx.create_vertex_buffer_pipeline(
		"shaders/tiles.vert.spv",
		"shaders/tiles.frag.spv",
		binding_description,
		attribute_descriptions[:],
		push_constant_range,
		len(Texture),
	)
	
	// ----- Create the sprite graphics pipeline -----
	// Vertex input binding and attributes
	sprite_binding_description := get_sprite_binding_description()
	sprite_attribute_descriptions := get_sprite_attribute_descriptions()

	// Push constants are the same (actually not used by the sprite shaders)
	sprite_pipeline = vkx.create_vertex_buffer_pipeline(
		"shaders/sprite.vert.spv",
		"shaders/sprite.frag.spv",
		sprite_binding_description,
		sprite_attribute_descriptions[:],
		push_constant_range,
		len(Texture),
	)
	
	// Screen pipeline is simple and has no vertex input
	screen_pipeline = vkx.create_screen_pipeline(
		"shaders/screen.vert.spv",
		"shaders/screen.frag.spv"
	)

	// ----- Create the buffers -----
	// Vertex buffer
	vertex_buffer = vkx.create_and_populate_buffer(
			raw_data(vertices),
			cast(vk.DeviceSize) (size_of(vertices[0]) * len(vertices)),
			{.VERTEX_BUFFER},
	)

	// Index buffer
	index_buffer = vkx.create_and_populate_buffer(
			raw_data(vertex_indices),
			cast(vk.DeviceSize) (size_of(vertex_indices[0]) * len(vertex_indices)),
			{.INDEX_BUFFER},
	)

	// Sprite vertex buffer
	sprite_vertex_buffer = vkx.create_and_populate_buffer(
			raw_data(vertex_sprites),
			cast(vk.DeviceSize) (size_of(vertex_sprites[0]) * len(vertex_sprites)),
			{.VERTEX_BUFFER},
	)
	
	// ----- Load the texture images -----
	// These must be loaded in the same order as the Texture enum
	append(&textures, vkx.create_texture_image("textures/tiles.png"))
	append(&textures, vkx.create_texture_image("textures/monsters1.png"))
	append(&textures, vkx.create_texture_image("textures/monsters2.png"))
	append(&textures, vkx.create_texture_image("textures/monsters3.png"))
	append(&textures, vkx.create_texture_image("textures/monsters4.png"))

	assert(len(textures) == len(Texture))

	// Create the texture sampler
	create_texture_sampler()
	
	// ----- Create the uniform buffer -----
	ubo_size: vk.DeviceSize = size_of(UniformBufferObject)
	if ubo_size > 65536 {
		fmt.eprintfln("Tried to allocate a buffer with %d bytes, which is greater than the maximum (65536)", ubo_size)
		os.exit(1)
	}

	for i := 0; i < len(uniform_buffers); i += 1 {
		uniform_buffers[i] = vkx.create_buffer(
			ubo_size,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
		);

		// Map the buffer memory and copy the vertex data into it
		vk.MapMemory(vkx.instance.device, uniform_buffers[i].memory, 0, ubo_size, {}, &uniform_buffers_mapped[i])
	}

	// ----- Create the offscreen images -----
	depth_format := vkx.find_depth_format()

	for i := 0; i < len(offscreen_images); i += 1 {
		offscreen_images[i] = vkx.create_image(
			SCREEN_WIDTH,
			SCREEN_HEIGHT,
			vkx.swap_chain.image_format,
			.OPTIMAL,
			{.COLOR_ATTACHMENT, .SAMPLED},
			{.DEVICE_LOCAL},
		)

		offscreen_images[i].view = vkx.create_image_view(
			offscreen_images[i].image,
			vkx.swap_chain.image_format,
			{.COLOR},
		)

		// transition the image layout to color attachment optimal
		vkx.transition_image_layout_tmp_buffer(
			offscreen_images[i].image,
			vkx.swap_chain.image_format,
			.UNDEFINED,
			.SHADER_READ_ONLY_OPTIMAL,
		)

		// And depth images too
		depth_images[i] = vkx.create_image(
			SCREEN_WIDTH,
			SCREEN_HEIGHT,
			depth_format,
			.OPTIMAL,
			{.DEPTH_STENCIL_ATTACHMENT},
			{.DEVICE_LOCAL},
		)

		depth_images[i].view = vkx.create_image_view(depth_images[i].image, depth_format, {.DEPTH})

		// Transition the image layout to depth stencil attachment
		vkx.transition_image_layout_tmp_buffer(
			depth_images[i].image, depth_format,
			.UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
		)
	}

	// ----- Create the descriptor pool -----
	desc_pool_sizes:= [?]vk.DescriptorPoolSize {
		{
			type = .UNIFORM_BUFFER,
			descriptorCount = vkx.FRAMES_IN_FLIGHT * 2,
		},
		{
			type = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = cast(u32) (vkx.FRAMES_IN_FLIGHT * len(textures) + vkx.FRAMES_IN_FLIGHT),
		},
	}
	
	desc_pool_info := vk.DescriptorPoolCreateInfo {
		sType = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = 2,
		pPoolSizes = &desc_pool_sizes[0],
		maxSets = vkx.FRAMES_IN_FLIGHT * 2,
	}

	if vk.CreateDescriptorPool(vkx.instance.device, &desc_pool_info, nil, &descriptor_pool) != .SUCCESS {
		fmt.eprintf("failed to create descriptor pool!\n")
		os.exit(1)
	}
	
	{
		// ----- Create the descriptor sets -----
		ds_layouts: [vkx.FRAMES_IN_FLIGHT]vk.DescriptorSetLayout
		for i := 0; i < vkx.FRAMES_IN_FLIGHT; i += 1 {
			ds_layouts[i] = tile_pipeline.descriptor_set_layout
		}
		
		ds_alloc_info := vk.DescriptorSetAllocateInfo {
			sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool = descriptor_pool,
			descriptorSetCount = vkx.FRAMES_IN_FLIGHT,
			pSetLayouts = &ds_layouts[0],
		}
		
		// Create the base descriptor sets
		if vk.AllocateDescriptorSets(vkx.instance.device, &ds_alloc_info, &descriptor_sets[0]) != .SUCCESS {
			fmt.eprintf("failed to allocate descriptor sets!\n")
			os.exit(1)
		}

		for i := 0; i < vkx.FRAMES_IN_FLIGHT; i += 1 {
			buffer_info := vk.DescriptorBufferInfo {
				buffer = uniform_buffers[i].buffer,
				offset = 0,
				range = size_of(UniformBufferObject),
			}

			image_infos: [dynamic]vk.DescriptorImageInfo
			
			for texture in textures {
				append(
					&image_infos,
					vk.DescriptorImageInfo {
						imageLayout = .SHADER_READ_ONLY_OPTIMAL,
						imageView = texture.view,
						sampler = texture_sampler,
					}
				)
			}

			descriptor_writes := [?]vk.WriteDescriptorSet {
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = descriptor_sets[i],
					dstBinding = 0,
					dstArrayElement = 0,
					descriptorType = .UNIFORM_BUFFER,
					descriptorCount = 1,
					pBufferInfo = &buffer_info,
					pImageInfo = nil,
					pTexelBufferView = nil,
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = descriptor_sets[i],
					dstBinding = 1,
					dstArrayElement = 0,
					descriptorType = .COMBINED_IMAGE_SAMPLER,
					descriptorCount = cast(u32) len(image_infos),
					pBufferInfo = nil,
					pImageInfo = raw_data(image_infos),
					pTexelBufferView = nil,
				},
			}

			vk.UpdateDescriptorSets(vkx.instance.device, 2, &descriptor_writes[0], 0, nil)
		}
	}

	{
		// ----- Create the screen descriptor sets -----
		ds_layouts: [vkx.FRAMES_IN_FLIGHT]vk.DescriptorSetLayout
		for i := 0; i < vkx.FRAMES_IN_FLIGHT; i += 1 {
			ds_layouts[i] = screen_pipeline.descriptor_set_layout
		}

		ds_alloc_info := vk.DescriptorSetAllocateInfo {
			sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool = descriptor_pool,
			descriptorSetCount = vkx.FRAMES_IN_FLIGHT,
			pSetLayouts = &ds_layouts[0],
		}
		
		// Create the base descriptor sets
		if vk.AllocateDescriptorSets(vkx.instance.device, &ds_alloc_info, &screen_descriptor_sets[0]) != .SUCCESS {
			fmt.eprintf("failed to allocate screen descriptor sets!\n")
			os.exit(1)
		}

		for i := 0; i < vkx.FRAMES_IN_FLIGHT; i += 1 {
			buffer_info := vk.DescriptorBufferInfo {
				buffer = uniform_buffers[i].buffer,
				offset = 0,
				range = size_of(UniformBufferObject),
			}

			image_info := vk.DescriptorImageInfo {
				imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				imageView = offscreen_images[i].view,
				sampler = texture_sampler,
			}

			descriptor_writes := [?]vk.WriteDescriptorSet {
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = screen_descriptor_sets[i],
					dstBinding = 0,
					dstArrayElement = 0,
					descriptorType = .UNIFORM_BUFFER,
					descriptorCount = 1,
					pBufferInfo = &buffer_info,
					pImageInfo = nil,
					pTexelBufferView = nil,
				},
				{
					sType = .WRITE_DESCRIPTOR_SET,
					dstSet = screen_descriptor_sets[i],
					dstBinding = 1,
					dstArrayElement = 0,
					descriptorType = .COMBINED_IMAGE_SAMPLER,
					descriptorCount = 1,
					pBufferInfo = nil,
					pImageInfo = &image_info,
					pTexelBufferView = nil,
				},
			}

			vk.UpdateDescriptorSets(vkx.instance.device, 2, &descriptor_writes[0], 0, nil)
		}
	}

	// ----- Create the semaphores and fences -----
	vkx.init_sync_objects()

	fmt.println("Initiialisation complete")
}

update :: proc(dt: f64) {
	for i := 0; i < NUM_MONSTERS; i += 1 {
		if (monsters[i].spd[0] > 0 && monsters[i].pos[0] >= X_TILES) {
			monsters[i].spd[0] *= -1
		}
		else if (monsters[i].spd[0] < 0 && monsters[i].pos[0] <= 0) {
			monsters[i].spd[0] *= -1
		}
		else {
			monsters[i].pos[0] += dt * monsters[i].spd[0]
		}

		if (monsters[i].spd[1] > 0 && monsters[i].pos[1] >= Y_TILES) {
			monsters[i].spd[1] *= -1
		}
		else if (monsters[i].spd[1] < 0 && monsters[i].pos[1] <= 0) {
			monsters[i].spd[1] *= -1
		}
		else {
			monsters[i].pos[1] += dt * monsters[i].spd[1]
		}
	}

	// FPS count
	frame_count += 1

	if t - last_fps_time >= 1.0 {
		total_time := t - last_fps_time
		fps := int(f64(frame_count) / total_time)
		fmt.printf("FPS: %d\n", fps)
		fmt.printf("Frame time: %f ms\n", (total_time / f64(frame_count)) * 1000.0)
		frame_count = 0
		last_fps_time = t
	}
}

record_command_buffer :: proc(command_buffer: vk.CommandBuffer, image_index: u32) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	if vk.BeginCommandBuffer(command_buffer, &begin_info) != .SUCCESS {
		fmt.eprint("failed to begin recording command buffer!\n")
		os.exit(1)
	}
	
	// Memory barrier to transition from present source to color attachment
	vkx.transition_image_layout(
		command_buffer,
		vkx.swap_chain.images[image_index],
		vkx.swap_chain.image_format,
		.PRESENT_SRC_KHR,
		.COLOR_ATTACHMENT_OPTIMAL,
	)

	// Memory barrier to transition the offscreen image from color attachment to shader read
	vkx.transition_image_layout(
		command_buffer,
		offscreen_images[current_frame].image,
		vkx.swap_chain.image_format,
		.SHADER_READ_ONLY_OPTIMAL,
		.COLOR_ATTACHMENT_OPTIMAL
	)

	clear_color := vk.ClearValue {
		color = vk.ClearColorValue {
			float32 = {0.0, 0.0, 0.0, 1.0},
		}
	}

	color_attachment_info := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = offscreen_images[current_frame].view,
		imageLayout = .ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = clear_color,
	}
	
	depth_clear_value := vk.ClearValue {
		depthStencil = vk.ClearDepthStencilValue {
			depth = 1.0,
			stencil = 0,
		},
	}

	depth_info := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = depth_images[current_frame].view,
		imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		resolveMode = {},
		resolveImageView = 0,
		resolveImageLayout = .UNDEFINED,
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
		clearValue = depth_clear_value,
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = vk.Rect2D {
			offset = vk.Offset2D {
				x = 0,
				y = 0,
			},
			extent = vk.Extent2D {
				width = SCREEN_WIDTH,
				height = SCREEN_HEIGHT,
			},
		},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment_info,
		pDepthAttachment = &depth_info,
	}
	
	// --- Begin dynamic rendering --------------------------------------------
	vk.CmdBeginRendering(command_buffer, &rendering_info)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, tile_pipeline.pipeline)

	offset := vk.DeviceSize{}

	vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vertex_buffer.buffer, &offset)

	vk.CmdBindIndexBuffer(command_buffer, index_buffer.buffer, 0, .UINT16)

	viewport := vk.Viewport {
		x = 0.0,
		y = 0.0,
		width = SCREEN_WIDTH,
		height = SCREEN_HEIGHT,
		minDepth = 0.0,
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = vk.Offset2D{0, 0},
		extent = vk.Extent2D{SCREEN_WIDTH, SCREEN_HEIGHT},
	}
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	
	// -- Render the tiles ----------------------------------------------------
	// Bind the descriptor set to update the uniform buffer
	vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, tile_pipeline.layout, 0, 1, &descriptor_sets[current_frame], 0, nil)
	
	// Create a model matrix for the tiles
	tile_model_matrix := glsl.identity(glsl.mat4)

	// Update the z-coordinate of the model matrix so that the tilemap is not
	// in front of everything else
	tile_translation: glsl.vec3 = {
		0.0,
		0.0,
		10.0,
	}
	tile_model_matrix = glsl.mat4Translate(tile_translation) * tile_model_matrix

	// Update push constants and copy in mvp matrix
	push_constants := PushConstants {
		mvp = projection_matrix * view_matrix * tile_model_matrix,
		// Set the texture index to 0
		texture_index = cast(u32) Texture.TEX_TILES,
		// Tiles always full white
		color = {1.0, 1.0, 1.0, 1.0},
	}

	vk.CmdPushConstants(command_buffer, tile_pipeline.layout, {.VERTEX, .FRAGMENT}, 0, size_of(PushConstants), &push_constants)

	// Draw the triangles for the tiles
	vk.CmdDrawIndexed(command_buffer, cast(u32) len(vertex_indices), 1, 0, 0, 0)
	
	// -- Render the sprites --------------------------------------------------
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, sprite_pipeline.pipeline)

	sprite_offset := vk.DeviceSize{}
	vk.CmdBindVertexBuffers(command_buffer, 0, 1, &sprite_vertex_buffer.buffer, &sprite_offset)

	vk.CmdDraw(command_buffer, NUM_MONSTERS * 6, 1, 0, 0)

	vk.CmdEndRendering(command_buffer)

	// Memory barrier to transition the offscreen image from shader read to color attachment
	vkx.transition_image_layout(
		command_buffer,
		offscreen_images[current_frame].image,
		vkx.swap_chain.image_format,
		.COLOR_ATTACHMENT_OPTIMAL,
		.SHADER_READ_ONLY_OPTIMAL,
	)

	// -- Render the screen ---------------------------------------------------
	// Update some parameters on the original structs
	viewport.width = cast(f32) vkx.swap_chain.extent.width
	viewport.height = cast(f32) vkx.swap_chain.extent.height
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)

	scissor.extent = vkx.swap_chain.extent
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	rendering_info.pDepthAttachment = nil
	color_attachment_info.imageView = vkx.swap_chain.image_views[image_index]
	rendering_info.renderArea.extent = vkx.swap_chain.extent
	
	// NOTE: an improvement we could make here would be to add a projection
	// matrix and feed it into the screen pipeline to ensure a consistent
	// aspect ratio (i.e. but black stripes down the sides of the screen).
	// This would probably involve adding the push constants to the screen
	// pipeline, or adding that projection matrix to the ubo.

	// Begin rendering again
	vk.CmdBeginRendering(command_buffer, &rendering_info)
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, screen_pipeline.pipeline)
	vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, screen_pipeline.layout, 0, 1, &screen_descriptor_sets[current_frame], 0, nil)
	vk.CmdDraw(command_buffer, 6, 1, 0, 0)

	// --- End dynamic rendering ----------------------------------------------
	vk.CmdEndRendering(command_buffer)
	
	// Memory barrier to transition the swap chain image from color attachment to present
	vkx.transition_image_layout(
		command_buffer,
		vkx.swap_chain.images[image_index],
		vkx.swap_chain.image_format,
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR
	)

	if vk.EndCommandBuffer(command_buffer) != .SUCCESS {
		fmt.eprint("failed to record command buffer!\n")
		os.exit(1)
	}
}

draw_frame :: proc() {
	vk.WaitForFences(vkx.instance.device, 1, &vkx.sync_objects.in_flight_fences[current_frame], true, c.UINT64_MAX);

	image_index: u32
	result := vk.AcquireNextImageKHR(
		device=vkx.instance.device,
		swapchain=vkx.swap_chain.swap_chain,
		timeout=c.UINT64_MAX,
		semaphore=vkx.sync_objects.image_available_semaphores[current_frame],
		fence={},
		pImageIndex=&image_index
	)

	if result == .ERROR_OUT_OF_DATE_KHR {
		fmt.printf("Couldn't acquire swap chain image - recreating swap chain\n")
		vkx.recreate_swap_chain()
		return

	} else if result != .SUCCESS && result != .SUBOPTIMAL_KHR {
		fmt.eprintf("Failed to acquire swap chain image (result: %d)\n", result)
		os.exit(1)
	}
	
	// Update all uniform buffers with transform data
	ubo := UniformBufferObject {
		t = f32(t)
	}
	
	// Update monster transforms
	for i := 0; i < NUM_MONSTERS; i += 1 {
		// TODO: check all of the matrix stuff in here!
		
		// Create a model matrix for the sprite
		model_matrix := glsl.identity(glsl.mat4)

		monster_size: f32 = 2.0
		// Centre the sprite around the origin
		offset: glsl.vec3 = {-monster_size / 4, -monster_size / 4, 0.0}
		model_matrix = glsl.mat4Translate(offset) * model_matrix
		
		// Scale the monster
		scale: glsl.vec3 = {monster_size, monster_size, 1.0}
		// Pulsating effect
		sin_val := math.sin(f32(t) * 2.0 + f32(i) * 5) * 0.15
		scale[0] *= (1 + sin_val)
		scale[1] *= (1 - sin_val)
		model_matrix = glsl.mat4Scale(scale) * model_matrix

		// Move it up and down relative to actual position
		translation: glsl.vec3 = {
			f32(monsters[i].pos[0]),
			f32(monsters[i].pos[1] + math.sin(t * 4.0 + f64(i) * 5) * 0.2),
			f32(monsters[i].pos[2])
		}
		model_matrix = glsl.mat4Translate(translation) * model_matrix

		// Apply model matrix to the UBO
		ubo.mvps[i] = projection_matrix * view_matrix * model_matrix
	}
	intrinsics.mem_copy(uniform_buffers_mapped[current_frame], &ubo, size_of(ubo))
	
	/*
	fmt.println("\nHEX DUMP:")
	bytes := slice.bytes_from_ptr(uniform_buffers_mapped[current_frame], size_of(ubo))
	for i := 0; i < 265; i += 1 {
		if i >= len(bytes) {
			fmt.printfln("Broke at %d", i)
			break
		}

		v := bytes[i]
		fmt.printf("%02X", v)

		if i % 16 == 15 {
			fmt.print("\n")
		} else if i % 4 == 3 {
			fmt.print(" ")
		}
	}
	fmt.print("\n")
	*/

	vk.ResetFences(vkx.instance.device, 1, &vkx.sync_objects.in_flight_fences[current_frame])

	vk.ResetCommandBuffer(vkx.instance.command_buffers[current_frame], {})
	
	// Write our draw commands into the command buffer
	record_command_buffer(vkx.instance.command_buffers[current_frame], image_index)

	wait_semaphore := &vkx.sync_objects.image_available_semaphores[current_frame]
	signal_semaphore := &vkx.sync_objects.render_finished_semaphores[current_frame]
	wait_stages: vk.PipelineStageFlags = {.COLOR_ATTACHMENT_OUTPUT}

	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		waitSemaphoreCount = 1,
		pWaitSemaphores = wait_semaphore,
		pWaitDstStageMask = &wait_stages,
		commandBufferCount = 1,
		pCommandBuffers = &vkx.instance.command_buffers[current_frame],
		signalSemaphoreCount = 1,
		pSignalSemaphores = signal_semaphore,
	}
	
	if vk.QueueSubmit(vkx.instance.graphics_queue, 1, &submit_info, vkx.sync_objects.in_flight_fences[current_frame]) != .SUCCESS {
		fmt.eprintfln("failed to submit draw command buffer!")
		os.exit(1)
	}

	present_info := vk.PresentInfoKHR {
		sType = .PRESENT_INFO_KHR,
		waitSemaphoreCount= 1,
		pWaitSemaphores = signal_semaphore,
		swapchainCount = 1,
		pSwapchains = &vkx.swap_chain.swap_chain,
		pImageIndices = &image_index,
	
	}

	result = vk.QueuePresentKHR(vkx.instance.present_queue, &present_info)
	if result == .SUBOPTIMAL_KHR {
		if suboptimal_swapchain_count == 0 {
			fmt.print("Swapchain was suboptimal\n")
		}
		suboptimal_swapchain_count += 1
	}
	else {
		// Reset to 0 if it doesn't come back like that every frame
		suboptimal_swapchain_count = 0
	}
	
	if framebuffer_resized {
		fmt.print("Framebuffer resized - recreating swap chain\n")
		framebuffer_resized = false
		vkx.recreate_swap_chain()
	}
	else if suboptimal_swapchain_count >= SUBOPTIMAL_SWAPCHAIN_THRESHOLD {
		suboptimal_swapchain_count = 0
		fmt.print("Swapchain is still suboptimal - recreating\n")
		vkx.recreate_swap_chain()
	}
	else if result == .ERROR_OUT_OF_DATE_KHR {
		fmt.printf("Couldn't present swap chain image - recreating swap chain (result: %d)\n", result)
		vkx.recreate_swap_chain()
	}
	else if result != .SUBOPTIMAL_KHR && result != .SUCCESS {
		fmt.eprintf("failed to present swap chain image! (result: %d)\n", result)
		os.exit(1)
	}

	current_frame = (current_frame + 1) % vkx.FRAMES_IN_FLIGHT
}

main :: proc() {
	fmt.println("Hello, Vulkan!\n")

	// Initialise SDL
	if !sdl.Init(sdl.INIT_VIDEO) {
		fmt.printf("SLD initialisation failed: %s\n", sdl.GetError())
	}

	// Create the window
	window_flags := sdl.WINDOW_VULKAN | sdl.WINDOW_HIDDEN | sdl.WINDOW_RESIZABLE
	window = sdl.CreateWindow("Vulkan", DEFAULT_WIDTH, DEFAULT_HEIGHT, window_flags)
    if (window == nil) {
		fmt.printf("Window creation failed: %s\n", sdl.GetError())
        sdl.Quit()
		os.exit(1)
    }

    sdl.SetWindowPosition(window, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED)
	fmt.println("SDL window created")

	// Don't let the window shrink
	sdl.SetWindowMinimumSize(window, SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2)

	// Create the tiles
	create_tiles()

	// Create the monsters
	create_monsters()
	
	// Initialise Vulkan
	init_vulkan()

	// Make the window visible
	sdl.ShowWindow(window)

	// Initialise matrices
	// At the moment there is no camera - just use the identity matrix for view
	view_matrix = glsl.identity(glsl.mat4)

	// Projection matrix
	// Orthographic projection with 0,0 in the bottom left hand corner, and each tile being 1x1
	// NOTE: z is inverted in OpenGL so we put -1.0f as the far plane
	// This seems to give values where 0 is closest and 20 is furthest away
	projection_matrix = glsl.mat4Ortho3d(0, X_TILES, Y_TILES, 0, 22, -22)
	
	// ----- Main loop -----

    running := true

    event: sdl.Event

    for running {
        // Poll for events
        for sdl.PollEvent(&event) == true {
            if event.type == sdl.EventType.QUIT {
                running = false
            } else if event.type == sdl.EventType.KEY_DOWN {
				if event.key.key == sdl.K_ESCAPE || event.key.key == sdl.K_Q {
					fmt.println("Quitting...")
					running = false
				}
				else if (event.key.key == sdl.K_F11) {
					// Toggle fullscreen
					fullscreen = !fullscreen
					sdl.SetWindowFullscreen(window, fullscreen)
					framebuffer_resized = true
				}
			}
        }
	
		ticks := sdl.GetTicksNS()
		t = f64(ticks) / f64(sdl.NS_PER_SECOND)
		dt: f64 = t - t_last

		if limit_fps && dt < min_frame_time {
			dt_ms := 1000.0 * dt
			sleep_time_f: f64 = 1000.0 * f64(min_frame_time) - dt_ms
			if (sleep_time_f <= 1) {
				sleep_time_f = 1
			}
			sleep_time := u32(sleep_time_f)
			sdl.Delay(sleep_time)
			ticks = sdl.GetTicksNS()
			t: f64 = f64(ticks) / f64(sdl.NS_PER_SECOND)
			dt = t - t_last

		} else if dt > 0.1 {
			// Clamp the delta time to 0.1 seconds
			dt = 0.1
		}
		
		update(dt)

		draw_frame()

		t_last = t

		// Clean up temporary allocator
		free_all(context.temp_allocator)
		
    }

	/*
	vkDeviceWaitIdle(vkx_instance.device);
	
	cleanup_vulkan();
	*/

	// Cleanup SDL
	fmt.println("Cleaning up SDL")
    sdl.DestroyWindow(window)
    sdl.Quit()
	
	fmt.println("Goodbye Vulkan!")

	// Print the build time
	compile_time := time.Time{ODIN_COMPILE_TIMESTAMP}
	date_buf : [time.MIN_YYYY_DATE_LEN]u8
	time_buf : [time.MIN_HMS_LEN]u8

	fmt.printf(
		"Built: %s %s\n",
		time.to_string_yyyy_mm_dd(compile_time, date_buf[:]),
		time.to_string_hms(compile_time, time_buf[:])
	)
}
