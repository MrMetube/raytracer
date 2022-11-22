package scene;

import math.Color;

public final class Material {
    private final Color color;
    private final double ambient;
    private final double diffuse;
    private final double specular;
    private final int shininess;

    public Material(Color color, double ambient, double diffuse, double specular, int shininess) {
        this.color = color;
        this.ambient = ambient;
        this.diffuse = diffuse;
        this.specular = specular;
        this.shininess = shininess;
    }

    public Color getColor() { return color; }
    public double getAmbient() { return ambient; }
    public double getDiffuse() { return diffuse; }
    public double getSpecular() { return specular; }
    public int getShininess() { return shininess; }
}
