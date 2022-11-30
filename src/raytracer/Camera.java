package raytracer;
import math.Point;
import math.Ray;
import math.Vector;

public class Camera {
    Point pos;
    Point lookAt;
    double fov;
    int width;
    int height;

    double pixelSize;

    Vector vpn;
    Vector up;
    Vector right;

    public Camera(Point pos, Point lookAt, double fovDeg, int width, int height) {
        this.pos = pos;
        this.lookAt = lookAt;
        this.fov = Math.toRadians(fovDeg);
        this.width = width;
        this.height = height;

        double aspectRatio = width/height;
        double halfHeight = Math.tan(fov/2);
        this.pixelSize = (aspectRatio < 1 ? halfHeight : halfHeight/aspectRatio) * 2/height ;

        this.vpn = lookAt.sub(pos).norm();
        // Dieser Trick funtioniert nicht, wenn vpn = (0,1,0) ist, weil dann ein Null-Vektor entsteht.
        // Wenn dies der Fall ist, drehen wir die Reihenfolge um und berechnen zuerst up.
        if(vpn.cross(new Vector(0, 1, 0)) != new Vector(0, 0, 0)){
            this.right = new Vector(0, 1, 0).cross(vpn).norm();
            this.up = vpn.cross(right).norm();
        }else{//man sollte einfach einen leicht anderen nehmen. Das umzudrehen ist kA
            this.up = new Vector(0, 0, 1).cross(vpn).norm();
            this.right = vpn.cross(up).norm();
        }
    }

    public Ray generateRay(int x, int y){
        double xOffset = (x + 0.5 - width  / 2) * pixelSize;
        double yOffset = (y + 0.5 - height / 2) * pixelSize;

        return new Ray(pos, right.mul(xOffset).add(up.mul(yOffset)).add(vpn));
    }

    public int getWidth() {return width;}
    public int getHeight() {return height;}
    
}
