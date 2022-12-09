package math;

public class Tuple {
    protected final double x;
    protected final double y;
    protected final double z;
    protected final double w;

    public Tuple(double x, double y, double z, double w){
        this.x = x;
        this.y = y;
        this.z = z;
        this.w = w;
    }

    public Tuple add(Tuple... tups){
        Tuple sum = new Tuple(x,y,z,w);
        for (Tuple t : tups) sum = new Tuple(
            sum.x()+t.x(), 
            sum.y()+t.y(), 
            sum.z()+t.z(), 
            sum.w()+t.w()
        );
        return sum;
    }
    public Tuple sub(Tuple... tups){
        Tuple dif = new Tuple(x,y,z,w);
        for (Tuple t : tups) dif = new Tuple(
            dif.x()-t.x(), 
            dif.y()-t.y(), 
            dif.z()-t.z(), 
            dif.w()-t.w()
        );
        return dif;
    }
    public Tuple neg(){ return new Tuple(0,0,0,0).sub(this); }

    public Tuple mul(double scl){ return new Tuple(x*scl, y*scl, z*scl, w*scl); }
    public Tuple div(double scl){ return new Tuple(x/scl, y/scl, z/scl, w/scl); }

    public double dot(Tuple t){ return x*t.x() + y*t.y() + z*t.z() + w*t.w(); }
    
    public double mag(){ return Math.sqrt( x*x + y*y + z*z + w*w ); }

    public Tuple norm(){ 
        double mag = this.mag();
        return new Tuple(x/mag, y/mag, z/mag, w/mag);
    }

    public double x() { return x; }
    public double y() { return y; }
    public double z() { return z; }
    public double w() { return w; }

    @Override
    public boolean equals(Object o){
        if(o == null) return false;
        if(o == this) return true;
        final Tuple that = (Tuple) o;
        return  MUtils.approxEqual(this.x, that.x(), 0.0001) &&
                MUtils.approxEqual(this.y, that.y(), 0.0001) &&
                MUtils.approxEqual(this.z, that.z(), 0.0001) &&
                MUtils.approxEqual(this.w, that.w(), 0.0001);
    }

    @Override
    public String toString(){ return String.format("(%.02f | %.02f | %.02f | %.02f)",x,y,z,w); }
}
