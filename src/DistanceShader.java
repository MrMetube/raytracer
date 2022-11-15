public class DistanceShader implements Shader{

    @Override
    public Color getColor(int x, int y, int size, Geometry geometry) {
        Ray r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
        double dis = r.dir().mag();
        return  geometry.intersect(r) ? new Color(dis,dis,dis) : null;    
    }

    @Override
    public String getName() {
        return "DISTANCE";
    }
    
}
