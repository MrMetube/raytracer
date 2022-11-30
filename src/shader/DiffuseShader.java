package shader;

import math.*;
import raytracer.*;
import raytracer.geometry.*;

public class DiffuseShader extends Shader{

    @Override
    public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        Material m = scene.getMaterials().get(geometry.material());
        Color il = new Color(0, 0, 0);
        Vector n = geometry.normal(ray.hitPoint());
        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.pos().sub(ray.hitPoint()).norm();
            double nl = n.dot(l);
            //If nl < 0 ?? can you ignore this 
            if(nl<0) nl = 0;
            Color lc = ls.color().mul(ls.intensity()).mul(nl);
            il = il.add(lc);
        }
        Color out = m.color()
            .mul(il)
            .mul(m.diffuse());
        return out;
    }

}
