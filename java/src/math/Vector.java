package math;
public class Vector extends Tuple{

    public static Vector Ypos  = new Vector(0,1,0);
    public static Vector Yneg  = new Vector(0,-1,0);
    public static Vector Xpos  = new Vector(1,0,0);
    public static Vector Xneg  = new Vector(-1,0,0);
    public static Vector Zpos  = new Vector(0,0,1);
    public static Vector Zneg  = new Vector(0,0,-1);
    public static Vector zero  = new Vector(0,0,0);

    public Vector(double x, double y, double z){ super(x,y,z,0); }

    public Vector add(double a)  { return new Vector(x+a, y+a, z+a); }
    public Vector add(Vector v)  { return new Vector(x+v.x(), y+v.y(), z+v.z() ); }
    public Vector sub(Vector v)  { return new Vector(x-v.x(), y-v.y(), z-v.z()); }

    public Vector cross(Vector v) { return new Vector( y*v.z() - z*v.y(), z*v.x() - x*v.z(), x*v.y() - y*v.x()); }
    public Vector mul(double s)   { return new Vector(x*s, y*s, z*s);}
    public Vector div(double s)   { return new Vector(x/s, y/s, z/s);}
    public Vector neg()           { return new Vector(-x, -y, -z);}

    public Vector norm() {
        double mag = this.mag();
        return new Vector(x/mag, y/mag, z/mag);
    }

    public Vector refl(Vector normal){
        Vector n = normal.norm();
        return sub(n.mul(2*this.dot(n)));
    }

    public Vector rotate(double angle, Vector axis){
        double sinHalfAngle = Math.sin(Math.toRadians(angle/2));
        double cosHalfAngle = Math.cos(Math.toRadians(angle/2));

        double rX = axis.x() * sinHalfAngle;
        double rY = axis.y() * sinHalfAngle;
        double rZ = axis.z() * sinHalfAngle;
        double rW = cosHalfAngle;

        Quaternion rot = new Quaternion(rX, rY, rZ, rW);
        Quaternion con = rot.con();

        Quaternion q = rot.mul(this).mul(con);

        return new Vector(q.x(), q.y(), q.z());
    }

    @Override
    public String toString(){ return String.format("(%.02f | %.02f | %.02f)",x,y,z); }
}
