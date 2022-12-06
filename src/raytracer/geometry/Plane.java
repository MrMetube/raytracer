package raytracer.geometry;

import math.Point;
import math.Ray;
import math.Vector;
import raytracer.Payload;

public class Plane extends Geometry{
    Vector n;
    Point  p;
    double r;
    
    static double DRAW_DISTANCE = 10000;

    public Plane(Vector normal, Point p) {
        this.n = normal.norm();
        this.p = p;
        this.r = 0;
        this.m = NO_MATERIAL;
    }
    public Plane(Vector normal, Point p, String m) {
        this.n = normal.norm();
        this.p = p;
        this.r = 0;
        this.m = m;
    }
    public Plane(Vector normal, Point p, double r, String m) {
        this.n = normal.norm();
        this.p = p;
        this.r = r;
        this.m = m;
    }

    @Override public boolean intersect(Payload payload) {
        Ray ray  = payload.ray();
        Point  o = ray.origin();
        Vector d = ray.dir();
        double t = n.dot(p.sub(o)) / n.dot(d);
        double l = p.sub(o.add(d.mul(t))).mag();
        if( t>0 && ( r!=0 && l < r || r==0 && l < DRAW_DISTANCE)){
            payload.hit(this,t);
            return true;
        }
        return false;
    }

    @Override public Vector normal(Point hit) { return n; } 
}
