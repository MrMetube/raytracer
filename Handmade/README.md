# Handmade Ray Tracer
A CPU ray-tracer(or path tracer), which tries to be as fast as possible using SIMD (Single Instruction Multiple Data) and multi-threading.
Renders 3D models and uses a BVH (bounding volume hierarchy) to accelerate this.
BRDFs (Bidirectional Reflectance Distribution Function) are used for reflections, which are based on measurements of real materials.

[MERL BRDF source](https://www.merl.com/research/downloads/BRDF/)

## Screenshots
(anti-chronological order)

![Render 20](output/render_20.png)
![Render 19](output/render_19.png)
![Render 18](output/render_18.png)
![Render 17](output/render_17.png)
~300k triangles in one model.
![Render 16](output/render_16.png)
The camera is inside a glass like sphere.
![Render 15](output/render_15.png)
Refractions.
![Render 14](output/render_14.png)
Non-uniform scaled models.
![Render 13](output/render_13.png)
Fixed buggy normals and uv interpolation.
![Render 12](output/render_12.png)
Load obj-files with per vertex normals.
![Render 11](output/render_11.png)
![Render 10](output/render_10.png)
![Render 9](output/render_9.png)
![Render 8](output/render_8.png)
![Render 7](output/render_7.png)
![Render 6](output/render_6.png)
![Render 5](output/render_day_5.png)
![Render 4](output/render_day_4.png)
![Render 3](output/render_day_3.png)
![Render 2](output/render_day_2.png)
![Render 1](output/render_day_1.png)