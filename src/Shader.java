interface Shader {
    Color getColor(int x, int y, int size, Geometry geometry);
    String getName();
}
