class Sphere {
    final Point c;    //center
    final double r;   //radius
    
    Sphere(Point p, double r) {
        this.c = p;
        this.r = r;
    }
    
    boolean intersect(Ray ray){
        Vector dir = ray.dir();
        
        Vector L = ray.origin.sub(c);
        double a = dir.dot(dir);
        double b = 2 * dir.dot(L);
        double c = L.dot(L) - r*r;
        if(!MUtils.solveQuadratic(a,b,c,ray)) return false;
        if(ray.t() < 0) return false;
        ray.hit(this);
        return true;
    }
}
