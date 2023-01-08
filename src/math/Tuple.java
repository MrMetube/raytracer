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

    public Tuple add(Tuple t) { return new Tuple(x+t.x(), y+t.y(), z+t.z(), w+t.w()); }
    public Tuple sub(Tuple t) { return new Tuple(x-t.x(), y-t.y(), z-t.z(), w-t.w()); }
    public Tuple neg()        { return new Tuple(-x,-y,-z,-w); }

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
        return  Util.approxEqual(this.x, that.x(), 0.0001) &&
                Util.approxEqual(this.y, that.y(), 0.0001) &&
                Util.approxEqual(this.z, that.z(), 0.0001) &&
                Util.approxEqual(this.w, that.w(), 0.0001);
    }

    @Override
    public String toString(){ return String.format("(%.02f | %.02f | %.02f | %.02f)",x,y,z,w); }
}
