package raytracer;

import java.util.HashSet;

import gui.App;
import math.Point;
import math.Ray;
import math.Vector;
import raytracer.stuff.Move;
import raytracer.stuff.Supersampling;
import raytracer.stuff.Turn;

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

    Supersampling supersampling = Supersampling.NONE;

    double moveSpeed = 0.7;
    double turnSpeed = 5;

    public Camera(Point pos, Point lookAt, double fovDeg, App app) {
        this.pos = pos;
        this.lookAt = lookAt;
        fov = Math.toRadians(fovDeg);
        width = app.getWidth();
        height = app.getHeight();

        double aspectRatio = width/height;
        double halfHeight = Math.tan(fov/2);
        pixelSize = (aspectRatio < 1 ? halfHeight : halfHeight/aspectRatio) * 2/height ;

        calcVectors();
    }

    public Camera(Camera orig){
        this.pos = orig.pos.add(Vector.ZERO);
        this.lookAt = orig.lookAt.add(Vector.ZERO);
        this.fov = orig.fov;
        width  = orig.width;
        height = orig.height;
        
        supersampling = orig.supersampling; 

        double aspectRatio = width/height;
        double halfHeight = Math.tan(fov/2);
        pixelSize = (aspectRatio < 1 ? halfHeight : halfHeight/aspectRatio) * 2/height ;

        calcVectors();
    }

    private void calcVectors(){
        vpn = lookAt.sub(pos).norm();
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
                supersampling = Supersampling.NONE;
                break;
        }
        return out;
    }

    public void move(HashSet<Move> moves){
        //This doesnt work when the cam is not looking directly forward
        Vector dir = Vector.ZERO;
        if(moves.contains(Move.FORWARD))
            dir = dir.add(vpn);
        if(moves.contains(Move.BACKWARD))
            dir = dir.add(vpn.neg());
        if(moves.contains(Move.LEFT))
            dir = dir.add(right.neg());
        if(moves.contains(Move.RIGHT))
            dir = dir.add(right);
        if(moves.contains(Move.UP))
            dir = dir.add(up);
        if(moves.contains(Move.DOWN))
            dir = dir.add(up.neg());

        dir = dir.mul(moveSpeed);
        pos = pos.add(dir);
        lookAt = lookAt.add(dir);
        calcVectors();
    }
    
    public void rotate(HashSet<Turn> turns){
        int rotX = 0, rotY = 0;
        if(turns.contains(Turn.UP))     rotX += turnSpeed;
        if(turns.contains(Turn.DOWN))   rotX -= turnSpeed;
        if(turns.contains(Turn.LEFT))   rotY -= turnSpeed;
        if(turns.contains(Turn.RIGHT))  rotY += turnSpeed;
        rotate(rotX, rotY);
    }

    public void rotate(double angleX, double angleY){
        Vector dir = vpn.rotate(angleX, right).add(vpn.rotate(angleY, up)).norm();
        lookAt = pos.add(dir);
        calcVectors();
    }
    
    public Point pos() {return pos;}
    public void setSupersampling(Supersampling mode){supersampling = mode;}
}
