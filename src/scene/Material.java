package scene;

import math.Color;

public final class Material {
    private final Color color;
    private final double ambient;
    private final double diffuse;
    private final double specular;
    private final int shininess;
    private final boolean isMetalic;

    public Material(Color color, double ambient, double diffuse, double specular, int shininess, boolean isMetalic) {
        this.color = color;
        this.ambient = ambient;
        this.diffuse = diffuse;
        this.specular = specular;
        this.shininess = shininess;
        this.isMetalic = isMetalic;
    }

    public Color color() { return color; }
    public double ambient() { return ambient; }
    public double diffuse() { return diffuse; }
    public double specular() { return specular; }
    public int shininess() { return shininess; }
    public boolean isMetalic() { return isMetalic; }
}
