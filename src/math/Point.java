package math;

public class Point extends Tuple{

    public Point(double x, double y, double z){ super(x,y,z,1); }

    public Point add(Vector... vecs){
        Point sum = new Point(x,y,z);
        for (Vector v : vecs) sum = new Point(sum.x()+v.x(), sum.y()+v.y(), sum.z()+v.z());
        return sum;
    }
    public Vector sub(Point t){ return new Vector(x-t.x(), y-t.y(), z-t.z()); }

    @Override
    public String toString(){ return String.format("x: %.2f, y: %.2f, z: %.2f",x,y,z); }
}
