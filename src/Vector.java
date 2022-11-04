class Vector extends Tuple{
    
    Vector(double x, double y, double z){ super(x,y,z,0); }
    Vector(Point a, Point b){
        super(a.x()-b.x(), a.y()-b.y(), a.z()-b.z(), 0);
    }
    Vector add(Vector... vecs){
        Vector sum = new Vector(x,y,z);
        for (Vector v : vecs) sum = new Vector(sum.x()+v.x(), sum.y()+v.y(), sum.z()+v.z());
        return sum;
    }
    Vector cross(Tuple t){ return new Vector( y*t.z() - z*t.y(), z*t.x() - x*t.z(), x*t.y() - y*t.x()); }

    Vector norm() {
        double mag = this.mag();
        return new Vector(x/mag, y/mag, z/mag);
    }

    @Override
    public String toString(){ return String.format("x: %.2f, y: %.2f, z: %.2f",x,y,z); }
}
