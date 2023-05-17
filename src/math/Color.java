package math;

public class Color extends Tuple {
    //#region Constants
    public static final Color RED     = new Color(1, 0, 0);
    public static final Color GREEN   = new Color(0, 1, 0);
    public static final Color BLUE    = new Color(0, 0, 1);
    public static final Color YELLOW  = new Color(1, 1, 0);
    public static final Color CYAN    = new Color(0, 1, 1);
    public static final Color MAGENTA = new Color(1, 0, 1);
    public static final Color WHITE   = new Color(1, 1, 1);
    public static final Color BLACK   = new Color(0, 0, 0);
    public static final Color GRAY    = new Color(.5, .5, .5);

    public static final Color PINK      = new Color(0.98, 0.4, 0.53);
    public static final Color ORANGE    = new Color(0.97, 0.62, 0.42);
    public static final Color LEMON     = new Color(0.98, 0.86, 0.42);
    public static final Color LIME      = new Color(0.65, 0.87, 0.47);
    public static final Color TURQUOISE = new Color(0.51, 0.85, 0.91);
    public static final Color PURPLE    = new Color(0.69, 0.6, 0.94);
    public static final Color DARK      = new Color(0.17, 0.16, 0.18);
    public static final Color LIGHT     = new Color(0.99, 0.98, 0.95);

    public static final Color GOLD    = new Color(1,    0.84,   0);
    public static final Color SILVER  = new Color(0.51, 0.54,   0.59);
    public static final Color BRONZE  = new Color(0.72, 0.45,   0.2);
    public static final Color COPPER  = new Color(0.8,  0.5,    0.2);
    //#endregion
    
    public Color(double r, double g, double b){ 
        super(r,g,b,-1);
    }
    public Color(int argb){
        super(
            ((argb & 0b00000000_11111111_00000000_00000000)>>16) / 255f,
            ((argb & 0b00000000_00000000_11111111_00000000)>>8 ) / 255f,
            ((argb & 0b00000000_00000000_00000000_11111111)    ) / 255f,
            -1
        );
    }

    public int rgb(){
        return (int) (Util.clamp(x, 0, 1)*255)<<16 | (int) (Util.clamp(y, 0, 1)*255)<<8 | (int) (Util.clamp(z, 0, 1)*255);
    }

    public Color mul(Color c)   { return new Color(r()*c.r(),   g()*c.g(),  b()*c.b()); }
    public Color mul(double scl){ return new Color(r()*scl,     g()*scl,    b()*scl);   }
    public Color div(double scl){ return new Color(r()/scl,     g()/scl,    b()/scl);   }

    public Color add(Color c){ return new Color(r()+c.r(), g()+c.g(), b()+c.b()); }

    public Color norm(){
        double mag = this.mag();
        return new Color(x/mag, y/mag, z/mag);
    }

    public double r(){ return x; }
    public double g(){ return y; }
    public double b(){ return z; }

    @Override
    public String toString(){ return String.format("(%.2f | %.2f | %.2f)",x,y,z); }

    @Override
    public boolean equals(Object o){
        if(o == null) return false;
        if(o == this) return true;
        final Tuple that = (Tuple) o;
        return  Util.approxEqual(this.x, that.x(), 0.01) &&
                Util.approxEqual(this.y, that.y(), 0.01) &&
                Util.approxEqual(this.z, that.z(), 0.01) &&
                Util.approxEqual(this.w, that.w(), 0.01);
    }
}
