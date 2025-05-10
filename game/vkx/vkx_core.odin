// Core shared code used throughout the VKX package
package vkx

import "core:fmt"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"

// Compile time flags
ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)

// The number of validation layers that are enabled
NUM_VALIDATION_LAYERS :: 1 when ENABLE_VALIDATION_LAYERS else 0
// The set of validation layers, for when they are enabled
VALIDATION_LAYERS :: cast([1]cstring) {"VK_LAYER_KHRONOS_validation"}

// Main VKX Instance struct
Instance :: struct {
	// Vulkan instance
	instance: vk.Instance,

	// Vulkan debug messenger
	debug_messenger: vk.DebugUtilsMessengerEXT,

	// SDL window that we are rendering to
	window: ^sdl.Window,

	// Surface from the SDL window
	surface: vk.SurfaceKHR,

	// Physical device that we are using
	physical_device: vk.PhysicalDevice,

	// Logical device that we are using
	device: vk.Device,

	// Graphics queue
	graphics_queue: vk.Queue,

	// Presentation queue
	present_queue: vk.Queue,

	// Single command pool for the program
	command_pool: vk.CommandPool,

	// Command buffers for each frame in flight
	command_buffers: [dynamic]vk.CommandBuffer,
}

// Main global instance
instance: Instance
