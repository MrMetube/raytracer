package shader;

import math.Color;
import math.Ray;
import math.Vector;
import raytracer.LightSource;
import raytracer.Material;
import raytracer.Scene;
import raytracer.geometry.Geometry;

public class PhongShader extends Shader{

    @Override public Color getColor(Ray ray, Geometry geometry, Scene scene) {
        // Constants
        Material m = scene.getMaterials().get(geometry.material());
        
        double ks = m.specular();
        double kd = m.diffuse();
        double ka = m.ambient();
        Vector v = ray.hitPoint().sub(ray.origin()).norm();
        double s = m.shininess();

        Color il = new Color(0, 0, 0);
        
        Vector n = geometry.normal(ray.hitPoint());
        //Colors
        Color ambient =  m.color().mul(ka);

        for (LightSource ls : scene.getLightSources()) {
            Vector l = ls.pos().sub(ray.hitPoint()).norm();
            //diffuse
            double nl = n.dot(l);
            //If nl < 0 ?? can you ignore this 
            if(nl>0)
                il = il.add(ls.color().mul(ls.intensity()).mul(nl));
            //specular
            Vector r = l.refl(n).norm();
            double vr = r.dot(v);
            if(vr > 0){
                double vrs = Math.pow(vr,s);
                Color lc = ls.color()
                    .mul(ks)
                    .mul(vrs);
                il = il.add(lc);
            }
        }

        if(m.isMetallic()) il.mul(m.color());
        Color out = m.color()
            .mul(il)
            .mul(kd)
            .add(ambient);
        return out;
    }
}
