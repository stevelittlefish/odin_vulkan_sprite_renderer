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
			return false;
		}
	}
	
	fmt.println(" All validation layers are supported")

	return true;
}

get_required_extensions :: proc(count: ^u32) -> []cstring {
	/*
	 * If validation layers are enabled, we need to request the VK_EXT_DEBUG_UTILS_EXTENSION_NAME extension
	 * as well as the extensions required by GLFW.
	 *
	 * Note: calling this repeatedly could cause a memory leak as we create a new array each time
	 * if validation layers are enabled.
	 */
	// assert(count != nil)
	
	// Get the required extensions from SDL and set count to the number of extensions
	sdl_extensions := sdl.Vulkan_GetInstanceExtensions(count);

	if sdl_extensions == nil {
		fmt.fprintln(os.stderr, "Failed to get required extensions from GLFW")
		os.exit(1)
	}
	
	if (!ENABLE_VALIDATION_LAYERS) {
		// Just copy the SDL sdl_extensions
		out := make([]cstring, count^)
		for i := 0; i < int(count^); i += 1 {
			out[i] = sdl_extensions[i]
		}
		return out
	}

	// If validation layers are enabled, add the debug utils extension
	out := make([]cstring, count^ + NUM_VALIDATION_LAYERS)
	validation_layers := VALIDATION_LAYERS

	// Copy the SDL extension layers
	for i := 0; i < int(count^); i += 1 {
		out[i] = sdl_extensions[i]
	}
	for j := 0; j < NUM_VALIDATION_LAYERS; j += 1 {
		out[int(count^) + j] = validation_layers[j]
	}
	
	count^ += NUM_VALIDATION_LAYERS
	
	return out
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

init_instance :: proc(window: ^sdl.Window) {
	fmt.println("Initialising Vulkan (VKX)");
	
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
			fmt.fprintfln(os.stderr, "validation layers requested, but not available!\n")
			os.exit(1)
		}
	}
	
	app_info := vk.ApplicationInfo{
		sType = vk.StructureType.APPLICATION_INFO,
		pApplicationName = "Hello Triangle",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName = "No Engine",
		engineVersion = vk.MAKE_VERSION(1, 0, 0),
		apiVersion = vk.API_VERSION_1_3
	}
	
	num_enabled_extensions: u32
	enabled_extensions := get_required_extensions(&num_enabled_extensions)

	fmt.println(" Requesting instance extensions:")
	for i := 0; i < int(num_enabled_extensions); i += 1 {
		fmt.printfln("  Extension: %s", enabled_extensions[i])
	}

	instance_create_info := vk.InstanceCreateInfo{
		sType = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
		ppEnabledExtensionNames = &enabled_extensions[0],
		enabledExtensionCount = num_enabled_extensions,
	}
	
	if ENABLE_VALIDATION_LAYERS {
		validation_layers := VALIDATION_LAYERS

		fmt.println(" Enabling validation layers:")
		for i: u32 = 0; i < NUM_VALIDATION_LAYERS; i += 1 {
			fmt.printfln("  Layer: %s", validation_layers[i])
		}

		instance_create_info.enabledLayerCount = NUM_VALIDATION_LAYERS
		instance_create_info.ppEnabledLayerNames = &validation_layers[0]
		
		debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE, .INFO, .ERROR, .WARNING},
			messageType = {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = debug_callback,
		}

		instance_create_info.pNext = &debug_create_info

	} else {
		instance_create_info.enabledLayerCount = 0
		instance_create_info.pNext = nil
	}
	
	// ----- Create the Vulkan instance -----
	if result := vk.CreateInstance(&instance_create_info, nil, &instance.instance); result != .SUCCESS {
		fmt.fprintln(os.stderr, "failed to create instance! Result:", result);
		os.exit(1);
	}

	/*
	free((void *)instance_create_info.ppEnabledExtensionNames);

	// ----- Create the debug messenger -----
	if (enable_validation_layers) {
		VkDebugUtilsMessengerCreateInfoEXT debug_messenger_create_info;
		vkx_populate_debug_messenger_create_info(&debug_messenger_create_info);
		
		// Create the debug messenger
		PFN_vkCreateDebugUtilsMessengerEXT func = (PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(vkx_instance.instance, "vkCreateDebugUtilsMessengerEXT");
		if (func == NULL) {
			fprintf(stderr, "failed to get vkCreateDebugUtilsMessengerEXT function pointer\n");
			exit(VK_ERROR_EXTENSION_NOT_PRESENT);
		}
	}

	// ----- Create the window surface -----
	if (!SDL_Vulkan_CreateSurface(window, vkx_instance.instance, NULL, &vkx_instance.surface)) {
		fprintf(stderr, "failed to create window surface!");
		exit(1);
	}
	
	// ----- Pick a physical device -----
	
	// Next find a phyiscal device (i.e. a GPU) that supports the required features
	vkx_instance.physical_device = vkx_pick_physical_device();

	if (vkx_instance.physical_device == VK_NULL_HANDLE) {
		fprintf(stderr, "failed to find a suitable GPU!\n");
		exit(1);
	}

	// ----- Create the logical device -----

	// Next we need to create a logical device to interface with the physical device
	// (and also the graphics and presentation queues)
	
	VkxQueueFamilyIndices physical_indices = vkx_find_queue_families(vkx_instance.physical_device, vkx_instance.surface);
	
	// I don't fully understand why, but sometimes it looks like both families could be the same
	uint32_t unique_queue_families[2] = {physical_indices.graphics_family, physical_indices.present_family};
	uint32_t num_unique_queue_families = unique_queue_families[0] == unique_queue_families[1] ? 1 : 2;
	VkDeviceQueueCreateInfo* queue_create_infos = malloc(sizeof(VkDeviceQueueCreateInfo) * num_unique_queue_families);

	float queue_priority = 1.0f;
	for (uint32_t i = 0; i < num_unique_queue_families; i++) {
		VkDeviceQueueCreateInfo queue_create_info = {0};
		queue_create_info.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
		queue_create_info.queueFamilyIndex = unique_queue_families[i];
		queue_create_info.queueCount = 1;
		queue_create_info.pQueuePriorities = &queue_priority;

		queue_create_infos[i] = queue_create_info;
	}

	VkPhysicalDeviceVulkan13Features vulkan13_features = {0};
	vulkan13_features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;
	vulkan13_features.dynamicRendering = VK_TRUE;
	vulkan13_features.synchronization2 = VK_TRUE;

	VkPhysicalDeviceVulkan12Features vulkan12_features = {0};
	vulkan12_features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
	vulkan12_features.descriptorIndexing = VK_TRUE;
	vulkan12_features.shaderSampledImageArrayNonUniformIndexing = VK_TRUE;
	vulkan12_features.pNext = &vulkan13_features;
	
	VkPhysicalDeviceFeatures2 features2 = {0};
	features2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
	features2.features.samplerAnisotropy = VK_TRUE;
	features2.pNext = &vulkan12_features;

	VkDeviceCreateInfo create_info = {0};
	create_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;

	create_info.queueCreateInfoCount = num_unique_queue_families;
	create_info.pQueueCreateInfos = queue_create_infos;

	create_info.enabledExtensionCount = VKX_NUM_DEVICE_EXTENSIONS;
	create_info.ppEnabledExtensionNames = device_extensions;

	create_info.pNext = &features2;

	printf(" Requesting device extensions:\n");

	for (uint32_t i = 0; i < create_info.enabledExtensionCount; i++) {
		printf("  Extension: %s\n", create_info.ppEnabledExtensionNames[i]);
	}

	if (enable_validation_layers) {
		create_info.enabledLayerCount = VKX_NUM_VALIDATION_LAYERS;
		create_info.ppEnabledLayerNames = validation_layers;
	} else {
		create_info.enabledLayerCount = 0;
	}

	if (vkCreateDevice(vkx_instance.physical_device, &create_info, NULL, &vkx_instance.device) != VK_SUCCESS) {
		fprintf(stderr, "failed to create logical device!\n");
		exit(1);
	}

	free(queue_create_infos);

	vkGetDeviceQueue(vkx_instance.device, physical_indices.graphics_family, 0, &vkx_instance.graphics_queue);
	vkGetDeviceQueue(vkx_instance.device, physical_indices.present_family, 0, &vkx_instance.present_queue);

	// ----- Create the command pool -----
	VkCommandPoolCreateInfo command_pool_info = {0};
	command_pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
	command_pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
	command_pool_info.queueFamilyIndex = physical_indices.graphics_family;

	if (vkCreateCommandPool(vkx_instance.device, &command_pool_info, NULL, &vkx_instance.command_pool) != VK_SUCCESS) {
		fprintf(stderr, "failed to create command pool!\n");
		exit(1);
	}

	// ----- Create the command buffers -----
	vkx_instance.command_buffers_count = VKX_FRAMES_IN_FLIGHT;

	VkCommandBufferAllocateInfo buf_alloc_info = {0};
	buf_alloc_info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
	buf_alloc_info.commandPool = vkx_instance.command_pool;
	buf_alloc_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	buf_alloc_info.commandBufferCount = vkx_instance.command_buffers_count;

	if (vkAllocateCommandBuffers(vkx_instance.device, &buf_alloc_info, vkx_instance.command_buffers) != VK_SUCCESS) {
		fprintf(stderr, "failed to allocate command buffers!\n");
		exit(1);
	}
	*/
}
