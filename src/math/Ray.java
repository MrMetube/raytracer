package math;

import geometry.Geometry;

public class Ray{
    Point origin;
    Vector dir;
    double t = Double.MAX_VALUE;
    Geometry target;

    public Ray(Point origin, Vector dir) {
        this.origin = origin;
        this.dir = dir;
    }

    public Ray(Ray ray){
        this.dir = ray.dir();
        this.origin = ray.origin();
    }

    public Vector dir() { return dir; }
    public Point origin() { return origin; }
    public double t() { return t; }
    public Geometry target() { return target; }

    public Point hitPoint(){
        return origin.add(dir.mul(t));
    }

    public void hit(Geometry target, double t){
        if( this.t>t && t > 0)
            this.target = target;
            this.t = t;
    }

    public double len(){ return dir.mag(); }
}
