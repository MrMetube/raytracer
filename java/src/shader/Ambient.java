package shader;

import raytracer.Material;
import raytracer.Payload;
import raytracer.Scene;

public class Ambient extends Shader {

    @Override
    public void getColor(Payload p, Scene scene) {
        Material m = scene.getMaterials().get(p.target().material());
        p.setColor(m.color().mul(m.ambient()));
    }
}
