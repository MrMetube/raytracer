package shader;

import geometry.Geometry;
import math.*;
import scene.LightSource;
import scene.Scene;
import scene.Material;

public class DiffuseShader extends Shader{

    @Override
    public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        Color out = new Color(0, 0, 0);
        Material m = scene.getMaterials().get(geometry.material());
        for (LightSource ls : scene.getLightSources()) {
            Vector n = geometry.normal(ray.hitPoint());
            Vector l = ray.hitPoint().sub(ls.pos());
            out.mul(ls.color()).mul(m.diffuse()).mul(n.dot(l));
        }
        return out;
    }

}
