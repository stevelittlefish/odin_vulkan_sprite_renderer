// Manages main VKX (Vulkan) instance
package vkx

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:os"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"


check_validation_layer_support :: proc() -> bool {
	layer_count: u32
	result := vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	if result != .SUCCESS {
		panic("Couldn't enumerate instance layer properties")
	}

	available_layers := make([]vk.LayerProperties, layer_count, context.temp_allocator)
	result = vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))
	if result != .SUCCESS {
		panic("Couldn't enumerate instance layer properties")
	}
	
	for i := 0; i < NUM_VALIDATION_LAYERS; i += 1 {
		layer_found := false
		validation_layers := VALIDATION_LAYERS

		for j := 0; j < int(layer_count); j += 1 {
			//if (strings.compare(validation_layers[i], available_layers[j].layerName) == 0) {
			if validation_layers[i] == cstring(&available_layers[j].layerName[0]) {
				fmt.printfln("  Validation layer %s is available", validation_layers[i])
				layer_found = true
				break
			}
		}

		if (!layer_found) {
			return false
		}
	}
	
	fmt.println(" All validation layers are supported")

	return true
}

get_required_extensions :: proc() -> [dynamic]cstring {
	/*
	 * If validation layers are enabled, we need to request the VK_EXT_DEBUG_UTILS_EXTENSION_NAME extension
	 * as well as the extensions required by SDL.
	 *
	 * Note: calling this repeatedly could cause a memory leak as we create a new array each time
	 * if validation layers are enabled.
	 */
	// Get the required extensions from SDL and set count to the number of extensions
	sdl_extensions_count: u32
	sdl_extensions := sdl.Vulkan_GetInstanceExtensions(&sdl_extensions_count)

	if sdl_extensions == nil {
		fmt.fprintln(os.stderr, "Failed to get required extensions from GLFW")
		os.exit(1)
	}

	// Create the final list of extensions
	extensions: [dynamic]cstring
	// Copy in the SDL extensions (there must be a function to do this?)
	for i: u32 = 0; i < sdl_extensions_count; i += 1 {
		append(&extensions, sdl_extensions[i])
	}
	
	// If validation layers are enabled, add the debug utils extension
	when ENABLE_VALIDATION_LAYERS {
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}
	
	return extensions
}

debug_callback :: proc "system" (
		message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
		message_type: vk.DebugUtilsMessageTypeFlagsEXT,
		callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
		user_data: rawptr,
) -> b32 {
	context = runtime.default_context()
	fmt.fprintf(os.stderr, "Validation Layer (%d, %d): ", message_severity, message_type)
	fmt.fprintf(os.stderr, "%s\n", callback_data.pMessage)

	return false
}


pick_physical_device :: proc() -> vk.PhysicalDevice {
	device_count: u32
	vk.EnumeratePhysicalDevices(instance.instance, &device_count, nil)

	if (device_count == 0) {
		fmt.fprintfln(os.stderr, "failed to find GPUs with Vulkan support!")
		os.exit(1)
	}
	
	devices := make([]vk.PhysicalDevice, device_count, context.temp_allocator)
	if vk.EnumeratePhysicalDevices(instance.instance, &device_count, raw_data(devices)) != .SUCCESS {
		fmt.fprintfln(os.stderr, "failed enumerate GPUs!")
		os.exit(1)
	}

	// First let's print some info about all of the found devices
	fmt.printfln(" Found %d physical devices:", device_count)
	for i := 0; i < int(device_count); i += 1 {
		device_properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(devices[i], &device_properties)
		fmt.printfln("  Device %d: %s", i, device_properties.deviceName)
	}
	
	physical_device: vk.PhysicalDevice

	for i := 0; i < int(device_count); i += 1 {
		fmt.printfln(" Physical Device %d", i)

		indices := find_queue_families(devices[i], instance.surface)

		fmt.printfln("  Graphics Family: %d", indices.graphics_family)
		fmt.printfln("  Present Family: %d", indices.present_family)
		
        extension_count: u32
        vk.EnumerateDeviceExtensionProperties(devices[i], nil, &extension_count, nil)
		available_extensions := make([]vk.ExtensionProperties, extension_count, context.temp_allocator)

        vk.EnumerateDeviceExtensionProperties(devices[i], nil, &extension_count, raw_data(available_extensions))
		
		// Check all of the required extensions are supported
		required_extensions_supported := true
		
		device_extensions := DEVICE_EXTENSIONS
		for j := 0; j < len(device_extensions); j += 1 {
			extension_found := false
			for k := 0; k < int(extension_count); k += 1 {
				if device_extensions[j] == cstring(&available_extensions[k].extensionName[0]) {
					extension_found = true
					break
				}
			}

			if (!extension_found) {
				required_extensions_supported = false
				fmt.printfln("Extension %s not supported", device_extensions[j])
				break
			}
		}

		if (!required_extensions_supported) {
			continue
		}

		// Check the features we need are supported
		features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceFeatures(devices[i], &features)

		if (!features.samplerAnisotropy) {
			fmt.println("Sampler anisotropy not supported")
			continue
		}
		
		// Check the device supports the required swap chain features
		swap_chain_adequate := false
		
		if (indices.has_present_family) {
			swap_chain_support := query_swap_chain_support(devices[i], instance.surface)
			swap_chain_adequate = len(swap_chain_support.formats) > 0 && len(swap_chain_support.present_modes) > 0
			cleanup_swap_chain_support(&swap_chain_support)
		}
		
        if indices.has_graphics_family && indices.has_present_family && swap_chain_adequate {
			device_properties: vk.PhysicalDeviceProperties
			vk.GetPhysicalDeviceProperties(devices[i], &device_properties)
			fmt.printfln(" Device %d (%s) is suitable", i, device_properties.deviceName)

			physical_device = devices[i]
			break
		}
	}

	return physical_device
}

init_instance :: proc(window: ^sdl.Window) {
	fmt.println("Initialising Vulkan (VKX)")
	
	// Keep a reference to the window to avoid passing it around later
	instance.window = window
	
	// Load Vulkan
	proc_addr := sdl.Vulkan_GetVkGetInstanceProcAddr()
	if proc_addr == nil {
		fmt.fprintfln(os.stderr, "Vulkan proc address is null!")
		os.exit(1)
	}

	vk.load_proc_addresses_global(cast(rawptr)proc_addr)
	
	// Should be loaded now
	assert(vk.CreateInstance != nil)

	when ENABLE_VALIDATION_LAYERS {
		fmt.println(" Validation layers enabled")

		if !check_validation_layer_support() {
			fmt.fprintfln(os.stderr, "validation layers requested, but not available!")
			os.exit(1)
		}
	}
	
	// This will include the validation layer extensions
	enabled_extensions := get_required_extensions()

	fmt.println(" Requesting instance extensions:")
	for extension in enabled_extensions {
		fmt.printfln("  Extension: %s", extension)
	}

	app_info := vk.ApplicationInfo{
		sType = vk.StructureType.APPLICATION_INFO,
		pApplicationName = "Hello Triangle",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName = "No Engine",
		engineVersion = vk.MAKE_VERSION(1, 0, 0),
		apiVersion = vk.API_VERSION_1_3,
	}

	instance_create_info := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
	}

	when ENABLE_VALIDATION_LAYERS {
		validation_layers := VALIDATION_LAYERS

		fmt.println(" Enabling validation layers:")
		for i: u32 = 0; i < NUM_VALIDATION_LAYERS; i += 1 {
			fmt.printfln("  Layer: %s", validation_layers[i])
		}

		instance_create_info.ppEnabledLayerNames = &validation_layers[0]
		instance_create_info.enabledLayerCount = len(validation_layers)
		
		debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE, .INFO, .ERROR, .WARNING},
			// TODO: do I want to enable the address binding messages?
			messageType = {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = debug_callback,
		}

		instance_create_info.pNext = &debug_create_info
	}

	instance_create_info.enabledExtensionCount = u32(len(enabled_extensions))
	instance_create_info.ppEnabledExtensionNames = raw_data(enabled_extensions)

	// ----- Create the Vulkan instance -----
	if result := vk.CreateInstance(&instance_create_info, nil, &instance.instance); result != .SUCCESS {
		fmt.fprintln(os.stderr, "failed to create instance! Result:", result)
		os.exit(1)
	}
	
	// Load procedure addresses
	vk.load_proc_addresses_instance(instance.instance)
	
	// TODO: remove if not needed
	// ----- Create the debug messenger -----
	/*
	if (enable_validation_layers) {
		// Create the debug messenger
		PFN_vkCreateDebugUtilsMessengerEXT func = (PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(vkx_instance.instance, "vkCreateDebugUtilsMessengerEXT");
		if (func == NULL) {
			fprintf(stderr, "failed to get vkCreateDebugUtilsMessengerEXT function pointer\n");
			exit(VK_ERROR_EXTENSION_NOT_PRESENT);
		}
	}
	*/

	// ----- Create the window surface -----
	if !sdl.Vulkan_CreateSurface(window, instance.instance, nil, &instance.surface) {
		fmt.fprintfln(os.stderr, "failed to create window surface!")
		os.exit(1)
	}

	// ----- Pick a physical device -----
	
	// Next find a phyiscal device (i.e. a GPU) that supports the required features
	instance.physical_device = pick_physical_device()

	if (instance.physical_device == nil) {
		fmt.fprintfln(os.stderr, "failed to find a suitable GPU!")
		os.exit(1)
	}

	// ----- Create the logical device -----

	// Next we need to create a logical device to interface with the physical device
	// (and also the graphics and presentation queues)
	
	physical_indices := find_queue_families(instance.physical_device, instance.surface)
	
	// I don't fully understand why, but sometimes it looks like both families could be the same
	unique_queue_families: [2]u32 = {physical_indices.graphics_family, physical_indices.present_family}
	num_unique_queue_families := unique_queue_families[0] == unique_queue_families[1] ? 1 : 2
	queue_create_infos := make([]vk.DeviceQueueCreateInfo, num_unique_queue_families, context.temp_allocator)

	queue_priority: f32 = 1.0
	for i := 0; i < num_unique_queue_families; i += 1 {
		queue_create_infos[i].sType = vk.StructureType.DEVICE_QUEUE_CREATE_INFO
		queue_create_infos[i].queueFamilyIndex = unique_queue_families[i]
		queue_create_infos[i].queueCount = 1
		queue_create_infos[i].pQueuePriorities = &queue_priority
	}

	vulkan13_features := vk.PhysicalDeviceVulkan13Features {
		sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		synchronization2 = true,
	}

	vulkan12_features := vk.PhysicalDeviceVulkan12Features {
		sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		descriptorIndexing = true,
		shaderSampledImageArrayNonUniformIndexing = true,
		pNext = &vulkan13_features,
	}

	features2 := vk.PhysicalDeviceFeatures2 {
		sType = vk.StructureType.PHYSICAL_DEVICE_FEATURES_2,
		features = vk.PhysicalDeviceFeatures {
			samplerAnisotropy = true,
		},
		pNext = &vulkan12_features,
	}
	
	device_extensions := DEVICE_EXTENSIONS

	create_info := vk.DeviceCreateInfo {
		sType = vk.StructureType.DEVICE_CREATE_INFO,
		queueCreateInfoCount = u32(num_unique_queue_families),
		pQueueCreateInfos = raw_data(queue_create_infos),
		enabledExtensionCount = len(device_extensions),
		ppEnabledExtensionNames = &device_extensions[0],
		pNext = &features2,
	}

	fmt.println(" Requesting device extensions:")

	for i: u32 = 0; i < create_info.enabledExtensionCount; i += 1 {
		fmt.printfln("  Extension: %s", create_info.ppEnabledExtensionNames[i])
	}

	when (ENABLE_VALIDATION_LAYERS) {
		create_info.ppEnabledLayerNames = &validation_layers[0]
		create_info.enabledLayerCount = len(validation_layers)
	}

	if vk.CreateDevice(instance.physical_device, &create_info, nil, &instance.device) != .SUCCESS {
		fmt.fprintln(os.stderr, "failed to create logical device!")
		os.exit(1)
	}

	vk.GetDeviceQueue(instance.device, physical_indices.graphics_family, 0, &instance.graphics_queue)
	vk.GetDeviceQueue(instance.device, physical_indices.present_family, 0, &instance.present_queue)

	// ----- Create the command pool -----
	command_pool_info := vk.CommandPoolCreateInfo {
		sType = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = physical_indices.graphics_family,
	}

	if vk.CreateCommandPool(instance.device, &command_pool_info, nil, &instance.command_pool) != .SUCCESS {
		fmt.fprintln(os.stderr, "failed to create command pool!\n")
		os.exit(1)
	}

	// ----- Create the swap chain -----
	create_swap_chain(&instance.swap_chain)

	// Set frames in flight to be the number of swap chain images
	instance.frames_in_flight = cast(u32) len(instance.swap_chain.images)
	fmt.printfln("NUM FRAMES IN FLIGHT: %d", instance.frames_in_flight)

	// ----- Create the command buffers -----
	instance.command_buffers = make([]vk.CommandBuffer, instance.frames_in_flight)

	buf_alloc_info := vk.CommandBufferAllocateInfo {
		sType = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool = instance.command_pool,
		level = vk.CommandBufferLevel.PRIMARY,
		commandBufferCount = instance.frames_in_flight,
	}

	if vk.AllocateCommandBuffers(instance.device, &buf_alloc_info, &instance.command_buffers[0]) != .SUCCESS {
		fmt.fprintln(os.stderr, "failed to allocate command buffers!")
		os.exit(1)
	}

	// ----- Create the semaphores and fence -----
	init_sync_objects(&instance.sync_objects, instance.frames_in_flight)
}

cleanup_instance :: proc() {
	fmt.println("Cleaning up Vulkan Instance (VKX)")
	
	vk.DestroyCommandPool(instance.device, instance.command_pool, nil)

	vk.DestroyDevice(instance.device, nil)
	
	/*
	if (enable_validation_layers) {
		PFN_vkDestroyDebugUtilsMessengerEXT func = (PFN_vkDestroyDebugUtilsMessengerEXT) vkGetInstanceProcAddr(instance.instance, "vkDestroyDebugUtilsMessengerEXT")
		if (func != nil) {
			func(instance.instance, instance.debug_messenger, nil)
		}
	}
	*/

	vk.DestroySurfaceKHR(instance.instance, instance.surface, nil)

	vk.DestroyInstance(instance.instance, nil)
}
