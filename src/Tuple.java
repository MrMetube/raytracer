public class Tuple {
    final double x;
    final double y;
    final double z;
    final double w;

    Tuple(double x, double y, double z, double w){
        this.x = x;
        this.y = y;
        this.z = z;
        this.w = w;
    }

    Tuple add(Tuple... tups){
        Tuple sum = new Tuple(x,y,z,w);
        for (Tuple t : tups) sum = new Tuple(sum.x()+t.x(), sum.y+t.y(), sum.z()+t.z(), sum.w()+t.w());
        return sum;
    }
    Tuple sub(Tuple... tups){
        Tuple dif = new Tuple(x,y,z,w);
        for (Tuple t : tups) dif = new Tuple(dif.x()-t.x(), dif.y()-t.y(), dif.z()-t.z(), dif.w()-t.w());
        return dif;
    }
    Tuple neg(){ return new Tuple(0,0,0,0).sub(this); }

    Tuple mul(double scl){ return new Tuple(x*scl, y*scl, z*scl, w*scl); }
    Tuple div(double scl){ return new Tuple(x/scl, y/scl, z/scl, w/scl); }

    double dot(Tuple t){ return x*t.x() + y*t.y() + z*t.z() + w*t.w(); }
    
    double mag(){ return Math.sqrt( x*x + y*y + z*z + w*w ); }

    Tuple norm(){ 
        double mag = this.mag();
        return new Tuple(x/mag, y/mag, z/mag, w/mag);
    }

    double x() { return x; }
    double y() { return y; }
    double z() { return z; }
    double w() { return w; }

    @Override
    public boolean equals(Object o){
        if(o == null) return false;
        if(o == this) return true;
        final Tuple that = (Tuple) o;
        return MUtils.approxEqual(this.x, that.x()) &&
                MUtils.approxEqual(this.y, that.y()) &&
                MUtils.approxEqual(this.z, that.z()) &&
                MUtils.approxEqual(this.w, that.w());
    }

    @Override
    public String toString(){ return String.format("(%.02f, %.02f, %.02f, %.02f)",x,y,z,w); }
}
