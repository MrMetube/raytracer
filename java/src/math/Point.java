package math;

public class Point extends Tuple{

    public static Point zero = new Point(0, 0, 0);

    public Point(double x, double y, double z){ super(x,y,z,1); }

    public Point add(Vector v){ return new Point(x+v.x(), y+v.y(), z+v.z()); }
    public Vector sub(Point t){ return new Vector(x-t.x(), y-t.y(), z-t.z()); }

    @Override
    public String toString(){ return String.format("(%.02f | %.02f | %.02f)",x,y,z); }
}
