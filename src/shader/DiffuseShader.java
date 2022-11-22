package shader;

import geometry.Geometry;
import math.*;
import scene.LightSource;
import scene.Scene;
import scene.Material;

public class DiffuseShader extends Shader{

    @Override
    public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        Material m = scene.getMaterials().get(geometry.material());
        Color out = m.color();
        for (LightSource ls : scene.getLightSources()) {
            Vector n = geometry.normal(ray.hitPoint());
            Vector l = ls.pos().sub(ray.hitPoint()).norm();
            out = out.mul(ls.color().mul(ls.intensity())).mul(n.dot(l)).mul(m.diffuse());
        }
        return out;
    }

}
