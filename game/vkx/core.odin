// Core shared code used throughout the VKX package
package vkx

import "base:intrinsics"
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

Pipeline :: struct {
	descriptor_set_layout: vk.DescriptorSetLayout,
	layout: vk.PipelineLayout,
	pipeline: vk.Pipeline,
}

// Buffer and associated memory
Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
}

// Compile time flags
ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)

// The number of validation layers that are enabled
NUM_VALIDATION_LAYERS :: 1 when ENABLE_VALIDATION_LAYERS else 0
// The set of validation layers, for when they are enabled
VALIDATION_LAYERS :: [1]cstring{"VK_LAYER_KHRONOS_validation"}

// Constants

DEVICE_EXTENSIONS :: [2]cstring{
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
 
 	return image_view
}

find_supported_format :: proc(candidates: []vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format {
	/* 
	 * Search through the list of candidates and find a supported format.
	 *
	 * @param candidates The list of candidate formats to search through
	 * @param candidates_count The number of candidate formats
	 * @param tiling The image tiling to use (linear or optimal)
	 * @param features The format features to check for
	 *
	 * Used to find the format of the depth buffer from the tutorial at:
	 * https://vulkan-tutorial.com/Depth_buffer
	 */
	for candidate in candidates {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(instance.physical_device, candidate, &props)
		
		if tiling == .LINEAR && props.linearTilingFeatures >= features {
			return candidate
		}

		if tiling == .OPTIMAL && props.optimalTilingFeatures >= features {
			return candidate
		}
	}

	fmt.eprintln("Failed to find supported format")
	os.exit(1)
}

find_depth_format :: proc() -> vk.Format {
	/*
	 * Find a supported depth format
	 */
	candidates := []vk.Format {
		.D32_SFLOAT,
		.D32_SFLOAT_S8_UINT,
		.D24_UNORM_S8_UINT,
	}
	
	return find_supported_format(candidates, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
}

find_memory_type :: proc(type_filter: u32, properties: vk.MemoryPropertyFlags) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(instance.physical_device, &mem_properties)

	for i: u32 = 0; i < mem_properties.memoryTypeCount; i += 1 {
		if ((type_filter & (1 << i)) != 0) \
				&& (mem_properties.memoryTypes[i].propertyFlags >= properties) {
			return i
		}
	}
	
	fmt.eprintln("Failed to find suitable memory type!")
	os.exit(1)
}

/*
 * Begin a one-time command buffer
 */
begin_single_time_commands :: proc() -> vk.CommandBuffer {
	alloc_info := vk.CommandBufferAllocateInfo{
		sType = .COMMAND_BUFFER_ALLOCATE_INFO,
		level = .PRIMARY,
		commandPool = instance.command_pool,
		commandBufferCount = 1,
	}

	command_buffer: vk.CommandBuffer
	vk.AllocateCommandBuffers(instance.device, &alloc_info, &command_buffer)

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}

	vk.BeginCommandBuffer(command_buffer, &begin_info)

	return command_buffer
}

/*
 * End a one-time command buffer
 */
end_single_time_commands :: proc (command_buffer: vk.CommandBuffer) {
	// Need address so put in local variable
	command_buffer := command_buffer

	if vk.EndCommandBuffer(command_buffer) != .SUCCESS {
		fmt.eprintln("failed to record command buffer!")
		os.exit(1)
	}
	
	submit_info := vk.SubmitInfo {
		sType = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &command_buffer,
	}

	vk.QueueSubmit(instance.graphics_queue, 1, &submit_info, 0)
	vk.QueueWaitIdle(instance.graphics_queue)
	
	vk.FreeCommandBuffers(instance.device, instance.command_pool, 1, &command_buffer)
}
/*
 * Copy buffers - used to copy from staging buffer into vertext buffer
 */
copy_buffer :: proc(src_buffer: vk.Buffer, dst_buffer: vk.Buffer, size: vk.DeviceSize) {
	command_buffer := begin_single_time_commands()
	
	copy_region := vk.BufferCopy{
		size = size,
	}
	vk.CmdCopyBuffer(command_buffer, src_buffer, dst_buffer, 1, &copy_region)

	end_single_time_commands(command_buffer)
}

create_buffer :: proc(
		size: vk.DeviceSize,
		usage: vk.BufferUsageFlags,
		properties: vk.MemoryPropertyFlags,
) -> Buffer {
	buffer: Buffer
	
	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = size,
		usage = usage,
		sharingMode = .EXCLUSIVE,
	}

	if vk.CreateBuffer(instance.device, &buffer_info, nil, &buffer.buffer) != .SUCCESS {
		fmt.eprintln("Failed to create buffer")
		os.exit(1)
	}
	
	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(instance.device, buffer.buffer, &mem_requirements)
	
	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_requirements.size,
		memoryTypeIndex = find_memory_type(mem_requirements.memoryTypeBits, properties),
	}

	if vk.AllocateMemory(instance.device, &alloc_info, nil, &buffer.memory) != .SUCCESS {
		fmt.eprintln("Failed to allocate buffer memory")
		os.exit(1)
	}

	vk.BindBufferMemory(instance.device, buffer.buffer, buffer.memory, 0)

	return buffer
}

cleanup_buffer :: proc(buffer: ^Buffer) {
	vk.DestroyBuffer(instance.device, buffer.buffer, nil)
	vk.FreeMemory(instance.device, buffer.memory, nil)

	buffer.buffer = 0
	buffer.memory = 0
}

/*
 * Create a vertex buffer from the given vertices
 *
 * @param vertices The array of vertex data to create the buffer from
 * @param buffer_size The size of the vertex data (i.e. sizeof(vertices[0]) * vertices_count)
 * @param usage_flags The usage flags for the buffer (TRANSFER_DST_BIT is automatically added)
 */
create_and_populate_buffer :: proc(
		vertices: rawptr,
		buffer_size: vk.DeviceSize,
		usage_flags: vk.BufferUsageFlags
) -> Buffer {
	// We should probably add a flag to decide if the buffer should be host coherent
	// (and not use a staging buffer)
	staging_buffer := create_buffer(
		buffer_size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	data: rawptr
	vk.MapMemory(instance.device, staging_buffer.memory, 0, buffer_size, {}, &data)
	intrinsics.mem_copy(data, vertices, buffer_size)
	vk.UnmapMemory(instance.device, staging_buffer.memory)

	buffer := create_buffer(
		buffer_size,
		usage_flags | {.TRANSFER_DST},
		{.DEVICE_LOCAL},
	)

	// Copy the staging buffer into the vertex buffer
	copy_buffer(staging_buffer.buffer, buffer.buffer, buffer_size)
	
	cleanup_buffer(&staging_buffer)

	return buffer
}

