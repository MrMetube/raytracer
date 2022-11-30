package raytracer.geometry;

import math.Point;
import math.Ray;
import math.Vector;

public abstract class Geometry {
    public static final String NO_MATERIAL = "NO_MATERIAL";
    String m;
    public String material(){ return m; }
    public void setMaterial(String material){ this.m = material; }
    public abstract boolean intersect(Ray ray);
    public abstract Vector normal(Point hit);
}
