package math;

public class Color extends Tuple {
    public Color(double r, double g, double b){ 
        super(
            MUtils.normRGB(r),
            MUtils.normRGB(g),
            MUtils.normRGB(b),
            -1);
    }
    public Color(int r, int g, int b){ 
        super(
            MUtils.normRGB(r/255),
            MUtils.normRGB(g/255),
            MUtils.normRGB(b/255),
            -1);
    }

    public int rgb(){
        int res = 0;
        res += (int)(x*255) << 16;
        res += (int)(y*255) << 8;
        res += (int)(z*255);
        return res;
    }

    public Color mul(Color c){
        return new Color(r()*c.r(), g()*c.g(), b()*c.b());
    }

    public double r(){ return x; }
    public double g(){ return y; }
    public double b(){ return z; }
}
