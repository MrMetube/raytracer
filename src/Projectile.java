class Projectile {
    private Point pos  = new Point(0, 0, 0);
    private Vector vel = new Vector(0, 0, 0);

    Projectile(Point position, Vector velocity){
        this.pos = position;
        this.vel = velocity;
    }

    Projectile tick(Environment e){
        return new Projectile( pos.add(vel), vel.add(e.grav(), e.wind()) );
    }

    Point  pos() { return pos; }
    Vector vel() { return vel; }
 
    @Override
    public String toString() { return String.format("pos: %s, vel: %s", pos, vel); }
}
