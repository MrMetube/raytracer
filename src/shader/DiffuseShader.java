package shader;

import math.*;
import raytracer.*;

public class DiffuseShader extends Shader{

    @Override
    public Color getColor(Payload p, Scene scene) {
        Material m = scene.getMaterials().get(p.target().material());
        Color il = new Color(0, 0, 0);
        Vector n = p.target().normal(p.hitPoint());
        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.pos().sub(p.hitPoint()).norm();
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
