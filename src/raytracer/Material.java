package raytracer;

import math.Color;

public record Material(Color color, double ambient, double diffuse, double specular, int shininess, double reflectivity, boolean isMetallic){
    public static Material DEFAULT   = new Material(Color.MAGENTA, .2,  1,  0,  0,  .0, false);

    public static Material RED       = new Material(Color.RED       , .2, .9, .9,  10, .05, false);
    public static Material GREEN     = new Material(Color.GREEN     , .2, .9, .9,  10, .05, false);
    public static Material BLUE      = new Material(Color.BLUE      , .2, .9, .9,  10, .05, false);
    public static Material CYAN      = new Material(Color.CYAN      , .2, .9, .9,  10, .05, false);
    public static Material MAGENTA   = new Material(Color.MAGENTA   , .2, .9, .9,  10, .05, false);
    public static Material YELLOW    = new Material(Color.YELLOW    , .2, .9, .9,  10, .05, false);
    public static Material WHITE     = new Material(Color.WHITE     , .2, .9, .9,  10, .05, false);
    public static Material BLACK     = new Material(Color.BLACK     , .2, .9, .9,  10, .05, false);
    public static Material GRAY      = new Material(Color.GRAY      , .2, .9, .9,  10, .05, false);

    public static Material PINK      = new Material(Color.PINK      , .2, .9, .1,   0, .01, false);
    public static Material ORANGE    = new Material(Color.ORANGE    , .2, .9, .1,   0, .01, false);
    public static Material LEMON     = new Material(Color.LEMON     , .2, .9, .1,   0, .01, false);
    public static Material LIME      = new Material(Color.LIME      , .2, .9, .1,   0, .01, false);
    public static Material TURQUOISE = new Material(Color.TURQUOISE , .2, .9, .1,   0, .01, false);
    public static Material PURPLE    = new Material(Color.PURPLE    , .2, .9, .1,   0, .01, false);
    public static Material DARK      = new Material(Color.DARK      , .2, .9, .1,   0, .01, false);
    public static Material LIGHT     = new Material(Color.LIGHT     , .2, .9, .1,   0, .01, false);

    public static Material GOLD      = new Material(Color.GOLD      , .2, .9, .9, 200,  .9,  true);
    public static Material SILVER    = new Material(Color.SILVER    , .2, .9, .9, 200,  .9,  true);
    public static Material BRONZE    = new Material(Color.BRONZE    , .2, .9, .9, 200,  .9,  true);
    public static Material COPPER    = new Material(Color.COPPER    , .2, .9, .9, 200,  .9,  true);
}
