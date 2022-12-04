package raytracer;
import java.util.Random;

import math.Point;
import math.Ray;
import math.Vector;

public class Camera {
    Point pos;
    Point lookAt;
    double fov;
    //TODO camera  shouldn't set width/height
    int width;
    int height;
    SupersamplingMode supersampling = SupersamplingMode.NONE;

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
        Payload[] out;

        switch(supersampling){
            case NONE:
                xOffset = (x + 0.5 - width  / 2) * pixelSize;
                yOffset = (y + 0.5 - height / 2) * pixelSize;
                dir = right.mul(xOffset).add(up.mul(yOffset)).add(vpn);
                out = new Payload[] { new Payload( new Ray(pos, dir)) };
                return out;
            case X9: // Generate 9 Rays, 4 corners, 4 sides, 1 middle
                out = new Payload[9];
                for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) {
                    xOffset = (x + (0.5*i) - width  / 2) * pixelSize;
                    yOffset = (y + (0.5*j) - height / 2) * pixelSize;
                    dir = right.mul(xOffset).add(up.mul(yOffset)).add(vpn);
                    out[i*3+j] = new Payload( new Ray(pos, dir));
                }
                return out;
            case RANDOMx2: // Generate 2 rays with slight random offset
                return getRandomPayloads(x, y, 2);
            case RANDOMx4:
                return getRandomPayloads(x, y, 4);
            case RANDOMx8:
                return getRandomPayloads(x, y, 8);
            default: // just deactivate ss if it isnt set for whatever reason
                setSupersampling(SupersamplingMode.NONE);
                return generatePayload(x, y);
        }
    }

    private Payload[] getRandomPayloads(int x, int y, int amount){
            Payload[] out = new Payload[amount+1];
            Random random = new Random();
            for (int i = 0; i < amount; i++) {
                double xOffset = (x + random.nextDouble(0,1) - width  / 2) * pixelSize;
                double yOffset = (y + random.nextDouble(0,1) - height / 2) * pixelSize;
                Vector dir = right.mul(xOffset).add(up.mul(yOffset)).add(vpn);
                out[i] = new Payload( new Ray(pos, dir));
            }
            double xOffset = (x + 0.5 - width  / 2) * pixelSize;
            double yOffset = (y + 0.5 - height / 2) * pixelSize;
            Vector dir = right.mul(xOffset).add(up.mul(yOffset)).add(vpn);
            out[amount] = new Payload( new Ray(pos, dir));
            return out;
    }

    public void move(Vector dir){
        this.pos = pos.add(dir);
    }
    
    public void rotate(double x, double y){
        lookAt.add(new Vector(x, y, 0));
        calcVectors();
    }
    
    public int width() {return width;}
    public int height() {return height;}
    public Point pos() {return pos;}

    public void setSupersampling(SupersamplingMode mode){ this.supersampling = mode;}
    
}
