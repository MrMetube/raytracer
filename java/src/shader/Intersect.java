package shader;

import math.Color;
import raytracer.Payload;
import raytracer.Scene;

public class Intersect extends Shader{
    
    @Override public void getColor(Payload p, Scene scene) {
        p.setColor(new Color(0.19, 0.2, 0.26));
    }
}
