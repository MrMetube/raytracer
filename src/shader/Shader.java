package shader;

import math.Color;
import raytracer.*;

public abstract class Shader {
    public abstract Color getColor(Payload p, Scene scene);
    public String getName(){ return this.getClass().getSimpleName(); }
}
