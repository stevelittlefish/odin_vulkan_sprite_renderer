// Code for managing the swap chain for the app
package vkx

import "core:fmt"
import "core:os"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"

choose_swap_extent :: proc(window: ^sdl.Window, capabilities: ^vk.SurfaceCapabilitiesKHR ) -> vk.Extent2D {
	if (capabilities.currentExtent.width != 0xFFFFFFFF) {
		return capabilities.currentExtent
	} else {
		width, height: i32
		sdl.GetWindowSize(window, &width, &height)

		actual_extent := vk.Extent2D{
			width=u32(width),
			height=u32(height),
		}
		
		// Clamp the width and height to the min and max extents
		if (actual_extent.width < capabilities.minImageExtent.width) {
			actual_extent.width = capabilities.minImageExtent.width
		}
		else if (actual_extent.width > capabilities.maxImageExtent.width) {
			actual_extent.width = capabilities.maxImageExtent.width
		}

		if (actual_extent.height < capabilities.minImageExtent.height) {
			actual_extent.height = capabilities.minImageExtent.height
		}
		else if (actual_extent.height > capabilities.maxImageExtent.height) {
			actual_extent.height = capabilities.maxImageExtent.height
		}

		return actual_extent
	}
}

create_swap_chain :: proc() {
	swap_chain_support := query_swap_chain_support(instance.physical_device, instance.surface)

	if len(swap_chain_support.formats) == 0 {
		fmt.fprintln(os.stderr, "Swap chain support not available (no formats)")
		os.exit(1)
	}
	else if (len(swap_chain_support.present_modes) == 0) {
		fmt.fprintln(os.stderr, "Swap chain support not available (no present modes)")
		os.exit(1)
	}

	fmt.printfln(
		" Swap chain support: %d formats, %d present modes",
		len(swap_chain_support.formats),
		len(swap_chain_support.present_modes)
	)
	
	// Choose the best surface format from the available formats
	surface_format := swap_chain_support.formats[0]
	for i := 0; i < len(swap_chain_support.formats); i +=1 {
		if swap_chain_support.formats[i].format == vk.Format.B8G8R8A8_SRGB \
				&& swap_chain_support.formats[i].colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
			surface_format = swap_chain_support.formats[i]
			break
		}
	}
	
	// Choose the best present mode from the available present modes
	present_mode := vk.PresentModeKHR.FIFO
	for i := 0; i < len(swap_chain_support.present_modes); i += 1 {
		if swap_chain_support.present_modes[i] == vk.PresentModeKHR.MAILBOX {
			present_mode = swap_chain_support.present_modes[i]
			break
		}
	}

	swap_chain.extent = choose_swap_extent(instance.window, &swap_chain_support.capabilities)
	fmt.printfln(" Swap chain extent: %d x %d", swap_chain.extent.width, swap_chain.extent.height)

	image_count := swap_chain_support.capabilities.minImageCount + 1
	if swap_chain_support.capabilities.maxImageCount > 0 && image_count > swap_chain_support.capabilities.maxImageCount {
		image_count = swap_chain_support.capabilities.maxImageCount
	}

	create_info: vk.SwapchainCreateInfoKHR = {
		sType = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
		surface = instance.surface,
		minImageCount = image_count,
		imageFormat = surface_format.format,
		imageColorSpace = surface_format.colorSpace,
		imageExtent = swap_chain.extent,
		imageArrayLayers = 1,
		imageUsage = {.COLOR_ATTACHMENT},
		preTransform = swap_chain_support.capabilities.currentTransform,
		compositeAlpha = {.OPAQUE},
		presentMode = present_mode,
		clipped = true,
	}

	indices := find_queue_families(instance.physical_device, instance.surface)
	queueFamilyIndices: []u32 = {indices.graphics_family, indices.present_family}

	if indices.graphics_family != indices.present_family {
		create_info.imageSharingMode = vk.SharingMode.CONCURRENT
		create_info.queueFamilyIndexCount = 2
		create_info.pQueueFamilyIndices = &queueFamilyIndices[0]
	} else {
		create_info.imageSharingMode = vk.SharingMode.EXCLUSIVE
	}

	if vk.CreateSwapchainKHR(instance.device, &create_info, nil, &swap_chain.swap_chain) != .SUCCESS {
		fmt.fprintfln(os.stderr, "failed to create swap chain!")
		os.exit(1)
	}
	
	num_swap_chain_images: u32
	vk.GetSwapchainImagesKHR(instance.device, swap_chain.swap_chain, &num_swap_chain_images, nil)
	swap_chain.images = make([]vk.Image, num_swap_chain_images)
	vk.GetSwapchainImagesKHR(instance.device, swap_chain.swap_chain, &num_swap_chain_images, raw_data(swap_chain.images))

	// Transition the images to a valid layout
    // Begin the command buffer
    begin_info := vk.CommandBufferBeginInfo {
		sType = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO
	}

	command_buffer := instance.command_buffers[0]

    if vk.ResetCommandBuffer(command_buffer, {}) != .SUCCESS {
        fmt.fprintln(os.stderr, "failed to reset command buffer!")
        os.exit(1)
    }

    if vk.BeginCommandBuffer(command_buffer, &begin_info) != .SUCCESS {
        fmt.fprintln(os.stderr, "failed to begin recording command buffer!")
        os.exit(1)
    }
	
	// All of the swap chain images are now in the VK_IMAGE_LAYOUT_UNDEFINED layout, which is not a valid
	// layout for rendering - we need to transition them to VK_IMAGE_LAYOUT_PRESENT_SRC_KHR

    // Transition the images to a valid layout
    for i := 0; i < len(swap_chain.images); i += 1 {
		barrier := vk.ImageMemoryBarrier {
			sType = vk.StructureType.IMAGE_MEMORY_BARRIER,
			srcAccessMask = {},
			dstAccessMask = {.MEMORY_READ},
			oldLayout = vk.ImageLayout.UNDEFINED,
			newLayout = vk.ImageLayout.PRESENT_SRC_KHR,
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			image = swap_chain.images[i],
			subresourceRange = vk.ImageSubresourceRange{
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		
		src_stage_mask: vk.PipelineStageFlags = {.TOP_OF_PIPE}
		dst_stage_mask: vk.PipelineStageFlags = {.BOTTOM_OF_PIPE}

        vk.CmdPipelineBarrier(
            command_buffer,
            src_stage_mask,  // Pipeline stage that source access mask applies to
            dst_stage_mask,  // Pipeline stage that destination access mask applies to
			{},              // Dependency flags (not used in this case)
            0, nil,          // Memory barriers
            0, nil,          // Buffer memory barriers
            1, &barrier      // Image memory barriers
        )
    }

    if vk.EndCommandBuffer(command_buffer) != .SUCCESS {
        fmt.fprintln(os.stderr, "failed to record command buffer!")
        os.exit(1)
    }
	
	// Submit the command buffer
	submit_info := vk.SubmitInfo {
		sType = vk.StructureType.SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers = &command_buffer,
	}
	
	// TODO: is this right? VK_NULL_HANDLE was passed in for the fence in the C version
	if vk.QueueSubmit(instance.graphics_queue, 1, &submit_info, vk.Fence{}) != .SUCCESS {
		fmt.fprintln(os.stderr, "failed to submit command buffer!")
		os.exit(1)
	}
	
	// ----- Now create the image views -----
	swap_chain.image_views = make([]vk.ImageView, len(swap_chain.images))

	for i := 0; i < len(swap_chain.images); i += 1 {
		swap_chain.image_views[i] = create_image_view(
			swap_chain.images[i], surface_format.format, {.COLOR}
		)
	}
	
	fmt.println(" Image views created")

	// Wait for the queue to finish processing the command buffer
	vk.QueueWaitIdle(instance.graphics_queue)

	swap_chain.image_format = surface_format.format

	cleanup_swap_chain_support(&swap_chain_support)

	fmt.printfln(" Swap chain created with format: %d", swap_chain.image_format)
}

cleanup_swap_chain :: proc() {
	fmt.printf("Cleaning up swap chain\n");
	
	for i := 0; i < len(swap_chain.images); i += 1 {
		vk.DestroyImageView(instance.device, swap_chain.image_views[i], nil)
	}
	
	// TODO: is this free needed?
	delete(swap_chain.image_views)
	swap_chain.image_views = nil

	vk.DestroySwapchainKHR(instance.device, swap_chain.swap_chain, nil);
}

recreate_swap_chain :: proc() {
	// TODO: fix the memory leak!
	fmt.println("WARNING: memory leak in vkx.recreate_swap_chain")

	width, height: i32
	sdl.GetWindowSize(instance.window, &width, &height)

	vk.DeviceWaitIdle(instance.device)

	cleanup_swap_chain()

	create_swap_chain()
}
