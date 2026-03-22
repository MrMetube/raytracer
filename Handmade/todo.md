## To be done

- dont enqueue tiles in order
    - use offsets to evenly distribute work across the screen 
    - so that partial output is more representative
    - do the same in the pixel loop, i.e. every even then every odd pixel

- for fast render
    - automatic mode
    - take last frame time, estimate next time by time_per_ray * ray_count -> rays_per_pixel

- store uvs per vertex and assign a texture per model
    - calculate the rays uvs on hit, and save the texture
    - bilinear sample the texture based on uvs
    - make a default 1x1 white pixel texture
    - load a model with uvs and texture and render it

- vary sample count over viewport, have a focus region with highest detail
- think more about the response to a accumulated ray
    - do more than store it, get inspired by biology

- Simulate more light behaviour
    - Refraction
    - Participating media(Fog)
    - Subsurface Scattering
        - What can be lerped(like .scatter) and what must be handled separatly
        - Find ground truths to check against

- Postprocessing / filtering of noisy images
    - How do cameras do this filtering?
        - bayer filters and proprietary de-mosaic-ing
    - How does the human eye do this? 
        - response-curve to certain wave lengths
        - and cones are bundled/summed, whilst rods are individual signals
        - and responses supress another, leaving "afterimages"
        - this requires a wavelength per ray, instead of a color
            - how to sample a texture's colors as wavelengths?
- Energy conservation

- check for "false sharing" between threads in render tiles
    - maybe adjust sizes

- load multiple models
    - Load obj files
    - Normals, UVs
    - How to handle textures?
    - allow rotating scaling with a transform
    - separate entity from model, use a model index

- Code minimization
    - replace random generator with math xorshiro, which seems to be a continuation of the original xor-shift

### Editor
- Make UI to add new objects to a scene
- UI for Brdfs, how to display? 
    - Maybe another view with just the selected object rendered alone.
    - Improve render abstraction to not always copy all data
    




