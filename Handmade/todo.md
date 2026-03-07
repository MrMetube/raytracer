## To be done

- vary sample count over viewport, have a focus region with highest detail
- think more about the response to a accumulated ray
    - do more than store it, get inspired by biology

- Simplify to only one render primitive(triangles)
- Investigate the BRDF table usage (is it still using the wrong indices with the Lane typing?)

- Add refraction
    - Ensure that the refraction is correct
    - can we lerp it like .scatter
    - how does it interact with reflectance and reflecting in general
- Postprocessing / filtering of noise images
    - How do cameras do this filtering?
    - How does the human eye do this? 
        - Does this require another color model(wavelengths) or is RGB fine?
- Energy conservation

### Editor
- Make UI to add new objects to a scene
- UI for Brdfs, how to display? 
    - Maybe another view with just the selected object rendered alone.
- Select/Move(scale/rotate) objects in the editor ui?
    - make models of triangles editable all at once