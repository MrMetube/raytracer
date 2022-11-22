package shader;

import geometry.Geometry;
import math.Color;
import math.Ray;
import scene.Scene;

public abstract class Shader {
    public abstract Color getColor(Ray ray, Geometry geometry, Scene scene);
    public String getName(){ return this.getClass().getSimpleName(); }
}
