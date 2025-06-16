package shader;

import math.Color;
import math.Vector;
import raytracer.Payload;
import raytracer.Scene;

public class Normal extends Shader {

    @Override public void getColor(Payload p, Scene scene) {
        Vector v = p.target().normal(p.hitPoint());
        p.setColor(new Color(Math.abs(v.x()),Math.abs(v.y()),Math.abs(v.z())));
    }
}
