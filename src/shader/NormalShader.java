package shader;

import geometry.Geometry;
import math.Color;
import math.Ray;
import math.Vector;

public class NormalShader implements Shader {

    @Override
    public Color getColor(Ray ray, Geometry geometry) {
        if(geometry == null) return null;
        if(geometry.intersect(ray)){
            Vector v = geometry.normal(ray.hitPoint());
            return new Color(Math.abs(v.x())*255,Math.abs(v.y())*255,Math.abs(v.z())*255);
        }
        return null;
    }
        
    @Override
    public String getName() {
        return "NORMAL";
    }
}
