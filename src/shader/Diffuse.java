package shader;

import math.*;
import raytracer.*;
import raytracer.light.LightSource;

public class Diffuse extends Shader{

    @Override
    public void getColor(Payload p, Scene scene) {
        Material m = scene.getMaterials().get(p.target().material());
        Color il = new Color(0, 0, 0);
        Vector n = p.target().normal(p.hitPoint());
        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.directionFrom(p.hitPoint());
            double nl = n.dot(l);
            //ignore reflected/opposite results
            nl = Math.max(nl,0);
            Color lc = ls.colorAt(p.hitPoint())
                .mul(nl);
            il = il.add(lc);
        }
        Color out = m.color()
            .mul(il)
            .mul(m.diffuse());
        p.setColor(out);
    }

}
