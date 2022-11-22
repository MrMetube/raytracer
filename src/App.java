import shader.*;
import geometry.*;
import math.*;
import scene.*;
import scene.Material;

class App {
    public static void main(String[] args){
        Scene s = new Scene(new Camera(new Point(0, 0, -2), new Point(0, 0, 0), 90, 800, 800));
        
        s.addLightSource(new PointLightSource(new Point(-10, 10, -10), new Color(1, 1, 1), 1));
        s.addMaterial("magenta", new Material(new Color(1, 0.2, 1), 0.1, 0.9, 0.9, 200, false) );
        s.addGeometry(new Sphere(new Point(0, 0, 0), 1, "magenta"));

        s.makeImage(new DiffuseShader());
        s.makeImage(new SpecularShader());
        s.makeImage(new LightShader());

        // s.toJson("example");
    }
}