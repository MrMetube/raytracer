package shader;

import math.Color;
import math.Ray;
import raytracer.Scene;
import raytracer.geometry.Geometry;

public class DistanceShader extends Shader{

    @Override public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        double dis = ray.origin().sub(ray.hitPoint()).mag()/255;
        return new Color(dis,dis,dis);
    }
}
