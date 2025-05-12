// Code for managing rendering pipelines
package vkx

import "core:fmt"
import "core:os"
import vk "vendor:vulkan"

/*
 * Create a descriptor set layout for the uniform buffer and texture sampler.
 *
 * This is made based on the assumption that most pipelines in the app will
 * use a similar layout format.
 *
 * @param num_textures The number of textures to make room for in the descriptor set layout
 */
create_descriptor_set_layout :: proc(num_textures: u32) -> vk.DescriptorSetLayout {
	bindings: [2]vk.DescriptorSetLayoutBinding = {
		// First binding is for the uniform buffer
		{
			binding = 0,
			descriptorType = .UNIFORM_BUFFER,
			descriptorCount = 1,
			stageFlags = {.VERTEX, .FRAGMENT},
		},
		// Second binding is for the texture sampler
		{
			binding = 1,
			descriptorType = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = num_textures,
			stageFlags = {.FRAGMENT},
		},
	}

	layout_info := vk.DescriptorSetLayoutCreateInfo{
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 2,
		pBindings = &bindings[0],
	}
	
	// Create the descriptor set layout
	descriptor_set_layout: vk.DescriptorSetLayout
	if (vk.CreateDescriptorSetLayout(instance.device, &layout_info, nil, &descriptor_set_layout) != .SUCCESS) {
		fmt.eprintln("failed to create descriptor set layout!")
		os.exit(1)
	}
	return descriptor_set_layout
}

create_shader_module :: proc(byte_code: []byte) -> vk.ShaderModule {
	create_info := vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(byte_code),
		pCode = cast(^u32) &byte_code[0],
	}

	shader_module: vk.ShaderModule
	if vk.CreateShaderModule(instance.device, &create_info, nil, &shader_module) != .SUCCESS {
		fmt.eprintfln("failed to create shader module!")
		os.exit(1)
	}

	return shader_module
}

/*
 * Load a shader module from a file
 *
 * @param path The path to the shader file
 */
load_shader_module :: proc(path: string) -> vk.ShaderModule {
	fmt.printfln(" Loading shader %s", path)

	byte_code, err := os.read_entire_file_from_filename_or_err(path, context.temp_allocator)
	if err != nil {
		fmt.eprintfln("Error reading file %s: %s", path, err)
		os.exit(1)
	}
	
	fmt.printfln("  Read %d bytes", len(byte_code))

	shader_module := create_shader_module(byte_code)

	return shader_module
}

/*
 * Create a graphics pipeline for rendering from a vertex buffer.
 *
 * Normally vertex data would be in the vertex buffer, but for primitives it is still
 * useful as it can store offsets for other data fed in from the uniform buffer.
 *
 * @param binding_description The vertex input binding description
 * @param attribute_descriptions The vertex input attribute descriptions
 * @param attribute_descriptions_count The number of vertex input attribute descriptions
 * @param push_constant_range The push constant range
 * @param num_textures The number of textures to make room for in the descriptor set layout
 */
create_vertex_buffer_pipeline :: proc(
		vert_shader_path: string,
		frag_shader_path: string,
		binding_description: vk.VertexInputBindingDescription,
		attribute_descriptions: []vk.VertexInputAttributeDescription,
		push_constants_range: vk.PushConstantRange,
		num_textures: u32,
) -> Pipeline {
	// TODO: make this a parameter?
	BLEND_ENABLED :: false

	pipeline: Pipeline
	pipeline.descriptor_set_layout = create_descriptor_set_layout(num_textures)
	
	// ----- Load the shaders -----
	vert_shader_module := load_shader_module(vert_shader_path)
	frag_shader_module := load_shader_module(frag_shader_path)
	// BOOKMARK
	/*
	
	// ----- Create the graphics pipeline -----
	VkPipelineShaderStageCreateInfo vert_shader_stage_info = {0}
	vert_shader_stage_info.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
	vert_shader_stage_info.stage = VK_SHADER_STAGE_VERTEX_BIT
	vert_shader_stage_info.module = vert_shader_module
	vert_shader_stage_info.pName = "main"

	VkPipelineShaderStageCreateInfo frag_shader_stage_info = {0}
	frag_shader_stage_info.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO
	frag_shader_stage_info.stage = VK_SHADER_STAGE_FRAGMENT_BIT
	frag_shader_stage_info.module = frag_shader_module
	frag_shader_stage_info.pName = "main"

	VkPipelineShaderStageCreateInfo shader_stages[] = {vert_shader_stage_info, frag_shader_stage_info}
	
	VkPipelineVertexInputStateCreateInfo vertex_input_info = {0}
	vertex_input_info.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
	vertex_input_info.vertexBindingDescriptionCount = 1
	vertex_input_info.vertexAttributeDescriptionCount = attribute_descriptions_count
	vertex_input_info.pVertexBindingDescriptions = &binding_description
	vertex_input_info.pVertexAttributeDescriptions = attribute_descriptions

	VkPipelineInputAssemblyStateCreateInfo input_assembly = {0}
	input_assembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	input_assembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
	input_assembly.primitiveRestartEnable = VK_FALSE

	VkPipelineViewportStateCreateInfo viewport_state = {0}
	viewport_state.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO
	viewport_state.viewportCount = 1
	viewport_state.scissorCount = 1

	VkPipelineRasterizationStateCreateInfo rasterizer = {0}
	rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO
	rasterizer.depthClampEnable = VK_FALSE
	rasterizer.rasterizerDiscardEnable = VK_FALSE
	rasterizer.polygonMode = VK_POLYGON_MODE_FILL
	rasterizer.lineWidth = 1.0f
	rasterizer.cullMode = VK_CULL_MODE_BACK_BIT
	rasterizer.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE
	rasterizer.depthBiasEnable = VK_FALSE

	VkPipelineMultisampleStateCreateInfo multisampling = {0}
	multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
	multisampling.sampleShadingEnable = VK_FALSE
	multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT

	VkPipelineColorBlendAttachmentState color_blend_attachment = {0}

	if (BLEND_ENABLED) {
		color_blend_attachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT
		color_blend_attachment.blendEnable = VK_TRUE
		color_blend_attachment.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA
		color_blend_attachment.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
		color_blend_attachment.colorBlendOp = VK_BLEND_OP_ADD
		color_blend_attachment.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE
		color_blend_attachment.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO
		color_blend_attachment.alphaBlendOp = VK_BLEND_OP_ADD
	}
	else {
		color_blend_attachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT
		color_blend_attachment.blendEnable = VK_FALSE
	}

	VkPipelineColorBlendStateCreateInfo color_blending = {0}
	color_blending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO
	color_blending.logicOpEnable = VK_FALSE
	color_blending.logicOp = VK_LOGIC_OP_COPY
	color_blending.attachmentCount = 1
	color_blending.pAttachments = &color_blend_attachment
	color_blending.blendConstants[0] = 0.0f
	color_blending.blendConstants[1] = 0.0f
	color_blending.blendConstants[2] = 0.0f
	color_blending.blendConstants[3] = 0.0f

	VkDynamicState dynamic_states[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR}

	VkPipelineDynamicStateCreateInfo dynamic_state = {0}
	dynamic_state.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO
	dynamic_state.dynamicStateCount = 2
	dynamic_state.pDynamicStates = dynamic_states
	

	VkPipelineLayoutCreateInfo pipeline_layout_info = {0}
	pipeline_layout_info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
	pipeline_layout_info.setLayoutCount = 1
	pipeline_layout_info.pSetLayouts = &pipeline.descriptor_set_layout
	pipeline_layout_info.pushConstantRangeCount = 1
	pipeline_layout_info.pPushConstantRanges = &push_constant_range

	if (vkCreatePipelineLayout(vkx_instance.device, &pipeline_layout_info, NULL, &pipeline.layout) != VK_SUCCESS) {
		fprintf(stderr, "failed to create pipeline layout!")
		exit(1)
	}

	VkPipelineRenderingCreateInfo rendering_info = {0}
	rendering_info.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO
	rendering_info.colorAttachmentCount = 1
	rendering_info.pColorAttachmentFormats = &vkx_swap_chain.image_format
	rendering_info.depthAttachmentFormat = vkx_find_depth_format()

	VkPipelineDepthStencilStateCreateInfo depth_stencil = {0}
	depth_stencil.sType = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
	depth_stencil.depthTestEnable = VK_TRUE
	depth_stencil.depthWriteEnable = VK_TRUE
	depth_stencil.depthCompareOp = VK_COMPARE_OP_LESS
	depth_stencil.depthBoundsTestEnable = VK_FALSE
	depth_stencil.minDepthBounds = 0.0f
	depth_stencil.maxDepthBounds = 1.0f
	depth_stencil.stencilTestEnable = VK_FALSE
	depth_stencil.front = (VkStencilOpState) {0}
	depth_stencil.back = (VkStencilOpState) {0}

	VkGraphicsPipelineCreateInfo pipeline_info = {0}
	pipeline_info.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO
	pipeline_info.stageCount = 2
	pipeline_info.pStages = shader_stages
	pipeline_info.pVertexInputState = &vertex_input_info
	pipeline_info.pInputAssemblyState = &input_assembly
	pipeline_info.pViewportState = &viewport_state
	pipeline_info.pRasterizationState = &rasterizer
	pipeline_info.pMultisampleState = &multisampling
	pipeline_info.pColorBlendState = &color_blending
	pipeline_info.pDynamicState = &dynamic_state
	pipeline_info.layout = pipeline.layout
	pipeline_info.renderPass = VK_NULL_HANDLE
	pipeline_info.subpass = 0
	pipeline_info.basePipelineHandle = VK_NULL_HANDLE
	pipeline_info.pDepthStencilState = &depth_stencil
	pipeline_info.pNext = &rendering_info

	if (vkCreateGraphicsPipelines(vkx_instance.device, VK_NULL_HANDLE, 1, &pipeline_info, NULL, &pipeline.pipeline) != VK_SUCCESS) {
		fprintf(stderr, "failed to create graphics pipeline!")
		exit(1)
	}

	vkDestroyShaderModule(vkx_instance.device, frag_shader_module, NULL)
	vkDestroyShaderModule(vkx_instance.device, vert_shader_module, NULL)

	printf(" Pipeline created\n")

	*/
	return pipeline
}
