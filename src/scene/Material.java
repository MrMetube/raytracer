package scene;

import math.Color;

public record Material(Color color, double ambient, double diffuse, double specular, int shininess, boolean isMetallic){
    public static Material DEFAULT = new Material(Color.MAGENTA, .2, 1, 0, 0, false);

    public static Material RED      = new Material(Color.RED,     .2, .9, .9, 100, false);
    public static Material GREEN    = new Material(Color.GREEN,   .2, .9, .9, 100, false);
    public static Material BLUE     = new Material(Color.BLUE,    .2, .9, .9, 100, false);
    public static Material CYAN     = new Material(Color.CYAN,    .2, .9, .9, 100, false);
    public static Material MAGENTA  = new Material(Color.MAGENTA, .2, .9, .9, 100, false);
    public static Material YELLOW   = new Material(Color.YELLOW,  .2, .9, .9, 100, false);
    public static Material WHITE    = new Material(Color.WHITE,   .2, .9, .9, 100, false);
    public static Material BLACK    = new Material(Color.BLACK,   .2, .9, .9, 100, false);
    public static Material GRAY     = new Material(Color.GRAY,   .2, .9, .9, 100, false);
}
