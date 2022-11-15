class NormalShader implements Shader {

    @Override
    public Color getColor(int x, int y, int size, Geometry geometry) {
        Ray r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
        if(geometry.intersect(r)){
            Vector v = geometry.normal(r.hitPoint());
            return new Color(Math.abs(v.x()),Math.abs(v.y()),Math.abs(v.z()));
        }
        return null;
    }
        
    @Override
    public String getName() {
        return "NORMAL";
    }
}
