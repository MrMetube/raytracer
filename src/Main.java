import shader.*;

import geometry.*;
import gui.App;
import math.*;
import scene.*;

class Main {
    public static void main(String[] args){
        Scene s = new Scene("./scenes/spheres.json");
        
        //#region scene setup
        // Scene s = new Scene(new Camera(new Point(0, 0, -2), new Point(0, 0, 0), 90, 800, 800));
        // s.addBasicMaterials();
        // s.addMaterial("yellow", new Material(new Color(0.9,0.9,0.5), 0.1, 0.9, 0.2, 5, true));
        // s.addMaterial("lime",   new Material(new Color(0.7,0.8,0.2), 0.1, 1, 0, 1, false));
        // s.addGeometry(new Plane(new Vector(0, 1, 0), new Point(0, -1, 0),"white"));
        // s.addLightSource(new PointLightSource(new Point(0, 10, -10), Color.WHITE, 1));
        // s.addLightSource(new PointLightSource(new Point(10, 10, -10), Color.RED, 0.5));
        // s.addLightSource(new PointLightSource(new Point(-10, 10, -10), Color.BLUE, 0.5));
        // s.addGeometry(new Sphere(new Point(-1.5, 0, .5), 0.75,"lime"));
        // s.addGeometry(new Sphere(new Point(-1, 1.2, .5), 0.75,"yellow"));
        // s.addGeometry(new Sphere(new Point(0, 1.4, .5), 0.75,"white"));
        // s.addGeometry(new Sphere(new Point(1, 1.2, .5), 0.75,"yellow"));
        // s.addGeometry(new Sphere(new Point(1.5, 0, .5), 0.75,"lime"));
        // s.addGeometry(new Sphere(new Point(0, 0, 2), 2,"gray"));
        
        // s.toJson("spheres");
        //#endregion
        
        //#region make Image
        // s.makeImage(new AmbientShader());

        // s.makeImage(new DiffuseShader());

        // s.makeImage(new SpecularShader());

        // s.makeImage(new LightShader());
        //#endregion
        
        // new App();

        //#region testing speed
        // for (int i = 0; i < 10; i++)
        //     s.makeImage(new LightShader(),true);
        //#endregion
    }
}