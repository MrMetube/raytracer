package shader;

import math.*;
import raytracer.*;

public class Specular extends Shader{

    @Override
    public Color getColor(Payload p, Scene scene) {
        Material m = scene.getMaterials().get(p.target().material());
        double ks = m.specular();
        Vector v = p.ray().dir().norm();
        double n = m.shininess();
        Color il = new Color(0, 0, 0);
        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.pos().sub(p.hitPoint());
            double distance = l.mag();
            l = l.div(distance);
            distance = distance * distance;
            Vector r = l.refl(p.target().normal(p.hitPoint())).norm();
            double vr = r.dot(v);
            // dont calc false values
            vr = Math.max(vr, 0);
            double vrn = Math.pow(vr,n);
            Color lc = ls.color()
                .mul(ks)
                .mul(vrn)
                .mul(ls.intensity())
                .div(distance);
            il = il.add(lc);
        }
        Color out = m.isMetallic() ? m.color().mul(il) : il;

        return out;
    }
}
