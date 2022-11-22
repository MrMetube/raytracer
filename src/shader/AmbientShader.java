package shader;

import geometry.Geometry;
import math.Color;
import math.Ray;
import scene.Material;
import scene.Scene;

public class AmbientShader extends Shader {

    @Override
    public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        Material m = scene.getMaterials().get(geometry.material());
        return m.color().mul(m.ambient());
    }
}
