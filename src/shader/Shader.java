package shader;

import math.Color;
import math.Ray;
import raytracer.Scene;
import raytracer.geometry.Geometry;

public abstract class Shader {
    public abstract Color getColor(Ray ray, Geometry geometry, Scene scene);
    public String getName(){ return this.getClass().getSimpleName(); }
}
