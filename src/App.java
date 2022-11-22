import shader.*;
import geometry.*;
import math.*;
import scene.*;
import scene.Material;

class App {
    public static void main(String[] args){
        Scene s = new Scene(new Camera(new Point(0, 0, -100), new Point(0, 0, 0), 90, 1080, 1080));
        
        s.addMaterial("blue", new Material(new Color(0.2, 0.2, 0.9), 0.2, 1, 0, 0));
        s.addMaterial("red",  new Material(new Color(0.9, 0.2, 0.6), 0.2, 1, 0, 0));
        s.addMaterial("green",new Material(new Color(0.2, 0.5, 0.3), 0.1, 1, 0, 0));
        
        s.addGeometry(new Sphere(new Point(0, 0, 50), 50, "red"));
        s.addGeometry(new Sphere(new Point(0, 50, 200), 150, "blue"));
        s.addGeometry(new Plane(new Vector(0, 1, 0), new Point(0, -100, 0),"green"));
        
        // s.makeImage(new AmbientShader());
        s.makeImage(new DiffuseShader());

        // s.toJson("Materials");

        // new Scene("./scenes/Materials.json").makeImage(new AmbientShader());
    }
}