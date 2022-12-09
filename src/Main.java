
import gui.*;
// import math.*;
// import shader.*;
// import raytracer.*;
// import raytracer.light.*;
// import raytracer.geometry.*;

class Main {
    public static void main(String[] args){
        
        // #region scene setup
        // Scene s = new Scene();
        // s.addBasicMaterials();
        // s.addGeometry(new Plane(new Vector(0, 1, 0), new Point(0, -1, 0),5,"lime"));

        // s.addLightSource(new DirectionalLight(new Vector(0.5, -1, 0.2), Color.WHITE, 0.5));
        // s.addLightSource(new PointLight(new Point(0, 5, 0), Color.PURPLE, 5));

        // s.addGeometry(new Cube(new Point(1, 0.5, 1), new Point(2, 1.5, 2),"turquoise"));
        // s.addGeometry(new Cube(new Point(1, 0, 0), new Point(2, 1, 2),"lemon"));
        // s.addGeometry(new Cube(new Point(-1.1, -1, -1.1), new Point(0, 0.1, 0),"pink"));
        // s.addGeometry(new Cube(new Point(0, -1, -1), new Point(1, 1, 1),"orange"));
        
        // s.toJson("cube");
        //#endregion
        
        new App();

        //#region testing speed
        
        // new World(800, 800).timedRender(new Phong(), 10);
        // new World(800, 800).timedRender(new Phong(), 10);
        // new World(800, 800).timedRender(new BlinnPhong(), 10);
        // new World(800, 800).timedRender(new BlinnPhong(), 10);
        
        //#endregion
    }
}