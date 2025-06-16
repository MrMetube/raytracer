package shader;

import raytracer.*;

public abstract class Shader {
    public abstract void getColor(Payload p, Scene scene);
    public String getName(){ return this.getClass().getSimpleName(); }

    @Override public String toString(){
        return this.getName();
    }
}
