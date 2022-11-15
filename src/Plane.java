class Plane extends Geometry {
    Vector n;
    Point  p;
    double r = 0;
    static double DRAW_DISTANCE = 1000;

    public Plane(Vector normal, Point p) {
        this.n = normal;
        this.p = p;
    }
    public Plane(Vector normal, Point p, double r) {
        this.n = normal;
        this.p = p;
        this.r = r;
    }

    @Override
    boolean intersect(Ray ray) {
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

    @Override
    Vector normal(Point hit) {
        return n;
    }
   
}
