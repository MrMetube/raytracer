# To be done

### ray/path tracing
- participating media
- subsurface scattering
- multiple importance sampling
    - shadow rays on the empty lanes
- ensure energy conservation

### postprocessing
- denoising
- hdr and apeture/exposure adjustments

### renderer
- texture sampling
    - use textures for: normals, other surface properties, material?
    - how can these textures be used artistically? (blending materials)
- instanced rendering
    - sort by model, keep caches hot in the model loop
- model bvh 
    - once there are more than 3 models in a scene
    
### engine
- just load all brdfs
- serialize the scene
    - reflection and version(range) annotation
    - save and load
    - (hotreloading)
- scene editing
    - models selection
    - transform manipulators
    - new objects
- ui
    - hot_t, active_t, triggered_t interpolators
    - [smooth exponential lerp](https://lisyarus.github.io/blog/posts/exponential-smoothing.html)
        - ``position = lerp(position, target, 1 - exp(- speed * dt))`` or even
        - ``position = lerp(target, position, exp(- speed * dt))``

### cleanup
- use math/xorshiro generator
