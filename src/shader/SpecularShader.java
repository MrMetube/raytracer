package shader;

import math.*;
import raytracer.*;
import raytracer.geometry.Geometry;

public class SpecularShader extends Shader{

    @Override
    public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        Material m = scene.getMaterials().get(geometry.material());
        double ks = m.specular();
        Vector v = ray.hitPoint().sub(ray.origin()).norm();
        double n = m.shininess();
        Color il = new Color(0, 0, 0);
        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.pos().sub(ray.hitPoint()).norm();
            Vector r = l.refl(geometry.normal(ray.hitPoint())).norm();
            double vr = r.dot(v);
            if(vr < 0 ) continue;
            double vrn = Math.pow(vr,n);
            Color lc = ls.color()
                .mul(ks)
                .mul(vrn);
            il = il.add(lc);
        }
        Color out = m.isMetallic() ? m.color().mul(il) : il;

        return out;
    }

    public Color getColor2(Ray ray, Geometry geometry, Scene scene) {
        Material m = scene.getMaterials().get(geometry.material());
        Color out = m.isMetallic() ? m.color(): null;
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
