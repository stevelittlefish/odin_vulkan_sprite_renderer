# Vulkan Sprite Renderer

2D sprite renderer written in Odin using the vulkan API

This project is an Odin port of my plain C implementation of a 2D sprite
renderer using the Vulkan API.  I started by following one of the Vulkan
tutorials, and ended up making a lot of changes, mainly:

- Using SDL3 instead of GLFW
- Using Vulkan 1.3 instead of 1.0
- Dynamic rendering
- Sychronisation2
- Offscreen rendering / post processing
- Multiple piplines
- Generating sprite vertices in the vertex shader

I make no claims that this is well organised or setup perfectly.  I tried
 to tidy a few things up but I'm still not sure the best way to organise
 a Vulkan project.

## Building / Running

You will need to have Odin installed, and you will need Vulkan installed
too.  I think you can run it without validation layers without the full
SDK, but if you want the validation layers you should install the SDK.

I have included the compiled shaders, so you should be able to run it
just by typing:

```
odin run game
```

If you want to run it with validation layers enabled do:

```
odin run game -define:ENABLE_VALIDATION_LAYERS=true
```

I've included a shell script and batch file to compile the shaders on
Linux and Windows respectively, as well as a run script to run the app
with the validation layers enabled.

