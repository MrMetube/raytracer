package shader;

import math.Color;
import math.Vector;
import raytracer.LightSource;
import raytracer.Material;
import raytracer.Payload;
import raytracer.Scene;
import raytracer.geometry.Geometry;

public class BlinnPhong extends Shader{
    @Override public Color getColor(Payload p, Scene scene) {
        // Constants
        Geometry geometry = p.target();
        Material m = scene.getMaterials().get(geometry.material());
        
        double ks = m.specular();
        double kd = m.diffuse();
        double ka = m.ambient();
        Vector v = p.ray().dir().norm();
        double s = m.shininess();

        Color il = new Color(0, 0, 0);
        
        Vector n = geometry.normal(p.hitPoint());
        //Colors
        Color ambient =  m.color().mul(ka);

        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.pos().sub(p.hitPoint());
            double distance = l.mag();
            l = l.div(distance);
            distance = distance * distance;
            //diffuse
            double nl = n.dot(l);
            //If nl < 0 ?? can you ignore this 
            nl = Math.max(nl,0);
            il = il.add(ls.color()
                .mul(nl)
                .mul(ls.intensity())
            );
            //specular
            Vector h = v.add(l).norm();
            double nh = h.dot(n);
            //ignore reflected/opposite results
            nh = Math.max(nh,0);
            double nhs = Math.pow(nh,s*4);

            Color lc = ls.color()
                .mul(ks)
                .mul(1/distance)
                .mul(nhs);
            il = il.add(lc);
        }

        if(m.isMetallic()) il.mul(m.color());
        Color out = m.color()
            .mul(il)
            .mul(kd)
            .add(ambient);
        return out;
    }
}
