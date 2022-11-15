package math;

public class Color extends Tuple {
    public Color(double r, double g, double b){ 
        super(
            MUtils.normRGB(r),
            MUtils.normRGB(g),
            MUtils.normRGB(b),
            -1);
    }

    public int rgb(){
        int res = 0;
        res += (int)x << 16;
        res += (int)y << 8;
        res += (int)z;
        return res;
    }

    public Color mul(Color c){
        return new Color(r() * c.r()/255,g() * c.g()/255,b() *c.b()/255);
    }

    public double r(){ return x; }
    public double g(){ return y; }
    public double b(){ return z; }
}
