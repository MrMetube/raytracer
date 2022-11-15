public class IntersectShader implements Shader{

    @Override
    public Color getColor(Ray ray, Geometry geometry) {
        return geometry.intersect(ray) ? new Color(50, 51, 68) : null;
    }
    
    @Override
    public String getName() {
        return "INTERSECT";
    }
}
