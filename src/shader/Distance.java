package shader;

import math.Color;
import math.Ray;
import raytracer.Payload;
import raytracer.Scene;

public class Distance extends Shader{

    @Override public Color getColor(Payload p, Scene scene) {
        Ray ray = p.ray();
        double dis = ray.origin().sub(p.hitPoint()).mag()/255;
        return new Color(dis,dis,dis);
    }
}
