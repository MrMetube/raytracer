class MUtils {
    static boolean approxEqual(double a, double b){
        double x = Math.abs(a - b);
        return x < 0.00001;
    }
    static double normRGB(double x){
        return Math.min(255, Math.max(0, x));
    }
}
