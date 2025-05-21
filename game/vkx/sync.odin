// Synchronisation object initialisation
package vkx

import "core:fmt"
import "core:os"
import vk "vendor:vulkan"


init_sync_objects :: proc(sync_objects: ^SyncObjects, frames_in_flight: u32) {
	sync_objects.in_flight_fences = make([]vk.Fence, frames_in_flight)
	sync_objects.image_available_semaphores = make([]vk.Semaphore, frames_in_flight)
	sync_objects.render_finished_semaphores = make([]vk.Semaphore, frames_in_flight)

	semaphore_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	for i: u32 = 0; i < frames_in_flight; i += 1 {
		if vk.CreateSemaphore(instance.device, &semaphore_info, nil, &sync_objects.image_available_semaphores[i]) != .SUCCESS \
				|| vk.CreateSemaphore(instance.device, &semaphore_info, nil, &sync_objects.render_finished_semaphores[i]) != .SUCCESS {
			fmt.eprint("failed to create semaphores for a frame!\n")
			os.exit(1)
		}

		if vk.CreateFence(instance.device, &fence_info, nil, &sync_objects.in_flight_fences[i]) != .SUCCESS {
			fmt.eprint("failed to create synchronization objects for a frame!\n")
			os.exit(1)
		}
	}
}

cleanup_sync_objects :: proc(sync_objects: ^SyncObjects, frames_in_flight: u32) {
	for i: u32 = 0; i < frames_in_flight; i += 1 {
		vk.DestroySemaphore(instance.device, sync_objects.render_finished_semaphores[i], nil)
		vk.DestroySemaphore(instance.device, sync_objects.image_available_semaphores[i], nil)
		vk.DestroyFence(instance.device, sync_objects.in_flight_fences[i], nil)
	}
}
