package raytracer;

import math.Color;
import math.Point;
import math.Ray;
import raytracer.geometry.Geometry;

public class Payload{
    Geometry target;
    double t = Double.MAX_VALUE;
    Ray ray;
    Color color;
    Ray reflection;
    double reflectStrength = 1;

    public Payload(Ray ray){
        this.ray = ray;
    }

    public void hit(Geometry target, double t){
        if(this.t > t){
            this.target = target;
            this.t = t;
        }
    }
    public Point hitPoint(){ return ray.origin().add(ray.dir().mul(t)); }

    public Geometry target() { return target; }
    public double t() { return t;}
    public Ray ray() { return ray;}
    public Color color(){ return color; }
    public Ray reflection() { return reflection;}
    public double reflectStrength() { return reflectStrength;}

    public void setReflection(Ray ray, double r){ 
        reflection = ray; 
        reflectStrength = r;
    }
    public void setColor(Color c){ color = c;}
}
