package shader;

import geometry.Geometry;
import math.*;
import scene.*;
import scene.Material;

public class SpecularShader extends Shader{

    @Override
    public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        Material m = scene.getMaterials().get(geometry.material());
        Color out = m.isMetalic() ? m.color(): null;
        Vector v = ray.dir().neg();
        Vector n = geometry.normal(ray.hitPoint());
        Vector r = v.refl(n);
        double vrn = Math.pow(v.dot(r),m.shininess()); 
        for (LightSource l : scene.getLightSources()){
            out = out == null ? l.color().mul(l.intensity()) : out.mul(l.color().mul(l.intensity()));
            out = out.mul(m.specular()*vrn);
        }
        return out;
    }
}
