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

    public Vector dir() { return dir; }
    public Point origin() { return origin; }
    public double t() { return t; }
    public Geometry target() { return target; }

    public Point hitPoint(){
        return origin.add(dir.mul(t));
    }

    public void hit(Geometry target){
        this.target = target;
    }
    public void hit(double t){
        this.t = t;
    }
    public void hit(Geometry target, double t){
        this.target = target;
        this.t = t;
    }

    public double len(){ return dir.mag(); }

    public Ray clone(){
        return new Ray(origin,dir);
    }
}
