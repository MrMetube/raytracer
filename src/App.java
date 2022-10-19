public class App {
    public static void main(String[] args){
        Environment room = new Environment(new Vector(0, -9.81, 0), new Vector(0, 0, -2));
        Projectile  ball = new Projectile( new Point(0, 10, 0),     new Vector(5, 2, 0) );
        for(int i=0;i<10;i++){
            ball = tick(room,ball);
            System.out.println(ball);
        }
    }

    static Projectile tick(Environment e, Projectile p){
        return new Projectile( p.pos().add(p.vel()), p.vel().add(e.grav(), e.wind()) );
    }
}