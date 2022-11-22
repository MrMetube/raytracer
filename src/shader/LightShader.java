package shader;

import geometry.Geometry;
import math.Color;
import math.Ray;
import scene.Scene;

public class LightShader extends Shader{

    @Override public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        if(geometry.intersect(ray)){
            return new AmbientShader().getColor(ray, geometry,scene)
                // .add(new Color(1, 1, 1).mul(m.color()).mul(m.diffuse()).mul()) // TODO Light color?
                // .add(new Color(1, 1, 1).mul())
                ;
        }
        return null;
    }
}
