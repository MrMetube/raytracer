package shader;

import math.Color;
import math.Ray;
import math.Vector;
import raytracer.Scene;
import raytracer.geometry.Geometry;

public class NormalShader extends Shader {

    @Override public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        Vector v = geometry.normal(ray.hitPoint());
        return new Color(Math.abs(v.x()),Math.abs(v.y()),Math.abs(v.z()));
    }
}
