package shader;

import geometry.Geometry;
import math.Color;
import math.Ray;

public class DistanceShader implements Shader{

    @Override
    public Color getColor(Ray ray, Geometry geometry) {
        if(geometry.intersect(ray)){
            double dis = ray.dir().mul(ray.t()).mag();
            //TODO clean up this
            dis = Math.sqrt(dis)*4;
            return new Color(dis,dis,dis);
        }
        return null;
    }

    @Override
    public String getName() {
        return "DISTANCE";
    }
    
}
