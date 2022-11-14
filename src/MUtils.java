class MUtils {
    static boolean approxEqual(double a, double b){
        double x = Math.abs(a - b);
        return x < 0.00001;
    }
    static double normRGB(double x){
        return Math.min(255, Math.max(0, x));
    }

    static boolean solveQuadratic(double a, double b, double c, Ray ray){
        double t1,t2;
        double discr = b * b - 4 * a * c; 
        if (discr < 0) return false; 
        else if (discr == 0) t1 = t2 = - 0.5 * b / a; 
        else { 
            double q = (b > 0) ? 
                -0.5 * (b + Math.sqrt(discr)) : 
                -0.5 * (b - Math.sqrt(discr)); 
            t1 = q / a; 
            t2 = c / q; 
        } 
        if (t1 > t2){
            double temp = t1;
            t1 = t2;
            t2 = temp;
        }
        ray.hit(t1);
        return true; 
    } 
}
