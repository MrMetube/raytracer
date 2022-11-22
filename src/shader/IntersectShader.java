package shader;

import geometry.Geometry;
import math.Color;
import math.Ray;

public class IntersectShader implements Shader{

    @Override
    public Color getColor(Ray ray, Geometry geometry) {
        return geometry.intersect(ray) ? new Color(0.19, 0.2, 0.26) : null;
    }
    
    @Override
    public String getName() {
        return "Intersect";
    }
}
