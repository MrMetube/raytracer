public class DistanceShader implements Shader{

    @Override
    public Color getColor(Ray ray, Geometry geometry) {
        double dis = ray.dir().mag();
        return  geometry.intersect(ray) ? new Color(dis,dis,dis) : null;    
    }

    @Override
    public String getName() {
        return "DISTANCE";
    }
    
}
