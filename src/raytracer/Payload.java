package raytracer;

import math.Point;
import math.Ray;
import raytracer.geometry.Geometry;

public class Payload{
    Geometry target;
    double t = Double.MAX_VALUE;
    Ray ray;

    public Payload(Ray ray){
        this.ray = ray;
    }

    public Geometry target() { return target; }
    public double t() { return t;}
    public Ray ray() { return ray;}

    public void hit(Geometry target, double t){
        if(this.t > t){
            this.target = target;
            this.t = t;
        }
    }
    public Point hitPoint(){
        return ray.origin().add(ray.dir().mul(t));
    }
    
}
