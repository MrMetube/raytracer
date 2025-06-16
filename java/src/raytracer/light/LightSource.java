package raytracer.light;

import math.Color;
import math.Point;
import math.Vector;

public abstract class LightSource {
    Color color;
    double intensity;

    public abstract Vector directionFrom(Point p);
    public abstract double distanceFrom(Point p);
    public abstract Color colorAt(Point p);
}
