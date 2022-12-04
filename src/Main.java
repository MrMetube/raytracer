
import gui.*;
import shader.*;
import raytracer.*;
import java.awt.image.BufferedImage;

class Main {
    public static void main(String[] args){
        
        //#region scene setup
        // Scene s = new Scene(new Camera(new Point(-1, 2, -3), new Point(0, 1, 0), 90, 800, 800));
        // s.addBasicMaterials();
        // s.addMaterial("yellow", new Material(new Color(0.9,0.9,0.5), 0.1, 0.9, 0.2, 5, true));
        // s.addGeometry(new Plane(new Vector(0, 1, 0), new Point(0, -1, 0), 5,"light"));

        // Vector left  = new Vector(2, 1, 0);
        // Vector right = new Vector(-2, 1, 0);
        // Vector up    = Vector.up;

        // s.addGeometry(new Plane(right, new Point(-1.4, 0, 0), 1,"pink"));
        // s.addGeometry(new Plane(left,  new Point(-0.45, 0, 0), 1,"orange"));
        // s.addGeometry(new Plane(right, new Point(0.45, 0, 0), 1,"lemon"));
        // s.addGeometry(new Plane(left,  new Point(1.4, 0, 0), 1,"lime"));

        // s.addGeometry(new Plane(up,  new Point(0, .9, 0), 1,"purple"));
        
        // s.addGeometry(new Plane(right,  new Point(-.45, 1.8, 0), 1,"azure"));
        // s.addGeometry(new Plane(left,  new Point(.45, 1.8, 0), 1,"light"));
        
        // s.addLightSource(new PointLightSource(new Point(0, 5, 0), Color.WHITE, 0.9));
        // s.addLightSource(new PointLightSource(new Point(5, 5, 10), Color.WHITE, 0.9));
        
        // s.toJson("new");
        //#endregion
        
        new Window();

        //#region testing speed
        
        // new World(800, 800).timedRender(new Intersect(), 10);
        
        //#endregion
    }
}