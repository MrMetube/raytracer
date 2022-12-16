package shader;

import math.Color;
import math.Point;
import math.Util;
import math.Ray;
import math.Vector;
import raytracer.Material;
import raytracer.Payload;
import raytracer.Scene;
import raytracer.geometry.Geometry;
import raytracer.light.LightSource;

public class Phong extends Shader{

    @Override public void getColor(Payload p, Scene scene) {
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
        Point hitShifted = p.hitPoint().add(n.mul(Util.EPSILON));
        //Colors
        Color ambient =  m.color().mul(ka);

        boolean inShade = false;
        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.directionFrom(p.hitPoint());
            //Check if it is in shade
            Payload pl = new Payload(new Ray(hitShifted, l));
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
            Vector r = l.refl(n).norm();
            double vr = v.dot(r);
            //ignore reflected/opposite results
            vr = Math.max(vr,0);
            double vrs = Math.pow(vr,s);

            Color lc = ls.colorAt(p.hitPoint())
                .mul(ks*vrs);
            il = il.add(lc);
        }
        // Reflection, tell the payload that it has a reflection
        if(m.reflectivity()>0)
            p.setReflection(new Ray(hitShifted, v.refl(n)), m.reflectivity());

        if(m.isMetallic()) il.mul(m.color());
        Color out = m.color()
            .mul(il)
            .mul(kd)
            .add(ambient);
        p.setColor(out);
    }
}
