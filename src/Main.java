import gui.*;
import math.*;
import shader.*;
import raytracer.*;
import raytracer.light.*;
import raytracer.geometry.*;

@SuppressWarnings("unused")
class Main {
    public static void main(String[] args){
        
        // Scene s = Scene.randomSpheres(10);
        // s.addBasicMaterials();
        // s.addGeometry(new Plane(new Vector(0, 1, 0), new Point(0, -1, 0),5,"lime"));

        // s.addGeometry(new Sphere(new Point(1.001,0,0), 1, "silver"));
        // s.addGeometry(new Sphere(new Point(-1.001,0,0), 1, "gold"));

        // s.toJson("reflection");
        new App();
    }
}