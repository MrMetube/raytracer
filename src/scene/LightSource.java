package scene;

import math.Color;
import math.Point;

public abstract class LightSource {
    Point pos;
    Color color;
    double intensity;

    public Point pos()        { return pos; }
    public Color color()      { return color; }
    public double intensity() { return intensity; }
}
