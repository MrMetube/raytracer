package shader;

import math.*;
import raytracer.*;
import raytracer.light.LightSource;

public class Specular extends Shader{

    @Override
    public void getColor(Payload p, Scene scene) {
        Material m = scene.getMaterials().get(p.target().material());
        double ks = m.specular();
        Vector v = p.ray().dir().norm();
        double n = m.shininess();
        Color il = new Color(0, 0, 0);
        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.directionFrom(p.hitPoint());
            Vector r = l.refl(p.target().normal(p.hitPoint())).norm();
            double vr = r.dot(v);
            // don't calc false values
            vr = Math.max(vr, 0);
            double vrn = Math.pow(vr,n);
            Color lc = ls.colorAt(p.hitPoint())
                .mul(ks)
                .mul(vrn);
            il = il.add(lc);
        }
        Color out = m.isMetallic() ? m.color().mul(il) : il;

        p.setColor(out);
    }
}
