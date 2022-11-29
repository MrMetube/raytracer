package shader;

import geometry.Geometry;
import math.Color;
import math.Ray;
import scene.Scene;

public class LightShader extends Shader{

    // TODO refactor to reduce doubling 
    @Override public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        return new AmbientShader().getColor(ray, geometry,scene)
                .add( new DiffuseShader().getColor(ray, geometry, scene),
                      new SpecularShader().getColor(ray, geometry, scene));
    }
}
