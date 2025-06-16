package math;

public class Quaternion extends Tuple {

    public Quaternion(double x, double y, double z, double w) {
        super(x, y, z, w);
    }
    
    public Quaternion con(){
        return new Quaternion(-x, -y, -z, w);
    }

    public Quaternion mul(Quaternion r){ 
        
        double x_ = x * r.w() + w * r.x() + y * r.z() - z * r.y();
        double y_ = y * r.w() + w * r.y() + z * r.x() - x * r.z();
        double z_ = z * r.w() + w * r.z() + x * r.y() - y * r.x();
        double w_ = w * r.w() - x * r.x() - y * r.y() - z * r.z();

        return new Quaternion(x_, y_, z_, w_); 
    }

    public Quaternion mul(Vector r){

        double w_ = -x * r.x() - y * r.y() - z * r.z();
        double x_ =  w * r.x() + y * r.z() - z * r.y();
        double y_ =  w * r.y() + z * r.x() - x * r.z();
        double z_ =  w * r.z() + x * r.y() - y * r.x(); 

        return new Quaternion(x_, y_, z_, w_);
    }


    public double dot(Tuple t){ return x*t.x() + y*t.y() + z*t.z() + w*t.w(); }
    
    public Quaternion norm(){ 
        double mag = this.mag();
        return new Quaternion(x/mag, y/mag, z/mag, w/mag);
    }
}
