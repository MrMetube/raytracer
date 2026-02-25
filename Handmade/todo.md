### To be done
- Add collections of basic elements (oct-tree)
- Make UI to add new spheres and planes
- UI for Brdfs, how to display? Maybe another view with just the selected object rendered alone. Needs a render task queue.
- Select/Move(scale/rotate) objects in the editor ui? Needs a fast rendering view. 

- Add refraction (and make it variable like .scatter with a basic lerp) 
  - Ensure that the refraction is correct

### Done 

- Allow for multiple renders at once
- Add spall profiling
- Simplify SIMD parts if possible with newer avx512
- Extract rendering and all dependent variables
- Make UI where the result is displayed and a render can be started, display render progress
- Make UI for the world where spheres and planes can be modified for the next render
