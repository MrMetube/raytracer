package shader;

import math.Color;
import math.Ray;
import math.Util;
import math.Vector;
import raytracer.Material;
import raytracer.Payload;
import raytracer.Scene;
import raytracer.geometry.Geometry;
import raytracer.light.LightSource;

public class BlinnPhong extends Shader{
    @Override public Color getColor(Payload p, Scene scene) {
        // Constants
        Geometry geometry = p.target();
        Material m = scene.getMaterials().get(geometry.material());
        
        double ks = m.specular();
        double kd = m.diffuse();
        double ka = m.ambient();
        Vector v = p.ray().dir().norm().neg();
        double s = m.shininess();

        Color il = new Color(0, 0, 0);
        
        Vector n = geometry.normal(p.hitPoint());
        //Colors
        Color ambient =  m.color().mul(ka);

        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.directionFrom(p.hitPoint());
            //Check if it is in shade
            boolean inShade = false;
            Payload pl = new Payload(new Ray(p.hitPoint().add(n.mul(Util.EPSILON)), l));
            for (Geometry g : scene.getGeometries()) {
                if (g.intersect(pl)) {
                    inShade = true;
                    break;
                }
            }
            if(inShade) continue;
            //diffuse
            double nl = n.dot(l);
            //ignore reflected/opposite results
            nl = Math.max(nl,0);
            il = il.add(ls.colorAt(p.hitPoint()).mul(nl));
            //specular
            Vector h = v.add(l).norm();
            double nh = h.dot(n);
            //ignore reflected/opposite results
            nh = Math.max(nh,0);
            double nhs = Math.pow(nh,s*4);

            Color lc = ls.colorAt(p.hitPoint())
                .mul(ks)
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
