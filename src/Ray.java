class Ray{
    Point origin;
    Vector dir;
    double t;
    Object target;
    public Ray(Point origin, Vector dir) {
        this.origin = origin;
        this.dir = dir;
    }

    Vector dir() { return dir; }
    Point origin() { return origin; }
    double t() { return t; }
    void hit(Object target){
        this.target = target;
    }
    void hit(double t){
        this.t = t;
    }
    void hit(Object target, double t){
        this.target = target;
        this.t = t;
    }

    double len(){ return dir.mag(); }
    Ray norm(){return new Ray(origin, dir.norm());}
}
