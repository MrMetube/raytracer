package shader;

import geometry.Geometry;
import math.Color;
import math.Ray;
import scene.Scene;

public class IntersectShader extends Shader{

    @Override public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        return new Color(0.19, 0.2, 0.26);
    }
}
