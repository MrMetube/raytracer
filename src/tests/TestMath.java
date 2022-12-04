package tests;
import org.junit.jupiter.api.*;

import math.Color;
import math.Point;
import math.Tuple;
import math.Vector;
import raytracer.geometry.Sphere;

import static org.junit.jupiter.api.Assertions.*;

class TestMath {
    @Test void isPoint(){
        Tuple a = new Point(4.3, -4.2, 3.1);
        assertEquals( 4.3, a.x());
        assertEquals(-4.2, a.y());
        assertEquals( 3.1, a.z());
        assertEquals( 1.0, a.w());
    }

    @Test void isVector(){
        Tuple a = new Vector(4.3, -4.2, 3.1);
        assertEquals( 4.3, a.x());
        assertEquals(-4.2, a.y());
        assertEquals( 3.1, a.z());
        assertEquals(   0, a.w());
    }

    @Test void addTuples(){
        Tuple a = new Tuple( 3, -2, 5, 1);
        Tuple b = new Tuple(-2,  3, 1, 0);
        assertEquals(new Tuple(1, 1, 6, 1), a.add(b));
    }
    
    @Test void subPointFromPoint(){
        Point p1 = new Point(3, 2, 1);
        Point p2 = new Point(5, 6, 7);
        assertEquals(new Vector(-2, -4, -6), p1.sub(p2));
    }
    @Test void subVecFromPoint(){
        Point p  = new Point(3, 2, 1);
        Vector v = new Vector(5, 6, 7);
        assertEquals(new Point(-2, -4, -6), p.sub(v));
    }
    @Test void subVecFromVec(){
        Vector v1 = new Vector(3, 2, 1);
        Vector v2 = new Vector(5, 6, 7);
        assertEquals(new Vector(-2, -4, -6), v1.sub(v2));
    }

    @Test void subVecFromZeroVec(){
        Vector zero = new Vector(0,  0, 0);
        Vector v    = new Vector(1, -2, 3);
        assertEquals(new Vector(-1, 2, -3), zero.sub(v));
    }
    @Test void negateTuple(){
        Vector v = new Vector(1, -2, 3);
        assertEquals(new Vector(-1, 2, -3), v.neg());
    }

    @Test void multiplyTupleByScalar(){
        Tuple a = new Tuple(1, -2, 3, -4);
        assertEquals(new Tuple(3.5, -7, 10.5, -14), a.mul(3.5));
    }
    @Test void multiplyTupleByFraction(){
        Tuple a = new Tuple(1, -2, 3, -4);
        assertEquals(new Tuple(0.5, -1, 1.5, -2), a.mul(0.5));
    }
    
    @Test void divideTupleByScalar(){
        Tuple a = new Tuple(1, -2, 3, -4);
        assertEquals(new Tuple(0.5, -1, 1.5, -2), a.div(2));
    }

    @Test void magnitudeOfVec(){
        Vector v1 = new Vector(1, 0, 0);
        Vector v2 = new Vector(0, 1, 0);
        Vector v3 = new Vector(0, 0, 1);
        Vector v4 = new Vector(1, 2, 3);
        Vector v5 = new Vector(-1, -2, -3);
        assertEquals(1, v1.mag());
        assertEquals(1, v2.mag());
        assertEquals(1, v3.mag());
        assertEquals(Math.sqrt(14), v4.mag());
        assertEquals(Math.sqrt(14), v5.mag());
    }

    @Test void normalizeVec(){
        Vector v1 = new Vector(4, 0, 0);
        Vector v2 = new Vector(1, 2, 3);
        double root = Math.sqrt(14);
        assertEquals(new Vector(1, 0, 0), v1.norm());
        assertEquals(new Vector(1/root, 2/root, 3/root), v2.norm());
    }

    @Test void magnitudeOfNormalizedVec(){
        Vector v = new Vector(1, 2, 3);
        assertEquals(1, v.norm().mag());
    }

    @Test void dotProductOfTuples(){
        Tuple a = new Vector(1, 2, 3);
        Tuple b = new Vector(2, 3, 4);
        assertEquals(20,a.dot(b));
    }
    @Test void dotProductOfVecs(){
        Vector a = new Vector(1, 2, 3);
        Vector b = new Vector(2, 3, 4);
        assertEquals(20,a.dot(b));
    }

    @Test void crossProductOfVecs(){
        Vector a = new Vector(1, 2, 3);
        Vector b = new Vector(2, 3, 4);
        assertEquals(new Vector(-1, 2, -1),a.cross(b));
        assertEquals(new Vector(1, -2, 1),b.cross(a));
    }

    @Test void reflectionOfVec45deg(){
        Vector v = new Vector(1, -1, 0);
        Vector n = new Vector(0, 1, 0);
        assertEquals(new Vector(1, 1, 0), v.refl(n));
    }

    @Test void reflectionOfVecSlanted(){
        Vector v = new Vector(0, -1, 0);
        double r = Math.sqrt(2)/2;
        Vector n = new Vector(r, r, 0);
        assertEquals(new Vector(1, 0, 0), v.refl(n));
    }
    
    @Test void normalVectorOnSphereX(){
        Sphere s = new Sphere(new Point(0, 0, 0), 1);
        assertEquals(new Vector(1,0,0), s.normal(new Point(1, 0, 0)));
    }

    @Test void normalVectorOnSphereY(){
        Sphere s = new Sphere(new Point(0, 0, 0), 1);
        assertEquals(new Vector(0,1,0), s.normal(new Point(0, 1, 0)));
    }

    @Test void normalVectorOnSphereZ(){
        Sphere s = new Sphere(new Point(0, 0, 0), 1);
        assertEquals(new Vector(0,0,1), s.normal(new Point(0, 0, 1)));
    }

    @Test void normalVectorOnSphereNonaxial(){
        Sphere s = new Sphere(new Point(0, 0, 0), 1);
        double r = Math.sqrt(3)/3;
        Vector n = s.normal(new Point(r, r, r));
        assertEquals(new Vector(r, r, r), n);
        assertEquals(n, n.norm());
    }

    @Test void colorFromRGBSimple(){
        Color r = Color.RED;
        Color g = Color.GREEN;
        Color b = Color.BLUE;
        assertEquals(r, new Color(r.rgb()));
        assertEquals(g, new Color(g.rgb()));
        assertEquals(b, new Color(b.rgb()));
    }

    @Test void colorFromRGB(){
        Color r = Color.LEMON;
        Color g = Color.TURQOUISE;
        Color b = new Color(Math.sqrt(2)/2, Math.PI/4, Math.E/3);

        Color r2 = new Color(r.rgb());
        Color g2 = new Color(g.rgb());
        Color b2 = new Color(b.rgb());
        assertEquals(r, r2);
        assertEquals(g, g2);
        assertEquals(b, b2);
    }
}
