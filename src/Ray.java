class Ray{
    Point origin;
    Vector dir;
    public Ray(Point origin, Vector dir) {
        this.origin = origin;
        this.dir = dir;
    }
    double len(){ return dir.mag(); }
    Ray norm(){return new Ray(origin, dir.norm());}
}
