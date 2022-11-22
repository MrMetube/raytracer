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
        res += (int)(x*255) << 16;
        res += (int)(y*255) << 8;
        res += (int)(z*255);
        return res;
    }

    public Color mul(Color c){
        return new Color(r()*c.r(), g()*c.g(), b()*c.b());
    }
    public Color mul(double scl){
        return new Color(r()*scl, g()*scl, b()*scl);
    }

    public Color add(Color c){
        return new Color(
            Math.min(1, r()+c.r()) , 
            Math.min(1, g()+c.g()) , 
            Math.min(1, b()+c.b()) );
    }

    public double r(){ return x; }
    public double g(){ return y; }
    public double b(){ return z; }
}
