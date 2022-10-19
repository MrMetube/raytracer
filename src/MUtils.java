public class MUtils {
    static boolean approxEqual(double a, double b){
        double x = Math.abs(a - b);
        return x < 0.00001;
    }
}
