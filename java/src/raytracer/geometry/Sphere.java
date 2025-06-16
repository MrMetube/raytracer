package raytracer.geometry;

import math.Util;
import math.Point;
import math.Ray;
import math.Vector;
import raytracer.Payload;

public class Sphere extends Geometry{
    final Point c;    //center
    final double r;   //radius
    
    public static Sphere UNIT = new Sphere(Point.zero, 1);

    public Sphere(Point p, double r) {
        this.c = p;
        this.r = r;
        this.m = NO_MATERIAL;
    }

    public Sphere(Point p, double r, String m) {
        this.c = p;
        this.r = r;
        this.m = m;
    }

    @Override public boolean intersect(Payload payload){
        Ray ray  = payload.ray();
        Vector dir = ray.dir();
        Vector L = ray.origin().sub(c);
        double a = dir.dot(dir);
        double b = 2 * dir.dot(L);
        double c = L.dot(L) - r*r;
        return Util.solveQuadratic(a,b,c,payload,this);
    }
    
    @Override public Vector normal(Point hit){
        return hit.sub(c).norm();
    }
}
