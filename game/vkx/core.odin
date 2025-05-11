// Core shared code used throughout the VKX package
package vkx

import "core:fmt"
import "core:os"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"

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
	command_buffers: []vk.CommandBuffer,
}

SwapChain :: struct {
	// Vulkan swap chain
	swap_chain: vk.SwapchainKHR,
	// Array of swap chain images
	images: []vk.Image,
	// Array of swap chain image views
	image_views: []vk.ImageView,
	// Image format of all images in the swapchain
	image_format: vk.Format,
	// Size of the swap chain images
	extent: vk.Extent2D,
}

QueueFamilyIndices :: struct {
	graphics_family: u32,
	present_family: u32,
	has_graphics_family: bool,
	has_present_family: bool,
}

SwapChainSupportDetails :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	// uint32_t formats_count;
	// uint32_t present_modes_count;
	formats: []vk.SurfaceFormatKHR,
	present_modes: []vk.PresentModeKHR,
}

// Compile time flags
ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)

// The number of validation layers that are enabled
NUM_VALIDATION_LAYERS :: 1 when ENABLE_VALIDATION_LAYERS else 0
// The set of validation layers, for when they are enabled
VALIDATION_LAYERS :: cast([1]cstring) {"VK_LAYER_KHRONOS_validation"}

// Constants

DEVICE_EXTENSIONS :: cast([2]cstring) {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME
}

FRAMES_IN_FLIGHT :: 2

// Main global instance
instance: Instance

// Global swap chain
swap_chain: SwapChain


find_queue_families :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> QueueFamilyIndices {
	indices := QueueFamilyIndices{}

	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)
	queue_families := make([]vk.QueueFamilyProperties, queue_family_count, context.temp_allocator)

	vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(queue_families))

	for i := 0; i < int(queue_family_count); i += 1 {
		if (vk.QueueFlag.GRAPHICS in queue_families[i].queueFlags) {
			indices.graphics_family = u32(i)
			indices.has_graphics_family = true
		}
		
		present_support: b32 = false
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &present_support)

		if (present_support) {
			indices.present_family = u32(i)
			indices.has_present_family = true
		}

		if (indices.has_graphics_family && indices.has_present_family) {
			break
		}
	}

	return indices
}

query_swap_chain_support :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> SwapChainSupportDetails {
	details := SwapChainSupportDetails{}

	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &details.capabilities)
	
	formats_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formats_count, nil)
	details.formats = make([]vk.SurfaceFormatKHR, formats_count)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &formats_count, raw_data(details.formats))
	
	present_modes_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_modes_count, nil)
	details.present_modes = make([]vk.PresentModeKHR, formats_count)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &present_modes_count, raw_data(details.present_modes))
	
	return details
}

cleanup_swap_chain_support :: proc(swap_chain_support: ^SwapChainSupportDetails) {
	delete(swap_chain_support.present_modes)
	delete(swap_chain_support.formats)
}

create_image_view :: proc(
		image: vk.Image, format: vk.Format, aspect_flags: vk.ImageAspectFlags
) -> vk.ImageView {
	view_info := vk.ImageViewCreateInfo {
		sType = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = vk.ImageViewType.D2,
		format = format,
		components = vk.ComponentMapping {
			r = vk.ComponentSwizzle.IDENTITY,
			g = vk.ComponentSwizzle.IDENTITY,
			b = vk.ComponentSwizzle.IDENTITY,
			a = vk.ComponentSwizzle.IDENTITY,
		},
		subresourceRange = vk.ImageSubresourceRange{
			aspectMask = aspect_flags,
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}
	
	image_view: vk.ImageView
 	if vk.CreateImageView(instance.device, &view_info, nil, &image_view) != .SUCCESS {
 		fmt.fprintln(os.stderr, "failed to create image view!\n")
 		os.exit(1)
 	}
 
 	return image_view;
}
