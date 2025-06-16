import gui.App;
import raytracer.*;

class Main {
    public static void main(String[] args) throws Exception {
        var app = new App();
        // var s = new Scene();
        // s.addBasicMaterials();
        // s.addLightSource(new DirectionalLight(new Vector(0, -1, -.2), Color.WHITE, 1));
        // s.addGeometry(new Plane(new Vector(0, 1, 0), new Point(0, -1, 0),10,"lime"));

        // s.addGeometry(new Triangle(new Point(2,0,0), new Point(-2,-1,0), new Point(0, 3, 3) , "silver"));

        // s.toJson("triangle");
        var s = new Scene("mirrors.json");
        app.scene = s;
    }
}