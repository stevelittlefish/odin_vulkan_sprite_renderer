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

	// ----- Create the graphics pipeline -----
	shader_stages: []vk.PipelineShaderStageCreateInfo = {
		vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.VERTEX},
			module = vert_shader_module,
			pName = "main",
		},
		vk.PipelineShaderStageCreateInfo {
			sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage = {.FRAGMENT},
			module = frag_shader_module,
			pName = "main",
		}
	}
	
	binding_description_var := binding_description

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo{
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount = 1,
		vertexAttributeDescriptionCount = cast(u32) len(attribute_descriptions),
		pVertexBindingDescriptions = &binding_description_var,
		pVertexAttributeDescriptions = raw_data(attribute_descriptions),
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount = 1,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable = false,
		rasterizerDiscardEnable = false,
		polygonMode = .FILL,
		lineWidth = 1.0,
		cullMode = {.BACK},
		frontFace = .COUNTER_CLOCKWISE,
		depthBiasEnable = false,
	}
	
	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable = false,
		rasterizationSamples = {._1},
	}

	when BLEND_ENABLED {
		color_blend_attachment := vk.PipelineColorBlendAttachmentState {
			colorWriteMask = {.R, .G, .B, .A},
			blendEnable = true,
			srcColorBlendFactor = .SRC_ALPHA,
			dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
			colorBlendOp = .ADD,
			srcAlphaBlendFactor = .ONE,
			dstAlphaBlendFactor = .ZERO,
			alphaBlendOp = .ADD,
		}
	} else {
		color_blend_attachment := vk.PipelineColorBlendAttachmentState {
			colorWriteMask = {.R, .G, .B, .A},
		}
	}
	
	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable = false,
		logicOp = .COPY,
		attachmentCount = 1,
		pAttachments = &color_blend_attachment,
		blendConstants = {0, 0, 0, 0},
	}
	
	dynamic_states: [2]vk.DynamicState = {.VIEWPORT, .SCISSOR}

	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates = &dynamic_states[0]
	}
	
	push_constants_range_var := push_constants_range
	pipeline_layout_info := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount = 1,
		pSetLayouts = &pipeline.descriptor_set_layout,
		pushConstantRangeCount = 1,
		pPushConstantRanges = &push_constants_range_var,
	}

	if vk.CreatePipelineLayout(instance.device, &pipeline_layout_info, nil, &pipeline.layout) != .SUCCESS {
		fmt.eprintfln("failed to create pipeline layout!")
		os.exit(1)
	}

	rendering_info := vk.PipelineRenderingCreateInfo {
		sType = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount = 1,
		pColorAttachmentFormats = &swap_chain.image_format,
		depthAttachmentFormat = find_depth_format(),
	}
	
	depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable = true,
		depthWriteEnable = true,
		depthCompareOp = .LESS,
		depthBoundsTestEnable = false,
		minDepthBounds = 0.0,
		maxDepthBounds = 1.0,
		stencilTestEnable = false,
		front = {},
		back = {},
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount = 2,
		pStages = &shader_stages[0],
		pVertexInputState = &vertex_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState = &multisampling,
		pColorBlendState = &color_blending,
		pDynamicState = &dynamic_state,
		layout = pipeline.layout,
		pDepthStencilState = &depth_stencil,
		pNext = &rendering_info,
	}

	if vk.CreateGraphicsPipelines(instance.device, 0, 1, &pipeline_info, nil, &pipeline.pipeline) != .SUCCESS {
		fmt.eprintln("failed to create graphics pipeline!")
		os.exit(1)
	}

	// Clean up the shader modules
	vk.DestroyShaderModule(instance.device, frag_shader_module, nil)
	vk.DestroyShaderModule(instance.device, vert_shader_module, nil)

	fmt.printfln(" Pipeline created")

	return pipeline
}
