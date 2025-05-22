// Core shared code used throughout the VKX package
package vkx

import "base:intrinsics"
import "core:fmt"
import "core:os"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

// Main VKX Instance struct
VkxInstance :: struct {
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
	// Graphics queue family index
	graphics_family: u32,
	// Presentation queue
	present_queue: vk.Queue,
	// Present queue family index
	present_family: u32,
	// Number of frames in flight
	frames_in_flight: u32,
	// Swap chain related data
	swap_chain: SwapChain,
	// Single command pool for the program
	command_pool: vk.CommandPool,
	// Command buffers for each frame in flight
	command_buffers: []vk.CommandBuffer,
	// Semaphores and fence for each frame
	frame_sync_objects: []FrameSyncObjects,
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
	// Semaphore for each swapchain image
	render_finished_semaphores: []vk.Semaphore,
}

QueueFamilyIndices :: struct {
	graphics_family: u32,
	present_family: u32,
	has_graphics_family: bool,
	has_present_family: bool,
}

SwapChainSupportDetails :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
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

// An image with corresponding view and memory
Image :: struct {
	image: vk.Image,
	memory: vk.DeviceMemory,
	view: vk.ImageView,
}

FrameSyncObjects :: struct {
	image_available_semaphore: vk.Semaphore,
	in_flight_fence: vk.Fence,
} 


// Compile time flags
ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, false)

// The number of validation layers that are enabled
NUM_VALIDATION_LAYERS :: 1 when ENABLE_VALIDATION_LAYERS else 0
// The set of validation layers, for when they are enabled
VALIDATION_LAYERS: [1]cstring : {"VK_LAYER_KHRONOS_validation"}

// Constants

DEVICE_EXTENSIONS: [2]cstring : {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	vk.EXT_DESCRIPTOR_INDEXING_EXTENSION_NAME,
}

// Global state:
instance: VkxInstance


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
		image: vk.Image, format: vk.Format, aspect_flags: vk.ImageAspectFlags,
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
 * Check if the format has a stencil component
 */
has_stencil_component :: proc(format: vk.Format) -> bool {
	#partial switch (format) {
		case .D32_SFLOAT_S8_UINT:
		case .D24_UNORM_S8_UINT:
			return true
	}

	return false
}

transition_image_layout :: proc(
		command_buffer: vk.CommandBuffer, image: vk.Image, format: vk.Format,
		old_layout: vk.ImageLayout, new_layout: vk.ImageLayout,
) {
	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = vk.ImageSubresourceRange {
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}

	if new_layout == vk.ImageLayout.DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		if has_stencil_component(format) {
			barrier.subresourceRange.aspectMask = {.DEPTH, .STENCIL}
		} else {
			barrier.subresourceRange.aspectMask = {.DEPTH}
		}
	} else {
		barrier.subresourceRange.aspectMask = {.COLOR}
	}

	if (old_layout == .UNDEFINED
			&& new_layout == .TRANSFER_DST_OPTIMAL) {
		barrier.srcStageMask = {.TOP_OF_PIPE}
		barrier.srcAccessMask = {}
		barrier.dstStageMask = {.TRANSFER}
		barrier.dstAccessMask = {.TRANSFER_WRITE}
	} else if (old_layout == .UNDEFINED
			&& new_layout == .SHADER_READ_ONLY_OPTIMAL) {
		barrier.srcStageMask = {.TOP_OF_PIPE}
		barrier.srcAccessMask = {}
		barrier.dstStageMask = {.TRANSFER}
		barrier.dstAccessMask = {.TRANSFER_WRITE}
	} else if (old_layout == .UNDEFINED
		   	&& new_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL) {
		barrier.srcAccessMask = {}
		barrier.srcStageMask = {.TOP_OF_PIPE}
		barrier.dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE}
		barrier.dstStageMask = {.EARLY_FRAGMENT_TESTS}
	} else if (old_layout == .TRANSFER_DST_OPTIMAL
			&& new_layout == .SHADER_READ_ONLY_OPTIMAL) {
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.srcStageMask = {.TRANSFER}
		barrier.dstAccessMask = {.SHADER_READ}
		barrier.dstStageMask = {.FRAGMENT_SHADER}
	} else if (old_layout == .PRESENT_SRC_KHR
			&& new_layout == .COLOR_ATTACHMENT_OPTIMAL) {
		barrier.srcStageMask = {.TOP_OF_PIPE}
		barrier.srcAccessMask = {}
		barrier.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT}
		barrier.dstAccessMask = {.COLOR_ATTACHMENT_WRITE}
	} else if (old_layout == .COLOR_ATTACHMENT_OPTIMAL
			&& new_layout == .PRESENT_SRC_KHR) {
		barrier.srcStageMask = {.COLOR_ATTACHMENT_OUTPUT}
		barrier.srcAccessMask = {.COLOR_ATTACHMENT_WRITE}
		barrier.dstStageMask = {.BOTTOM_OF_PIPE}
		barrier.dstAccessMask = {.MEMORY_READ}
	} else if (old_layout == .COLOR_ATTACHMENT_OPTIMAL
			&& new_layout == .SHADER_READ_ONLY_OPTIMAL) {
		barrier.srcStageMask = {.TOP_OF_PIPE}
		barrier.srcAccessMask = {}
		barrier.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT}
		barrier.dstAccessMask = {.MEMORY_READ}
	} else if (old_layout == .SHADER_READ_ONLY_OPTIMAL
			&& new_layout == .COLOR_ATTACHMENT_OPTIMAL) {
		barrier.srcStageMask = {.FRAGMENT_SHADER}
		barrier.srcAccessMask = {.MEMORY_READ}
		barrier.dstStageMask = {.COLOR_ATTACHMENT_OUTPUT}
		barrier.dstAccessMask = {.COLOR_ATTACHMENT_WRITE}
	} else {
		fmt.eprintf("Unsupported layout transition from %d to %d\n", old_layout, new_layout)
		os.exit(1)
	}

	dependency_info := vk.DependencyInfo {
		sType = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers = &barrier,
	}

	vk.CmdPipelineBarrier2(command_buffer, &dependency_info)
}

transition_image_layout_tmp_buffer :: proc (
		image: vk.Image, format: vk.Format, old_layout: vk.ImageLayout, new_layout: vk.ImageLayout,
) {
	command_buffer := begin_single_time_commands()
	
	transition_image_layout(
		command_buffer,
		image,
		format,
		old_layout,
		new_layout,
	)
	
	end_single_time_commands(command_buffer)
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

copy_buffer_to_image :: proc(buffer: vk.Buffer, image: vk.Image, width: u32, height: u32) {
	command_buffer := begin_single_time_commands()

	region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = vk.ImageSubresourceLayers {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageOffset = vk.Offset3D {
			x = 0,
			y = 0,
			z = 0,
		},
		imageExtent = vk.Extent3D {
			width = width,
			height = height,
			depth = 1,
		},
	}

	vk.CmdCopyBufferToImage(
		command_buffer,
		buffer,
		image,
		.TRANSFER_DST_OPTIMAL,
		1,
		&region,
	)

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
		usage_flags: vk.BufferUsageFlags,
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

create_image :: proc(
		width: u32, height: u32, format:vk.Format, tiling: vk.ImageTiling,
		usage: vk.ImageUsageFlags, properties: vk.MemoryPropertyFlags,
) -> Image {
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = vk.Extent3D {
			width = width,
			height = height,
			depth = 1,
		},
		mipLevels = 1,
		arrayLayers = 1,
		format = format,
		tiling = tiling,
		initialLayout = .UNDEFINED,
		usage = usage,
		samples = {._1},
		sharingMode = .EXCLUSIVE,
	}
	
	image: Image

	if vk.CreateImage(instance.device, &image_info, nil, &image.image) != .SUCCESS {
		fmt.eprintf("Failed to create image!\n")
		os.exit(1)
	}
	
	mem_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(instance.device, image.image, &mem_requirements)
	
	alloc_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = mem_requirements.size,
		memoryTypeIndex = find_memory_type(mem_requirements.memoryTypeBits, properties),
	}

	if vk.AllocateMemory(instance.device, &alloc_info, nil, &image.memory) != .SUCCESS {
		fmt.eprintf("Failed to allocate image memory!\n")
	}

	vk.BindImageMemory(instance.device, image.image, image.memory, 0)

	return image
}

cleanup_image :: proc(image: ^Image) {
	if image.view != 0 {
		vk.DestroyImageView(instance.device, image.view, nil)
	}

	vk.DestroyImage(instance.device, image.image, nil)
	vk.FreeMemory(instance.device, image.memory, nil)

	image.image = 0
	image.memory = 0
	image.view = 0
}

create_texture_image :: proc(filename: cstring) -> Image {
	width, height, channels: i32

	fmt.printf("Loading texture image %s\n", filename)
	
	// 4 channels: RGBA
	pixels := stbi.load(filename, &width, &height, &channels, 4)
	if pixels == nil {
		fmt.eprintf("failed to load texture image!\n")
		os.exit(1)
	}

	image_size := cast(vk.DeviceSize) (width * height * 4)

	// Create a buffer and load the image into it
	staging_buffer := create_buffer(
		image_size,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)
	
	data: rawptr
	vk.MapMemory(instance.device, staging_buffer.memory, 0, image_size, {}, &data)
	intrinsics.mem_copy(data, pixels, image_size)
	vk.UnmapMemory(instance.device, staging_buffer.memory)

	stbi.image_free(pixels)

	// Create the image
	image := create_image(
		cast(u32) width,
		cast(u32) height,
		.R8G8B8A8_SRGB,
		.OPTIMAL,
		{.TRANSFER_DST, .SAMPLED},
		{.DEVICE_LOCAL},
	)

	// Transition the image layout to transfer destination
	transition_image_layout_tmp_buffer(image.image, .R8G8B8A8_SRGB, .UNDEFINED, .TRANSFER_DST_OPTIMAL)
	
	copy_buffer_to_image(staging_buffer.buffer, image.image, cast(u32) width, cast(u32) height)

	// Transition the image layout to shader read
	transition_image_layout_tmp_buffer(image.image, .R8G8B8A8_SRGB, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	
	// Clean up the staging buffer
	cleanup_buffer(&staging_buffer)

	// Create the image view
	image.view = create_image_view(image.image, .R8G8B8A8_SRGB, {.COLOR})

	return image
}
