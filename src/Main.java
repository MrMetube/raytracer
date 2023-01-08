import gui.*;
import math.*;
import shader.*;
import raytracer.*;
import raytracer.light.*;
import raytracer.geometry.*;

@SuppressWarnings("unused")
class Main {
    public static void main(String[] args){
        var app = new App();
        
        // var s = new Scene();
        // s.addBasicMaterials();
        // s.addLightSource(new DirectionalLight(new Vector(0, -1, -.2), Color.WHITE, 1));
        // s.addGeometry(new Plane(new Vector(0, 1, 0), Point.zero,10,"lime"));

        // s.addGeometry(new Plane(new Vector(1, 0, 0), new Point(-3, 0, 0),5,"silver"));
        // s.addGeometry(new Plane(new Vector(-1, 0, 0), new Point(3, 0, 0),6,"silver"));

        // s.addGeometry(new Sphere(new Point(1,0.5,-2), 1, "turquoise"));
        // s.addGeometry(new Sphere(new Point(0,-0.5,1), 2, "pink"));
        // s.addGeometry(new Sphere(new Point(-4,1.5,3), 3, "lemon"));

        // s.toJson("mirrors");
        // app.scene = s;
    }
}