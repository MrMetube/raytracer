package raytracer.geometry;

import math.Point;
import math.Util;
import math.Vector;
import raytracer.Payload;

public class Triangle extends Geometry{
    Point a,b,c;
    boolean isSingleSided = true;

    public Triangle(Point a, Point b, Point c, String material) {
        this.a = a;
        this.b = b;
        this.c = c;
        m = material;
    }

    public Triangle(Point a, Point b, Point c, boolean isSingleSided, String material) {
        this.a = a;
        this.b = b;
        this.c = c;
        this.isSingleSided = isSingleSided;
        m = material;
    }

    @Override
    public boolean intersect(Payload payload) {
        var ray = payload.ray();
        var dir = ray.dir();
        var origin = ray.origin();

        var e0 = b.sub(a);
        var e1 = c.sub(a);
        var n = e0.cross(e1);

        if(isSingleSided && dir.dot(n) > 0) return false;

        var ab = a.sub(b);
        var ac = a.sub(c);
        var normal = ab.cross(ac);
        // double denom = normal.dot(normal);
        // double area = normal.mag();


        // check if the ray is parallel
        double nRayDir = normal.dot(dir);
        if(Util.approxEqual(nRayDir, 0)) return false;

        //check if the triangle is behind the ray
        double d = -normal.dot(a);
        double t = -(normal.dot(origin)+d) / nRayDir;
        if(t<0) return false;

        var p = origin.add(dir.mul(t));

        Vector cross;
        // edge 1
        cross =  b.sub(a).cross(p.sub(a));
        if(normal.dot(cross)<0) return false;

        // edge 2
        cross = c.sub(b).cross(p.sub(b));
        var u = normal.dot(cross);
        if(u<0) return false;

        // edge 3
        cross = a.sub(c).cross(p.sub(c));
        var v = normal.dot(cross);
        if(v<0) return false;

        // iterpolate between the colors at each vertex with these
        // need to remake the color and material
        // u /= denom;
        // v /= denom;

        payload.hit(this, t);
        return true;
    }

    @Override
    public Vector normal(Point hit) {
        var ab = a.sub(b);
        var ac = a.sub(c);

        return ab.cross(ac).norm();
    }
    
}
