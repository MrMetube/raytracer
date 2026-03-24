# Handmade Ray Tracer
A CPU ray-tracer(or path tracer), which tries to be as fast as possible using SIMD (Single Instruction Multiple Data) and multi-threading.
Renders 3D models and uses a BVH (bounding volume hierarchy) to accelerate this.
BRDFs (Bidirectional Reflectance Distribution Function) are used for reflections, which are based on measurements of real materials.

[MERL BRDF source](https://www.merl.com/research/downloads/BRDF/)

## Screenshots
(anti-chronological order)

![Render 16](data/render_16.png)
The camera is inside a glass like sphere.
![Render 15](data/render_15.png)
Refractions..
![Render 14](data/render_14.png)
Non-uniform scaled models.
![Render 13](data/render_13.png)
Fixed buggy normals and uv interpolation.
![Render 12](data/render_12.png)
Load obj-files with per vertex normals.
![Render 11](data/render_11.png)
![Render 10](data/render_10.png)
![Render 9](data/render_9.png)
![Render 8](data/render_8.png)
![Render 7](data/render_7.png)
![Render 6](data/render_6.png)
![Render 5](data/render_day_5.png)
![Render 4](data/render_day_4.png)
![Render 3](data/render_day_3.png)
![Render 2](data/render_day_2.png)
![Render 1](data/render_day_1.png)