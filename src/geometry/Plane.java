package geometry;

import math.Point;
import math.Ray;
import math.Vector;

public class Plane extends Geometry{
    Vector n;
    Point  p;
    double r;
    
    static double DRAW_DISTANCE = Double.POSITIVE_INFINITY;

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

    @Override public boolean intersect(Ray ray) {
        Point  o = ray.origin();
        Vector d = ray.dir();
        double t = n.dot(p.sub(o)) / n.dot(d);
        if( t>0 && (
            r != 0 && p.sub(o.add(d.mul(t))).mag() < r ||
            r == 0 && p.sub(o.add(d.mul(t))).mag() < DRAW_DISTANCE )){
            ray.hit(this,t);
            return true;
        }
        return false;
    }

    @Override public Vector normal(Point hit) { return n.norm(); } 
}
