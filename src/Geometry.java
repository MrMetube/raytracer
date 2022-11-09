abstract class Geometry {
    abstract boolean intersect(Ray ray);
    abstract Vector normal(Point hit);
}
