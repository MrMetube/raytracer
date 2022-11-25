import shader.*;

import geometry.*;
import gui.App;
import math.*;
import scene.*;

class Main {
    public static void main(String[] args){
        // Scene s = new Scene("./scenes/example spheres.json");
        // // s.addMaterial("white",  new Material(new Color(1.0,1.0,1.0), 0.1, 0.6, 0.9, 100, false));
        // // s.addMaterial("yellow", new Material(new Color(0.9,0.9,0.5), 0.1, 0.9, 0.2, 5, true));
        // // s.addMaterial("lime",   new Material(new Color(0.7,0.8,0.2), 0.1, 1, 0, 1, false));
        // // s.addGeometry(new Plane(new Vector(0, 1, 0), new Point(0, -1, 0),"white"));
        // // // s.addGeometry(new Plane(new Vector(1, 0, 0), new Point(5, 0, 0),"white"));
        // // // s.addGeometry(new Plane(new Vector(-1, 0, 0), new Point(-5, 0, 0),"white"));
        // // // s.addGeometry(new Plane(new Vector(0, 0, -1), new Point(0, 0, 5),"white"));
        // // s.addLightSource(new PointLightSource(new Point(0, 10, 0), new Color(1, 1, 1), 1));
        // // s.addGeometry(new Sphere(new Point(-2, 1.0, 1), 0.75,"lime"));
        // // s.addGeometry(new Sphere(new Point(-1, 1.2, 1), 0.75,"yellow"));
        // // s.addGeometry(new Sphere(new Point(0, 1.4, 1), 0.75,"white"));
        // // s.addGeometry(new Sphere(new Point(1, 1.2, 1), 0.75,"yellow"));
        // // s.addGeometry(new Sphere(new Point(2, 1.0, 1), 0.75,"lime"));

        // s.makeImage(new AmbientShader());

        // s.makeImage(new DiffuseShader());

        // s.makeImage(new SpecularShader());

        // s.makeImage(new LightShader());

        // s.toJson("example");

        new App();
    }
}