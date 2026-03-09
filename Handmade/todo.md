## To be done

- vary sample count over viewport, have a focus region with highest detail
- think more about the response to a accumulated ray
    - do more than store it, get inspired by biology

- Investigate the BRDF table usage (is it still using the wrong indices with the Lane typing?)

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

- load multiple models
    - Load obj files
    - Normals, UVs
    - How to handle textures?
    - allow moving rotating scaling with a transform
        - multiply input by inverse transform and output by transform
    - separate entity from model, use a model index
    - if we do obj parsing, parse once and emit a flat buffer of data
        - header + data, 
        - versioning, migration
        - cache invalidation

- Code minimization
    - replace handmade formatting and format with core:fmt
    - replace arena with mem:arena if it is even needed
    - replace random generator with math xorshiro, which seems to be a continuation of the original xor-shift

### Editor
- Make UI to add new objects to a scene
- UI for Brdfs, how to display? 
    - Maybe another view with just the selected object rendered alone.
    - Improve render abstraction to not always copy all data
    




