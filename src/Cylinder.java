class Cylinder extends Geometry{
    double rad;
    Vector norm;
    Point cent;
    
    public Cylinder(double rad, Point cent, Vector norm) {
        this.rad = rad;
        this.norm = norm;
        this.cent = cent;
    }

    boolean intersect(Ray ray) {
        Vector dir = ray.dir();
        
        Vector L = ray.origin.sub(cent);
        double a = dir.dot(dir);
        double b = 2 * dir.dot(L);
        double c = L.dot(L) - rad*rad;
        
        
        
        if(!MUtils.solveQuadratic(a,b,c,ray)) return false;
        if(ray.t() < 0) return false;
        ray.hit(this);
        return true;
    }

    Vector normal(Point hit) {
        Vector v = cent.sub(hit);
        return new Vector(rad, rad, rad);
    }
}
