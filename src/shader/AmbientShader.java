package shader;

import math.Color;
import math.Ray;
import raytracer.Material;
import raytracer.Scene;
import raytracer.geometry.Geometry;

public class AmbientShader extends Shader {

    @Override
    public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        Material m = scene.getMaterials().get(geometry.material());
        return m.color().mul(m.ambient());
    }
}
