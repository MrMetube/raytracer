package geometry;

import math.Point;
import math.Ray;
import math.Vector;

public abstract class Geometry {
    public abstract boolean intersect(Ray ray);
    public abstract Vector normal(Point hit);
}
