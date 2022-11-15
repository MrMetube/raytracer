public class Camera {
    Point pos;
    Point lookAt;
    double fov;
    int width;
    int height;

    double aspectRatio;
    double halfHeight;
    double pixelSize;

    Vector vpn;
    Vector up;
    Vector right;

    Camera(Point pos, Point lookAt, double fovDeg, int width, int height) {
        // TODO: Cleanup variables at the end
        this.pos = pos;
        this.lookAt = lookAt;
        this.fov = Math.toRadians(fovDeg);
        this.width = width;
        this.height = height;

        this.aspectRatio = width/height;
        this.halfHeight = Math.tan(fov/2);
        this.pixelSize = (aspectRatio > 0 ? halfHeight : halfHeight/aspectRatio) * 2/height ;

        this.vpn = lookAt.sub(pos).norm();
        // Dieser Trick funtioniert nicht, wenn vpn = (0,1,0) ist, weil dann ein Null-Vektor entsteht.
        // Wenn dies der Fall ist, drehen wir die Reihenfolge um und berechnen zuerst up.
        if(vpn != new Vector(0, 1, 0)){
            this.right = new Vector(0, 1, 0).cross(vpn).norm();
            this.up = vpn.cross(right).norm();
        }else{
            this.up = new Vector(0, 0, 1).cross(vpn).norm();
            this.right = vpn.cross(up).norm();
        }
    }

    Ray generateRay(int x, int y){
        double xOffset = (x + 0.5 - width  / 2) * pixelSize;
        double yOffset = (y + 0.5 - height / 2) * pixelSize;

        return new Ray(pos, right.mul(xOffset).add(up.mul(yOffset)).add(vpn));
    }
    
}
