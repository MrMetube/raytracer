package math;

import raytracer.Payload;
import raytracer.geometry.Geometry;

public class MUtils {
    public static boolean approxEqual(double a, double b){
        double x = Math.abs(a - b);
        return x < 0.00001;
    }

    public static boolean solveQuadratic(double a, double b, double c, Payload payload, Geometry target){
        double t1,t2;
        double discr = b * b - 4 * a * c; 
        if (discr < 0) return false; 
        else if (discr == 0) t1 = t2 = - 0.5 * b / a; 
        else {
            double q = -0.5 * (b + ( (b > 0) ? Math.sqrt(discr) : -Math.sqrt(discr) )); 
            t1 = q / a; 
            t2 = c / q; 
        } 
        if (t1 > t2){
            double temp = t1;
            t1 = t2;
            t2 = temp;
        }
        if(t1<=0) return false;
        payload.hit(target,t1);
        return true; 
    }
}
