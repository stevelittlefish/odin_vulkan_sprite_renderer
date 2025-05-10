package game

import "core:fmt"
import "core:os"
import "core:time"
import "core:math/rand"
import sdl "vendor:sdl3"

import "vkx"

// Simple vector types
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

// Struct for vertex based geometry (i.e. the tiles)
Vertex :: struct {
	pos: Vec3,
	tex_coord: Vec2,
}

// This struct stores a sprite in a vertex array
VertexBufferSprite :: struct {
	// RGBA colour for rendering
	color: Vec4,
	// Texture coordinates
	uv: Vec2,
	uv2: Vec2,
	// Texture index
	texture_index: u32,
	// Index into arrays in ubo
	sprite_index: u32,
}

// Monster struct for game logic
Monster :: struct {
	pos: Vec3,
	spd: Vec2,
	color: Vec4,
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

// SDL Window handle
window: ^sdl.Window = nil

// Tile data - which visual tile to display (or EMPTY)
tiles: [TOTAL_TILES]u8

// Vertices for the tilemap geometry
vertices: [dynamic]Vertex

// Indices for the tilemap geometry
vertex_indices: [dynamic]u16

// "Vertices" for the sprites
vertex_sprites: [dynamic]VertexBufferSprite

// Monster data
monsters: [NUM_MONSTERS]Monster

/*
 * Return the index of the tile at (x, y)
 */
get_tile_index :: proc(x, y: int) -> int {
	return x + y * X_TILES;
}

create_tiles :: proc() {
	// The number of occupied tiles
	num_tiles := 0

	// Generate a random set of tiles
	// TODO: is this necessary?
	// srand(time(NULL));
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
		monsters[i].pos[0] = rand.float32_range(0, X_TILES)
		monsters[i].pos[1] = rand.float32_range(0, Y_TILES)
		// Half of the monsters will be in front of the tiles and half
		// will be behind
		monsters[i].pos[2] = rand.float32_range(1, 19)

		monsters[i].spd[0] = rand.float32_range(-5, 5)
		monsters[i].spd[1] = rand.float32_range(-5, 5)
		
		// Fade to blue as the monsters z coord puts them in the background
		blue_fade := monsters[i].pos[2] / 20.0
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

	/*
	// ----- Create the swap chain -----
	vkx_create_swap_chain(false);
	
	// ----- Create the graphics pipeline -----
	// Vertex input bindng and attributes
	VkVertexInputBindingDescription binding_description = get_binding_description();
	size_t attribute_descriptions_count = 0;
	VkVertexInputAttributeDescription* attribute_descriptions = get_attribute_descriptions(&attribute_descriptions_count);

	// Push constants for pushing matrices etc.
	VkPushConstantRange push_constant_range = {0};
	push_constant_range.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
	push_constant_range.offset = 0;
	push_constant_range.size = sizeof(PushConstants);

	tile_pipeline = vkx_create_vertex_buffer_pipeline(
		"shaders/tiles.vert.spv",
		"shaders/tiles.frag.spv",
		binding_description,
		attribute_descriptions,
		attribute_descriptions_count,
		push_constant_range,
		num_textures
	);
	
	// Create the sprite pipeline
	// Vertex input binding and attributes
	VkVertexInputBindingDescription sprite_binding_description = get_sprite_binding_description();
	size_t sprite_attribute_descriptions_count = 0;
	VkVertexInputAttributeDescription* sprite_attribute_descriptions = get_sprite_attribute_descriptions(&sprite_attribute_descriptions_count);

	// Push constants are the same (actually not used by the sprite shaders)
	sprite_pipeline = vkx_create_vertex_buffer_pipeline(
		"shaders/sprite.vert.spv",
		"shaders/sprite.frag.spv",
		sprite_binding_description,
		sprite_attribute_descriptions,
		sprite_attribute_descriptions_count,
		push_constant_range,
		num_textures
	);

	// Screen pipeline is simple and has no vertex input
	screen_pipeline = vkx_create_screen_pipeline(
		"shaders/screen.vert.spv",
		"shaders/screen.frag.spv"
	);

	free(sprite_attribute_descriptions);
	free(attribute_descriptions);

	
	// ----- Create the buffers -----
	// Vertex buffer
	vertex_buffer = vkx_create_and_populate_buffer(
			vertices, sizeof(vertices[0]) * vertices_count,
			VK_BUFFER_USAGE_VERTEX_BUFFER_BIT
	);
	// Index buffer
	index_buffer = vkx_create_and_populate_buffer(
			vertex_indices, sizeof(vertex_indices[0]) * vertex_indices_count,
			VK_BUFFER_USAGE_INDEX_BUFFER_BIT
	);
	// Sprite vertex buffer
	sprite_vertex_buffer = vkx_create_and_populate_buffer(
			vertex_sprites, sizeof(vertex_sprites[0]) * vertex_sprites_count,
			VK_BUFFER_USAGE_VERTEX_BUFFER_BIT
	);

	// ----- Load the texture images -----
	textures = malloc(sizeof(VkxImage) * num_textures);
	textures[0] = vkx_create_texture_image("textures/tiles.png");
	textures[1] = vkx_create_texture_image("textures/monsters1.png");
	textures[2] = vkx_create_texture_image("textures/monsters2.png");
	textures[3] = vkx_create_texture_image("textures/monsters3.png");
	textures[4] = vkx_create_texture_image("textures/monsters4.png");
	
	// Create the texture sampler
	create_texture_sampler();

	// ----- Create the uniform buffer -----
	VkDeviceSize uniform_buffer_size = sizeof(UniformBufferObject);

	if (uniform_buffer_size > 65536) {
		fprintf(stderr, "Tried to allocate a buffer with %zu bytes, which is greater than the maximum (65536)", uniform_buffer_size);
		exit(1);
	}

	for (size_t i = 0; i < VKX_FRAMES_IN_FLIGHT; i++) {
		uniform_buffers[i] = vkx_create_buffer(
			uniform_buffer_size,
			VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
			VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
		);

		// Map the buffer memory and copy the vertex data into it
		vkMapMemory(vkx_instance.device, uniform_buffers[i].memory, 0, uniform_buffer_size, 0, &uniform_buffers_mapped[i]);
	}

	// ----- Create the offscreen images -----
	VkFormat depth_format = vkx_find_depth_format();

	for (size_t i=0; i<VKX_FRAMES_IN_FLIGHT; i++) {
		offscreen_images[i] = vkx_create_image(
			SCREEN_WIDTH,
			SCREEN_HEIGHT,
			vkx_swap_chain.image_format,
			VK_IMAGE_TILING_OPTIMAL,
			VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
			VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
		);

		offscreen_images[i].view = vkx_create_image_view(
			offscreen_images[i].image,
			vkx_swap_chain.image_format,
			VK_IMAGE_ASPECT_COLOR_BIT
		);

		// transition the image layout to color attachment optimal
		vkx_transition_image_layout_tmp_buffer(
			offscreen_images[i].image,
			vkx_swap_chain.image_format,
			VK_IMAGE_LAYOUT_UNDEFINED,
			VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
		);

		// And depth images too
		depth_images[i] = vkx_create_image(
			SCREEN_WIDTH,
			SCREEN_HEIGHT,
			depth_format,
			VK_IMAGE_TILING_OPTIMAL,
			VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
			VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
		);

		depth_images[i].view = vkx_create_image_view(depth_images[i].image, depth_format, VK_IMAGE_ASPECT_DEPTH_BIT);

		// Transition the image layout to depth stencil attachment
		vkx_transition_image_layout_tmp_buffer(
			depth_images[i].image, depth_format,
			VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL
		);
	}

	// ----- Create the descriptor pool -----
	VkDescriptorPoolSize desc_pool_sizes[2] = {0};
	desc_pool_sizes[0].type = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
	desc_pool_sizes[0].descriptorCount = VKX_FRAMES_IN_FLIGHT * 2;
	desc_pool_sizes[1].type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
	desc_pool_sizes[1].descriptorCount = VKX_FRAMES_IN_FLIGHT * num_textures + VKX_FRAMES_IN_FLIGHT;

	VkDescriptorPoolCreateInfo desc_pool_info = {0};
	desc_pool_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
	desc_pool_info.poolSizeCount = 2;
	desc_pool_info.pPoolSizes = desc_pool_sizes;
	desc_pool_info.maxSets = VKX_FRAMES_IN_FLIGHT * 2;

	if (vkCreateDescriptorPool(vkx_instance.device, &desc_pool_info, NULL, &descriptor_pool) != VK_SUCCESS) {
		fprintf(stderr, "failed to create descriptor pool!\n");
		exit(1);
	}
	
	{
		// ----- Create the descriptor sets -----
		VkDescriptorSetLayout ds_layouts[VKX_FRAMES_IN_FLIGHT] = {0};
		for (size_t i = 0; i < VKX_FRAMES_IN_FLIGHT; i++) {
			ds_layouts[i] = tile_pipeline.descriptor_set_layout;
		}

		VkDescriptorSetAllocateInfo ds_alloc_info = {0};
		ds_alloc_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
		ds_alloc_info.descriptorPool = descriptor_pool;
		ds_alloc_info.descriptorSetCount = VKX_FRAMES_IN_FLIGHT;
		ds_alloc_info.pSetLayouts = ds_layouts;
		
		// Create the base descriptor sets
		if (vkAllocateDescriptorSets(vkx_instance.device, &ds_alloc_info, descriptor_sets) != VK_SUCCESS) {
			fprintf(stderr, "failed to allocate descriptor sets!\n");
			exit(1);
		}

		for (size_t i = 0; i < VKX_FRAMES_IN_FLIGHT; i++) {
			VkDescriptorBufferInfo buffer_info = {0};
			buffer_info.buffer = uniform_buffers[i].buffer;
			buffer_info.offset = 0;
			buffer_info.range = sizeof(UniformBufferObject);

			VkDescriptorImageInfo* image_infos = malloc(sizeof(VkDescriptorImageInfo) * num_textures);

			for (size_t j = 0; j < num_textures; j++) {
				image_infos[j].imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
				image_infos[j].imageView = textures[j].view;
				image_infos[j].sampler = texture_sampler;
			}

			VkWriteDescriptorSet descriptor_writes[2] = {0};
			descriptor_writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
			descriptor_writes[0].dstSet = descriptor_sets[i];
			descriptor_writes[0].dstBinding = 0;
			descriptor_writes[0].dstArrayElement = 0;
			descriptor_writes[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
			descriptor_writes[0].descriptorCount = 1;
			descriptor_writes[0].pBufferInfo = &buffer_info;
			descriptor_writes[0].pImageInfo = NULL;
			descriptor_writes[0].pTexelBufferView = NULL;

			descriptor_writes[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
			descriptor_writes[1].dstSet = descriptor_sets[i];
			descriptor_writes[1].dstBinding = 1;
			descriptor_writes[1].dstArrayElement = 0;
			descriptor_writes[1].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
			descriptor_writes[1].descriptorCount = num_textures;
			descriptor_writes[1].pBufferInfo = NULL;
			descriptor_writes[1].pImageInfo = image_infos;
			descriptor_writes[1].pTexelBufferView = NULL;

			vkUpdateDescriptorSets(vkx_instance.device, 2, descriptor_writes, 0, NULL);

			free(image_infos);
		}
	}
	{
		// ----- Create the screen descriptor sets -----
		VkDescriptorSetLayout ds_layouts[VKX_FRAMES_IN_FLIGHT] = {0};
		for (size_t i = 0; i < VKX_FRAMES_IN_FLIGHT; i++) {
			ds_layouts[i] = screen_pipeline.descriptor_set_layout;
		}

		VkDescriptorSetAllocateInfo ds_alloc_info = {0};
		ds_alloc_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
		ds_alloc_info.descriptorPool = descriptor_pool;
		ds_alloc_info.descriptorSetCount = VKX_FRAMES_IN_FLIGHT;
		ds_alloc_info.pSetLayouts = ds_layouts;
		
		// Create the base descriptor sets
		if (vkAllocateDescriptorSets(vkx_instance.device, &ds_alloc_info, screen_descriptor_sets) != VK_SUCCESS) {
			fprintf(stderr, "failed to allocate screen descriptor sets!\n");
			exit(1);
		}

		for (size_t i = 0; i < VKX_FRAMES_IN_FLIGHT; i++) {
			VkDescriptorBufferInfo buffer_info = {0};
			buffer_info.buffer = uniform_buffers[i].buffer;
			buffer_info.offset = 0;
			buffer_info.range = sizeof(UniformBufferObject);

			VkDescriptorImageInfo image_info = {0};

			image_info.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
			image_info.imageView = offscreen_images[i].view;
			image_info.sampler = texture_sampler;

			VkWriteDescriptorSet descriptor_writes[2] = {0};
			descriptor_writes[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
			descriptor_writes[0].dstSet = screen_descriptor_sets[i];
			descriptor_writes[0].dstBinding = 0;
			descriptor_writes[0].dstArrayElement = 0;
			descriptor_writes[0].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
			descriptor_writes[0].descriptorCount = 1;
			descriptor_writes[0].pBufferInfo = &buffer_info;
			descriptor_writes[0].pImageInfo = NULL;
			descriptor_writes[0].pTexelBufferView = NULL;

			descriptor_writes[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
			descriptor_writes[1].dstSet = screen_descriptor_sets[i];
			descriptor_writes[1].dstBinding = 1;
			descriptor_writes[1].dstArrayElement = 0;
			descriptor_writes[1].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
			descriptor_writes[1].descriptorCount = 1;
			descriptor_writes[1].pBufferInfo = NULL;
			descriptor_writes[1].pImageInfo = &image_info;
			descriptor_writes[1].pTexelBufferView = NULL;

			vkUpdateDescriptorSets(vkx_instance.device, 2, descriptor_writes, 0, NULL);
		}
	}

	// ----- Create the semaphores and fences -----
	vkx_init_sync_objects();

	printf("Initiialisation complete\n");
	*/
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
	init_vulkan();
	
	/*
	// Make the window visible
	SDL_ShowWindow(window);

	// Initialise matrices
	// At the moment there is no camera - just use the identity matrix for view
	glm_mat4_identity(view_matrix);

	// Projection matrix
	// Orthographic projection with 0,0 in the bottom left hand corner, and each tile being 1x1
	// NOTE: z is inverted in OpenGL so we put -1.0f as the far plane
	// This seems to give values where 0 is closest and 20 is furthest away
	glm_ortho(0.0f, (float) X_TILES, (float) Y_TILES, 0.0f, 22.0f, -22.0f, projection_matrix);
	
	// ----- Main loop -----

    bool running = true;
    SDL_Event event;
    while (running) {
        // Poll for events
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) {
                running = false;
            }
			else if (event.type == SDL_EVENT_KEY_DOWN) {
				if (event.key.key == SDLK_ESCAPE || event.key.key == SDLK_Q) {
					printf("Quitting...\n");
					running = false;
				}
				else if (event.key.key == SDLK_F11) {
					// Toggle fullscreen
					if (fullscreen) {
						SDL_SetWindowFullscreen(window, 0);
						fullscreen = false;
					}
					else {
						SDL_SetWindowFullscreen(window, SDL_WINDOW_FULLSCREEN);
						fullscreen = true;
					}
					framebuffer_resized = true;
				}
			}
        }

		uint64_t ticks = SDL_GetTicksNS();
		t = SDL_NS_TO_SECONDS((double) ticks);
		double dt = t - t_last;

		if (limit_fps && dt < min_frame_time) {
			int dt_ms = (int) (1000.0 * dt);
			int sleep_time = (int) (1000.0 * min_frame_time) - dt_ms;
			if (sleep_time <= 0) {
				sleep_time = 1;
			}
			SDL_Delay(sleep_time);
			ticks = SDL_GetTicksNS();
			t = SDL_NS_TO_SECONDS((double) ticks);
			dt = t - t_last;
		}
		else if (dt > 0.1) {
			// Clamp the delta time to 0.1 seconds
			dt = 0.1;
		}

		update(dt);

		draw_frame();

		t_last = t;
    }

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
