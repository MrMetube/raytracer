package shader;

import geometry.Geometry;
import math.Color;
import math.Ray;

public interface Shader {
    Color getColor(Ray ray, Geometry geometry);
    String getName();
}
