package raytracer;

import gui.World;
import math.Point;
import math.Ray;
import math.Vector;
import raytracer.stuff.SupersamplingMode;

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

    World world;
    SupersamplingMode supersampling = SupersamplingMode.NONE;

    public Camera(Point pos, Point lookAt, double fovDeg, World world) {
        this.pos = pos;
        this.lookAt = lookAt;
        this.fov = Math.toRadians(fovDeg);
        this.width = world.getWidth();
        this.height = world.getHeight();

        double aspectRatio = width/height;
        double halfHeight = Math.tan(fov/2);
        this.pixelSize = (aspectRatio < 1 ? halfHeight : halfHeight/aspectRatio) * 2/height ;

        calcVectors();
    }

    private void calcVectors(){
        this.vpn = lookAt.sub(pos).norm();
        // Dies funtioniert nicht, wenn vpn = (0,1,0) ist, weil dann ein Null-Vektor entsteht.
        // Man sollte einfach einen leicht anderen Vektor nehmen. 
        if(vpn.cross(new Vector(0, 1, 0)) != new Vector(0, 0, 0)){
            this.right = new Vector(0, 1, 0).cross(vpn).norm();
            this.up = vpn.cross(right).norm();
        }
    }

    public Payload[] generatePayload(int x, int y){
        double xOffset, yOffset;
        Vector dir;
        Payload[] out = {};

        switch(supersampling){
            case NONE:
                xOffset = (x + 0.5 - width  / 2) * pixelSize;
                yOffset = (y + 0.5 - height / 2) * pixelSize;
                dir = right.mul(xOffset).add(up.mul(yOffset)).add(vpn);
                out = new Payload[] { new Payload( new Ray(pos, dir)) };
                break;
            case X4: // Generate 4 Rays in a square around the center
                out = new Payload[4];
                for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) {
                    xOffset = (x + 0.25 + (0.5*i) - width  / 2) * pixelSize;
                    yOffset = (y + 0.25 + (0.5*j) - height / 2) * pixelSize;
                    dir = right.mul(xOffset).add(up.mul(yOffset)).add(vpn);
                    out[i*2+j] = new Payload( new Ray(pos, dir));
                }
                break;
            case X9: // Generate 9 Rays, 4 corners, 4 sides, 1 middle
                out = new Payload[9];
                for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) {
                    xOffset = (x + (0.5*i) - width  / 2) * pixelSize;
                    yOffset = (y + (0.5*j) - height / 2) * pixelSize;
                    dir = right.mul(xOffset).add(up.mul(yOffset)).add(vpn);
                    out[i*3+j] = new Payload( new Ray(pos, dir));
                }
                break;
            default: // just deactivate ss if it isnt set for whatever reason
                break;
        }
        return out;
    }

    public void move(Vector dir){
        this.pos = pos.add(dir);
    }
    
    public void rotate(double x, double y){
        lookAt.add(new Vector(x, y, 0));
        calcVectors();
    }
    
    public Point pos() {return pos;}
    public void setSupersampling(SupersamplingMode mode){supersampling = mode;}
}
