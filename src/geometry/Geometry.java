package geometry;

import math.Color;
import math.Point;
import math.Ray;
import math.Vector;
import scene.Material;

public abstract class Geometry {
    static final Material standardMaterial = new Material(new Color(255, 0, 255), 0, 1, 0, 0);
    public abstract boolean intersect(Ray ray);
    public abstract Vector normal(Point hit);
}
