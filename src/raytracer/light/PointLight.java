package raytracer.light;

import math.Color;
import math.Point;
import math.Vector;

public class PointLight extends LightSource{
    Point pos;

    public PointLight(Point pos, Color color, double intensity){
        this.pos = pos;
        this.color = color;
        this.intensity = intensity;
    }

    @Override public boolean isDirectional() { return false;}
    @Override public Vector directionFrom(Point p) { return pos.sub(p); }
    @Override public double distanceFrom(Point p) { return pos.sub(p).mag(); }
    @Override public Color colorAt(Point p) { return color.mul(intensity).div(distanceFrom(p)*distanceFrom(p)); }
}
