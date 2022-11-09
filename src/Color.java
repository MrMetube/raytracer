class Color extends Tuple {
    Color(double r, double g, double b){ 
        super(
            MUtils.normRGB(r),
            MUtils.normRGB(g),
            MUtils.normRGB(b),
            -1);
    }

    int rgb(){
        int res = 0;
        res += (int)x << 16;
        res += (int)y << 8;
        res += (int)z;
        return res;
    }

    Color mul(Color c){
        return new Color(r() * c.r()/255,g() * c.g()/255,b() *c.b()/255);
    }

    double r(){ return x; }
    double g(){ return y; }
    double b(){ return z; }
}
