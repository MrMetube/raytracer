import shader.*;

import geometry.*;
import math.*;
import scene.*;

class App {
    public static void main(String[] args){
        Scene s = new Scene("./scenes/example color.json");
        
        // Timing includes writing image to disc
        // TODO create extra method to time only rendering

        // long start;
        // start = System.currentTimeMillis();
        // System.out.printf("X Shader took %s ms%n", System.currentTimeMillis()-start);
        s.makeImage(new AmbientShader());

        s.makeImage(new DiffuseShader());

        s.makeImage(new SpecularShader());

        s.makeImage(new LightShader());

        // s.toJson("example");
    }
}