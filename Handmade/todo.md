### To be done
- Add refraction (and make it variable like .scatter with a basic lerp) 
- Extract rendering and all dependent variables
- Make UI where the result is displayed and a render can be started, display render progress
- Make UI for the world where spheres and planes can be added and modified for the next render
- Make a copy of the world and send to be rendered in other threads
- UI for Brdfs, how to display? Maybe another view with just the selected object rendered alone. Needs a render task queue. 
- Add bounding volumes(Rectangle) and triangles
- Add collections of basic elements (oct-tree) 
- Select/Move(scale/rotate) objects in the editor ui? Needs a fast rendering view. 

### Done 

- Add spall profiling
- Simplify SIMD parts if possible with newer avx512
