package math;

public class Color extends Tuple {
    public static Color RED     = new Color(1, 0, 0);
    public static Color GREEN   = new Color(0, 1, 0);
    public static Color BLUE    = new Color(0, 0, 1);
    public static Color YELLOW  = new Color(1, 1, 0);
    public static Color CYAN    = new Color(0, 1, 1);
    public static Color MAGENTA = new Color(1, 0, 1);
    public static Color WHITE   = new Color(1, 1, 1);
    public static Color BLACK   = new Color(0, 0, 0);
    public static Color GRAY    = new Color(.5, .5, .5);

    public Color(double r, double g, double b){ 
        super(r,g,b,-1);
    }

    public int rgb(){
        int res = 0;
        res += (int)(Math.min(1,Math.max(0,x))*255) << 16;
        res += (int)(Math.min(1,Math.max(0,y))*255) << 8;
        res += (int)(Math.min(1,Math.max(0,z))*255);
        return res;
    }

    public Color mul(Color c){
        return new Color(r()*c.r(), g()*c.g(), b()*c.b());
    }
    public Color mul(double scl){
        return new Color(r()*scl, g()*scl, b()*scl);
    }

    public Color add(Color... colors){
        Color sum = new Color(r(),g(),b());
        for (Color c : colors) sum = new Color(sum.r()+c.r(), sum.g()+c.g(), sum.b()+c.b());
        return sum;
    }

    public Color norm(){
        double mag = this.mag();
        return new Color(x/mag, y/mag, z/mag);
    }

    public double r(){ return x; }
    public double g(){ return y; }
    public double b(){ return z; }

    @Override
    public String toString(){ return String.format("(%.02f | %.02f | %.02f)",x,y,z); }
}
