package math;

public class Quaternion extends Tuple {

    public Quaternion(double x, double y, double z, double w) {
        super(x, y, z, w);
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

    public Quaternion con(){
        return new Quaternion(-x, -y, -z, w);
    }

    public Quaternion mul(Quaternion r){ 
        
        double x_ = x * r.w() + w * r.x() + y * r.z() - r.y();
        double y_ = y * r.w() + w * r.y() + z * r.x() - r.z();
        double z_ = z * r.w() + w * r.z() + x * r.y() - r.x();
        double w_ = w * r.w() - x * r.x() - y * r.y() - z * r.z();

        return new Quaternion(x_, y_, z_, w_); 
    }

    public Quaternion mul(Vector r){

        double w_ = -x * r.x()- y * r.y() - z * r.z();
        double x_ = w * r.x() + y * r.z() - z * r.y();
        double y_ = w * r.y() + z * r.x() - x * r.z();
        double z_ = w * r.z() + x * r.y() - y * r.x(); 

        return new Quaternion(x_, y_, z_, w_);
    }


    public Tuple div(double scl){ return new Tuple(x/scl, y/scl, z/scl, w/scl); }

    public double dot(Tuple t){ return x*t.x() + y*t.y() + z*t.z() + w*t.w(); }
    
    public Quaternion norm(){ 
        double mag = this.mag();
        return new Quaternion(x/mag, y/mag, z/mag, w/mag);
    }
}
