package shader;

import math.Color;
import math.Ray;
import raytracer.Payload;
import raytracer.Scene;

public class Distance extends Shader{

    @Override public void getColor(Payload p, Scene scene) {
        Ray ray = p.ray();
        double dis = 1/ray.origin().sub(p.hitPoint()).mag();
        p.setColor(new Color(dis,dis,dis));
    }
}
