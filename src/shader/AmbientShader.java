package shader;

import math.Color;
import raytracer.Material;
import raytracer.Payload;
import raytracer.Scene;

public class AmbientShader extends Shader {

    @Override
    public Color getColor(Payload p, Scene scene) {
        Material m = scene.getMaterials().get(p.target().material());
        return m.color().mul(m.ambient());
    }
}
