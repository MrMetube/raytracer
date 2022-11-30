package math;

public class Ray{
    Point origin;
    Vector dir;

    public Ray(Point origin, Vector dir) {
        this.origin = origin;
        this.dir = dir;
    }

    public Vector dir() { return dir; }
    public Point origin() { return origin; }
    public double len(){ return dir.mag(); }
}
