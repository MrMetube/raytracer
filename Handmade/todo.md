### To be done
- Debug the octtree traversal, there are visual artifacts along bounding rectangles and triangle edges
    - Check for NaNs and Infs
    - Do we keep the basic for loop version or fold the traversal into the cast rays to simplify
    - Do we keep the other primitives(spheres, planes) or should we simplify to only do triangles
    - Should octtree nodes have a pointer/index or inline/copy the value directly?
- Make UI to add new objects to a scene
- UI for Brdfs, how to display? 
    - Maybe another view with just the selected object rendered alone.
- Select/Move(scale/rotate) objects in the editor ui?
    - make models of triangles editable all at once

- Add refraction
    - Ensure that the refraction is correct
    - can we lerp it like .scatter
    - how does it interact with reflectance and reflecting in general

### Done 

- Add collections of basic elements (oct-tree)
- Allow for multiple renders at once
- Add spall profiling
- Simplify SIMD parts if possible with newer avx512
- Extract rendering and all dependent variables
- Make UI where the result is displayed and a render can be started, display render progress
- Make UI for the world where spheres and planes can be modified for the next render
