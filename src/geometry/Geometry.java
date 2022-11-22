package geometry;

import math.Point;
import math.Ray;
import math.Vector;

public abstract class Geometry {
    public static final String NO_MATERIAL = "NO_MATERIAL";
    
    public abstract String material();
    public abstract boolean intersect(Ray ray);
    public abstract Vector normal(Point hit);
}
