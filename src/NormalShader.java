public class NormalShader implements Shader {

    @Override
    public Color getColor(Ray ray, Geometry geometry) {
        if(geometry.intersect(ray)){
            Vector v = geometry.normal(ray.hitPoint());
            return new Color(Math.abs(v.x()),Math.abs(v.y()),Math.abs(v.z()));
        }
        return null;
    }
        
    @Override
    public String getName() {
        return "NORMAL";
    }
}
