package shader;

import math.Color;
import math.Vector;
import raytracer.Payload;
import raytracer.Scene;

public class NormalShader extends Shader {

    @Override public Color getColor(Payload p, Scene scene) {
        Vector v = p.target().normal(p.hitPoint());
        return new Color(Math.abs(v.x()),Math.abs(v.y()),Math.abs(v.z()));
    }
}
