## To be done

- ui
    - hot_t, active_t, triggered_t interpolators
    - smooth exponential lerp
        - https://lisyarus.github.io/blog/posts/exponential-smoothing.html
        - position = lerp(position, target, 1 - exp(- speed * dt)) or even position = lerp(target, position, exp(- speed * dt))

- store uvs per vertex and assign a texture per model
    - save the texture on hit
    - bilinear sample the texture based on uvs
    - make a default 1x1 white pixel texture
    - load a model with uvs and texture and render it

- models
    - How to handle textures?
    - separate entity from model, use a model index

- vary sample count over viewport, have a focus region with highest detail
    - base this on the shifted iteration?
    - just sample certain regions first/allow partial results to be displayed
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

- Code minimization
    - replace random generator with math xorshiro, which seems to be a continuation of the original xor-shift

### Editor
- Make UI to add new objects to a scene
    




