package shader;

import math.Color;
import raytracer.Payload;
import raytracer.Scene;

public class IntersectShader extends Shader{
    
    @Override public Color getColor(Payload p, Scene scene) {
        return new Color(0.19, 0.2, 0.26);
    }
}
