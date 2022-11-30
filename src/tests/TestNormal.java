package tests;

import org.junit.jupiter.api.*;
import static org.junit.jupiter.api.Assertions.*;

import math.*;
import raytracer.geometry.Sphere;

public class TestNormal {
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
}
