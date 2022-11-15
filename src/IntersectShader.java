public class IntersectShader implements Shader{

    @Override
    public Color getColor(int x, int y, int size, Geometry geometry) {
        Ray r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
        return geometry.intersect(r) ? new Color(50, 51, 68) : null;
    }
    
    @Override
    public String getName() {
        return "INTERSECT";
    }
}
