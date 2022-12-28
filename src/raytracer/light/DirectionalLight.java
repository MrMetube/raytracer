package raytracer.light;

import math.Color;
import math.Point;
import math.Vector;

public class DirectionalLight extends LightSource{
    Vector dir;

    public DirectionalLight(Vector dir, Color color, double intensity){
        this.dir = dir;
        this.color = color;
        this.intensity = intensity;
    }
 
    @Override public Vector directionFrom(Point p) { return dir.neg(); }
    @Override public double distanceFrom(Point p) { return Double.NaN; }
    @Override public Color colorAt(Point p) { return color.mul(intensity); }
    
}
