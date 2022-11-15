interface Shader {
    Color getColor(Ray ray, Geometry geometry);
    String getName();
}
