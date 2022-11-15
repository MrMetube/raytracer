package math;

public class Ray{
    Point origin;
    Vector dir;
    double t = Double.MAX_VALUE;
    Object target;
    public Ray(Point origin, Vector dir) {
        this.origin = origin;
        this.dir = dir;
    }

    public Vector dir() { return dir; }
    public Point origin() { return origin; }
    public double t() { return t; }

    public Point hitPoint(){
        Vector v = dir.mul(t);
        return origin.add(v);
    }

    public void hit(Object target){
        this.target = target;
    }
    public void hit(double t){
        this.t = t;
    }
    public void hit(Object target, double t){
        this.target = target;
        this.t = t;
    }

    public double len(){ return dir.mag(); }
}
