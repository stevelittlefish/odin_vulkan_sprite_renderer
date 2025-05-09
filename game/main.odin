package game

import "core:fmt"
import "core:os"
import "core:time"
import "core:math/rand"
import sdl "vendor:sdl3"

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

window: ^sdl.Window = nil

tiles: [TOTAL_TILES]u8

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
	
	/*
	// Generate the mesh for the tilemap
	
	// First let's allocate some memory for the vertices and indices
	// We need 4 vertices per tile, and 6 indices per tile
	vertices_count = num_tiles * 4;
	vertices = malloc(sizeof(Vertex) * vertices_count);
	vertex_indices_count = num_tiles * 6;
	vertex_indices = malloc(sizeof(uint16_t) * vertex_indices_count);

	// Loop through and add the geometry for each tile
	size_t vertex_idx = 0;
	size_t index_idx = 0;

	for (size_t x = 0; x < X_TILES; x++) {
		for (size_t y = 0; y < Y_TILES; y++) {
			size_t idx = get_tile_index(x, y);
			if (tiles[idx] == EMPTY) {
				continue;
			}

			// We need to calculate the grid coords of the texture tile
			size_t tileset_idx = tiles[idx];
			size_t tileset_x = tileset_idx % TILESET_X_TILES;
			size_t tileset_y = tileset_idx / TILESET_X_TILES;

			// Tiles are 1x1, so we can just use the x and y coordinates as the vertex positions
			// We can leave all z coordinates as 0.0f. We'll update colours later
			
			// Bottom left
			vertices[vertex_idx].pos[0] = (float) x;
			vertices[vertex_idx].pos[1] = (float) y;
			vertices[vertex_idx].tex_coord[0] = (float) tileset_x / TILESET_X_TILES;
			vertices[vertex_idx].tex_coord[1] = (float) tileset_y / TILESET_Y_TILES + 1.0f / TILESET_Y_TILES;
			vertex_idx++;

			// Bottom right
			vertices[vertex_idx].pos[0] = (float) x + 1.0f;
			vertices[vertex_idx].pos[1] = (float) y;
			vertices[vertex_idx].tex_coord[0] = (float) tileset_x / TILESET_X_TILES + 1.0f / TILESET_X_TILES;
			vertices[vertex_idx].tex_coord[1] = (float) tileset_y / TILESET_Y_TILES + 1.0f / TILESET_Y_TILES;
			vertex_idx++;

			// Top right
			vertices[vertex_idx].pos[0] = (float) x + 1.0f;
			vertices[vertex_idx].pos[1] = (float) y + 1.0f;
			vertices[vertex_idx].tex_coord[0] = (float) tileset_x / TILESET_X_TILES + 1.0f / TILESET_X_TILES;
			vertices[vertex_idx].tex_coord[1] = (float) tileset_y / TILESET_Y_TILES;
			vertex_idx++;

			// Top left
			vertices[vertex_idx].pos[0] = (float) x;
			vertices[vertex_idx].pos[1] = (float) y + 1.0f;
			vertices[vertex_idx].tex_coord[0] = (float) tileset_x / TILESET_X_TILES;
			vertices[vertex_idx].tex_coord[1] = (float) tileset_y / TILESET_Y_TILES;
			vertex_idx++;

			// Now we need to add the indices for this tile
			vertex_indices[index_idx++] = vertex_idx - 4; // Bottom left
			vertex_indices[index_idx++] = vertex_idx - 3; // Bottom right
			vertex_indices[index_idx++] = vertex_idx - 2; // Top right
			vertex_indices[index_idx++] = vertex_idx - 2; // Top right
			vertex_indices[index_idx++] = vertex_idx - 1; // Top left
			vertex_indices[index_idx++] = vertex_idx - 4; // Bottom left
		}
	}

	// Loop through all vertices now and set z coord
	for (size_t i = 0; i < vertices_count; i++) {
		vertices[i].pos[2] = 0.0f;
	}
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
	fmt.println("SDL window created");

	// Don't let the window shrink
	sdl.SetWindowMinimumSize(window, SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2)

	// Create the tiles
	create_tiles();

	/*
	// Create the monsters
	create_monsters();

	// Initialise Vulkan
	init_vulkan();
	
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
