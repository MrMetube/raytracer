package scene;

import math.Color;

public record Material(Color color, double ambient, double diffuse, double specular, int shininess, boolean isMetallic){
    public static Material DEFAULT = new Material(Color.MAGENTA, .2, 1, 0, 0, false);

    public static Material RED      = new Material(Color.RED,     .2, .9, .9, 10, false);
    public static Material GREEN    = new Material(Color.GREEN,   .2, .9, .9, 10, false);
    public static Material BLUE     = new Material(Color.BLUE,    .2, .9, .9, 10, false);
    public static Material CYAN     = new Material(Color.CYAN,    .2, .9, .9, 10, false);
    public static Material MAGENTA  = new Material(Color.MAGENTA, .2, .9, .9, 10, false);
    public static Material YELLOW   = new Material(Color.YELLOW,  .2, .9, .9, 10, false);
    public static Material WHITE    = new Material(Color.WHITE,   .2, .9, .9, 10, false);
    public static Material BLACK    = new Material(Color.BLACK,   .2, .9, .9, 10, false);
    public static Material GRAY     = new Material(Color.GRAY,    .2, .9, .9, 10, false);

    public static Material PINK     = new Material(Color.PINK  ,  .2, .9, .2, 10, false);
    public static Material ORANGE   = new Material(Color.ORANGE,  .2, .9, .2, 10, false);
    public static Material LEMON    = new Material(Color.LEMON ,  .2, .9, .2, 10, false);
    public static Material LIME     = new Material(Color.LIME  ,  .2, .9, .2, 10, false);
    public static Material AZURE    = new Material(Color.AZURE ,  .2, .9, .2, 10, false);
    public static Material PURPLE   = new Material(Color.PURPLE,  .2, .9, .2, 10, false);
    public static Material DARK     = new Material(Color.DARK  ,  .2, .9, .2, 10, false);
    public static Material LIGHT    = new Material(Color.LIGHT ,  .2, .9, .2, 10, false);
}
