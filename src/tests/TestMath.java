package tests;
import org.junit.jupiter.api.*;

import math.Color;
import math.Matrix;
import math.Point;
import math.Tuple;
import math.Vector;
import raytracer.geometry.Sphere;

import static org.junit.jupiter.api.Assertions.*;

class TestMath {
    @Test void isPoint(){
        var a = new Point(4.3, -4.2, 3.1);
        assertEquals( 4.3, a.x());
        assertEquals(-4.2, a.y());
        assertEquals( 3.1, a.z());
        assertEquals( 1.0, a.w());
    }

    @Test void isVector(){
        var a = new Vector(4.3, -4.2, 3.1);
        assertEquals( 4.3, a.x());
        assertEquals(-4.2, a.y());
        assertEquals( 3.1, a.z());
        assertEquals(   0, a.w());
    }


    @Test void addTuples(){
        var a = new Tuple( 3, -2, 5, 1);
        var b = new Tuple(-2,  3, 1, 0);
        assertEquals(new Tuple(1, 1, 6, 1), a.add(b));
    }
    
    @Test void subPointFromPoint(){
        var p1 = new Point(3, 2, 1);
        var p2 = new Point(5, 6, 7);
        assertEquals(new Vector(-2, -4, -6), p1.sub(p2));
    }
    
    @Test void subVecFromPoint(){
        var p  = new Point(3, 2, 1);
        var v = new Vector(5, 6, 7);
        assertEquals(new Point(-2, -4, -6), p.sub(v));
    }
    
    @Test void subVecFromVec(){
        var v1 = new Vector(3, 2, 1);
        var v2 = new Vector(5, 6, 7);
        assertEquals(new Vector(-2, -4, -6), v1.sub(v2));
    }

    @Test void subVecFromZeroVec(){
        var zero = new Vector(0,  0, 0);
        var v    = new Vector(1, -2, 3);
        assertEquals(new Vector(-1, 2, -3), zero.sub(v));
    }
    
    @Test void negateTuple(){
        var v = new Vector(1, -2, 3);
        assertEquals(new Vector(-1, 2, -3), v.neg());
    }


    @Test void multiplyTupleByScalar(){
        var a = new Tuple(1, -2, 3, -4);
        assertEquals(new Tuple(3.5, -7, 10.5, -14), a.mul(3.5));
    }
    
    @Test void multiplyTupleByFraction(){
        var a = new Tuple(1, -2, 3, -4);
        assertEquals(new Tuple(0.5, -1, 1.5, -2), a.mul(0.5));
    }
    
    @Test void divideTupleByScalar(){
        var a = new Tuple(1, -2, 3, -4);
        assertEquals(new Tuple(0.5, -1, 1.5, -2), a.div(2));
    }


    @Test void magnitudeOfVec(){
        var v1 = new Vector(1, 0, 0);
        var v2 = new Vector(0, 1, 0);
        var v3 = new Vector(0, 0, 1);
        var v4 = new Vector(1, 2, 3);
        var v5 = new Vector(-1, -2, -3);
        assertEquals(1, v1.mag());
        assertEquals(1, v2.mag());
        assertEquals(1, v3.mag());
        assertEquals(Math.sqrt(14), v4.mag());
        assertEquals(Math.sqrt(14), v5.mag());
    }

    @Test void normalizeVec(){
        var v1 = new Vector(4, 0, 0);
        var v2 = new Vector(1, 2, 3);
        double root = Math.sqrt(14);
        assertEquals(new Vector(1, 0, 0), v1.norm());
        assertEquals(new Vector(1/root, 2/root, 3/root), v2.norm());
    }

    @Test void magnitudeOfNormalizedVec(){
        var v = new Vector(1, 2, 3);
        assertEquals(1, v.norm().mag());
    }


    @Test void dotProductOfTuples(){
        var a = new Vector(1, 2, 3);
        var b = new Vector(2, 3, 4);
        assertEquals(20,a.dot(b));
    }
    
    @Test void dotProductOfVecs(){
        var a = new Vector(1, 2, 3);
        var b = new Vector(2, 3, 4);
        assertEquals(20,a.dot(b));
    }

    @Test void crossProductOfVecs(){
        var a = new Vector(1, 2, 3);
        var b = new Vector(2, 3, 4);
        assertEquals(new Vector(-1, 2, -1),a.cross(b));
        assertEquals(new Vector(1, -2, 1),b.cross(a));
    }


    @Test void reflectionOfVec45deg(){
        var v = new Vector(1, -1, 0);
        var n = new Vector(0, 1, 0);
        assertEquals(new Vector(1, 1, 0), v.refl(n));
    }

    @Test void reflectionOfVecSlanted(){
        var v = new Vector(0, -1, 0);
        double r = Math.sqrt(2)/2;
        var n = new Vector(r, r, 0);
        assertEquals(new Vector(1, 0, 0), v.refl(n));
    }


    @Test void normalVectorOnSphereX(){
        var s = new Sphere(new Point(0, 0, 0), 1);
        assertEquals(new Vector(1,0,0), s.normal(new Point(1, 0, 0)));
    }

    @Test void normalVectorOnSphereY(){
        var s = new Sphere(new Point(0, 0, 0), 1);
        assertEquals(new Vector(0,1,0), s.normal(new Point(0, 1, 0)));
    }

    @Test void normalVectorOnSphereZ(){
        var s = new Sphere(new Point(0, 0, 0), 1);
        assertEquals(new Vector(0,0,1), s.normal(new Point(0, 0, 1)));
    }

    @Test void normalVectorOnSphereNonaxial(){
        var s = new Sphere(new Point(0, 0, 0), 1);
        double r = Math.sqrt(3)/3;
        var n = s.normal(new Point(r, r, r));
        assertEquals(new Vector(r, r, r), n);
        assertEquals(n, n.norm());
    }


    @Test void colorFromRGBSimple(){
        var r = Color.RED;
        var g = Color.GREEN;
        var b = Color.BLUE;
        assertEquals(r, new Color(r.rgb()));
        assertEquals(g, new Color(g.rgb()));
        assertEquals(b, new Color(b.rgb()));
    }

    @Test void colorFromRGB(){
        var r = Color.LEMON;
        var g = Color.TURQUOISE;
        var b = new Color(Math.sqrt(2)/2, Math.PI/4, Math.E/3);

        var r2 = new Color(r.rgb());
        var g2 = new Color(g.rgb());
        var b2 = new Color(b.rgb());
        assertEquals(r, r2);
        assertEquals(g, g2);
        assertEquals(b, b2);
    }


    @Test void isMatrix4x4(){
        var actual = new Matrix(
            1,2,3,4,
            5.5,6.5,7.5,8.5,
            9,10,11,12,
            13.5,14.5,15.5,16.5);
        assertEquals(1,     actual.get(0,0));
        assertEquals(2,     actual.get(0,1));
        assertEquals(3,     actual.get(0,2));
        assertEquals(4,     actual.get(0,3));
        assertEquals(5.5,   actual.get(1,0));
        assertEquals(6.5,   actual.get(1,1));
        assertEquals(7.5,   actual.get(1,2));
        assertEquals(8.5,   actual.get(1,3));
        assertEquals(9,     actual.get(2,0));
        assertEquals(10,    actual.get(2,1));
        assertEquals(11,    actual.get(2,2));
        assertEquals(12,    actual.get(2,3));
        assertEquals(13.5,  actual.get(3,0));
        assertEquals(14.5,  actual.get(3,1));
        assertEquals(15.5,  actual.get(3,2));
        assertEquals(16.5,  actual.get(3,3));
    }

    @Test void isMatrix3x3(){
        var actual = new Matrix(
            -3,5,0, 
            1,-2,-7,
            0,1,1);
        assertEquals(-3, actual.get(0,0));
        assertEquals(5,  actual.get(0,1));
        assertEquals(0,  actual.get(0,2));
        assertEquals(1,  actual.get(1,0));
        assertEquals(-2, actual.get(1,1));
        assertEquals(-7, actual.get(1,2));
        assertEquals(0,  actual.get(2,0));
        assertEquals(1,  actual.get(2,1));
        assertEquals(1,  actual.get(2,2));
    }

    @Test void isMatrix2x2(){
        var actual = new Matrix(
            -3,5, 
            1,-2);
        assertEquals(-3, actual.get(0,0));
        assertEquals(5,  actual.get(0,1));
        assertEquals(1,  actual.get(1,0));
        assertEquals(-2, actual.get(1,1));
    }

    @Test void isNotMatrix(){
        // not square
        assertThrows(AssertionError.class, () -> new Matrix(1,2));
        // index out of bounds
        assertThrows(AssertionError.class, () -> new Matrix(1,2).get(22,0));
        assertThrows(AssertionError.class, () -> new Matrix(1,2).get(-2,0));
    }

    @Test void isMatrixEqual(){
        var a = new Matrix(
            1,2,3,4,
            5,6,7,8,
            9,10,11,12,
            13,14,15,16);
        var b = new Matrix(
            1,2,3,4,
            5,6,7,8,
            9,10,11,12,
            13,14,15,16);
        var c = new Matrix(
            1,2,3,4,
            5,6,7,8,
            9,1,1,1,
            1,1,1,1);
        var d = new Matrix(
            1,2,3,
            4,5,6,
            7,8,9);
        assertEquals(a, b);
        assertNotEquals(a, c);
        assertNotEquals(a, d);
    }


    @Test void multiplyMatrices(){
        var a = new Matrix(
            1,2,3,4,
            5,6,7,8,
            9,8,7,6,
            5,4,3,2);
        var b = new Matrix(
            -2,1,2,3,
            3,2,1,-1,
            4,3,6,5,
            1,2,7,8);
        
        var expected = new Matrix(
            20,22,50,48,
            44,54,114,108,
            40,58,110,102,
            16,26,46,42);

        assertEquals(expected, a.mul(b));
    }

    @Test void multiplyMatrixWithTuple(){
        var a = new Matrix(
            1,2,3,4,
            2,4,4,2,
            8,6,4,1,
            0,0,0,1);
        var b = new Tuple(1, 2, 3, 1);
        assertEquals(new Tuple(18,24,33,1), a.mul(b));
    }

    @Test void multiplyMatrixWithScalar(){
        var a = new Matrix(
            1,2,3,4,
            2,4,4,2,
            8,6,4,1,
            0,0,0,1);
        var b = 2;
        var expected = new Matrix(
            2,4,6,8,
            4,8,8,4,
            16,12,8,2,
            0,0,0,2);
        assertEquals(expected, a.mul(b));
    }

    @Test void multiplyMatrixWithIdentity(){
        var a = new Matrix(
            0,1,2,4,
            1,2,4,8,
            2,4,8,16,
            4,8,16,32);
        assertEquals(a, a.mul(Matrix.identity4));
    }

    @Test void multiplyTupleWithIdentity(){
        var a = new Tuple(1, 2, 3, 4);
        assertEquals(a, Matrix.identity4.mul(a));
    }


    @Test void transposeMatrix(){
        var a = new Matrix(
            0,9,3,0,
            9,8,0,8,
            1,8,5,3,
            0,0,5,8);
        var b = new Matrix(
            0,9,1,0,
            9,8,8,0,
            3,0,5,5,
            0,8,3,8);
        assertEquals(b, a.transpose());
    }

    @Test void transposeIndentityMatrix(){
        assertEquals(Matrix.identity4, Matrix.identity4.transpose());
    }


    @Test void submatrix(){
        var a = new Matrix(
            1,5,0,
            -3,2,7,
            0,6,-3);
        var x = new Matrix(
            -3,2,
            0,6);

        var b = new Matrix(
            -6,1,1,6,
            -8,5,8,6,
            -1,0,8,2,
            -7,1,-1,1);
        var y = new Matrix(
            -6,1,6,
            -8,8,6,
            -7,-1,1);
        assertEquals(x, a.submatrix(0, 2));
        assertEquals(y, b.submatrix(2, 1));
    }

    @Test void minor3(){
        var a = new Matrix(
            3,5,0,
            2,-1,-7,
            6,-1,5);
        var b = a.submatrix(1, 0);
        assertEquals(b.determinant(),a.minor(1,0));
    }

    @Test void cofactor3(){
        var a = new Matrix(
            3,5,0,
            2,-1,-7,
            6,-1,5);
        assertEquals(-12, a.minor(0, 0));
        assertEquals(-12, a.cofactor(0, 0));
        assertEquals( 25, a.minor(1, 0));
        assertEquals(-25, a.cofactor(1, 0));
    }

    @Test void determinant2(){
        var a = new Matrix(
            1,5,
            -3,2);
        assertEquals(17, a.determinant());
    }

    @Test void determinant3(){
        var a = new Matrix(
            1,2,6,
            -5,8,-4,
            2,6,4);
        assertEquals( 56, a.cofactor(0, 0));
        assertEquals( 12, a.cofactor(0, 1));
        assertEquals(-46, a.cofactor(0, 2));
        assertEquals(-196, a.determinant());
    }
    
    @Test void determinant4(){
        var a = new Matrix(
            -2,-8, 3, 5,
            -3, 1, 7, 3,
             1, 2,-9, 6,
            -6, 7, 7,-9);
        assertEquals(690, a.cofactor(0, 0));
        assertEquals(447, a.cofactor(0, 1));
        assertEquals(210, a.cofactor(0, 2));
        assertEquals( 51, a.cofactor(0, 3));
        assertEquals(-4071, a.determinant());
    }


    @Test void isInvertible(){
        var a = new Matrix(
            6,4,4,4,
            5,5,7,6,
            4,-9,3,-7,
            9,1,7,-6);
        var b = new Matrix(
            -4,2,-2,-3,
            9,6,2,6,
            0,-5,1,-5,
            0,0,0,0);
        assertTrue(a.isInvertible());
        assertFalse(b.isInvertible());
    }

    @Test void invertMatrix(){
        var a = new Matrix(
            -5, 2, 6,-8,
             1,-5, 1, 8,
             7, 7,-6,-7,
             1,-3, 7, 4);
        var b = a.inverse();
        var expected = new Matrix(
             0.21805,  0.45113,  0.24060, -0.04511,
            -0.80827, -1.45677, -0.44361,  0.52068,
            -0.07895, -0.22368, -0.05263,  0.19737,
            -0.52256, -0.81391, -0.30075,  0.30639);
        
        assertEquals(532, a.determinant());
        assertEquals(-160,a.cofactor(2, 3));
        assertEquals(-160d/532d,b.get(3, 2));
        assertEquals(105,a.cofactor(3, 2));
        assertEquals(105d/532d,b.get(2,3));
        assertEquals(expected,b);
    }

    @Test void invertingMatricese(){
        var a = new Matrix(
            8 , -5 , 9 , 2 ,
            7 , 5 , 6 , 1 ,
            -6 , 0 , 9 , 6 ,
            -3 , 0 , -9 , -4);
        var x = new Matrix(
            -0.15385 , -0.15385 , -0.28205 , -0.53846 ,
            -0.07692 , 0.12308 , 0.02564 , 0.03077 ,
            0.35897 , 0.35897 , 0.43590 , 0.92308 ,
            -0.69231 , -0.69231 , -0.76923 , -1.92308 );
        var b = new Matrix(
            9 , 3 , 0 , 9 ,
            -5 , -2 , -6 , -3 ,
            -4 , 9 , 6 , 4 ,
            -7 , 6 , 6 , 2 );
        var y = new Matrix(
            -0.04074 , -0.07778 , 0.14444 , -0.22222 ,
            -0.07778 , 0.03333 , 0.36667 , -0.33333 ,
            -0.02901 , -0.14630 , -0.10926 , 0.12963 ,
            0.17778 , 0.06667 , -0.26667 , 0.33333 );
        assertEquals(x,a.inverse());
        assertEquals(y,b.inverse());
    }

    @Test void multiplyingByInverse(){
        var a = new Matrix(
            3 , -9 , 7 , 3 ,
            3 , -8 , 2 , -9 ,
            -4 , 4 , 4 , 1 ,
            -6 , 5 , -1 , 1 );
        var b = new Matrix(
            8 , 2 , 2 , 2 ,
            3 , -1 , 7 , 0 ,
            7 , 0 , 5 , 4 ,
            6 , -2 , 0 , 5);
        var c = a.mul(b);
        assertEquals(a, c.mul(b.inverse()));
    }


    @Test void translatePoint(){
        var transform = Matrix.translation(5, -3, 2);
        var p = new Point(-3,4,5);
        assertEquals(new Point(2,1,7), transform.mul(p));
    }
    
    @Test void translatePointByInverse(){
        var transform = Matrix.translation(5, -3, 2).inverse();
        var p = new Point(-3,4,5);
        assertEquals(new Point(-8,7,3), transform.mul(p));
    }

    @Test void translateVector(){
        var transform = Matrix.translation(5, -3, 2);
        var v = new Vector(-3,4,5);
        assertEquals(v, transform.mul(v));
    }

    @Test void scalePoint(){
        var transform = Matrix.scaling(2, 3, 4);
        var p = new Point(-4,6,8);
        assertEquals(new Point(-8,18,32), transform.mul(p));
    }

    @Test void scaleVector(){
        var transform = Matrix.scaling(2, 3, 4);
        var v = new Vector(-4,6,8);
        assertEquals(new Vector(-8,18,32), transform.mul(v));
    }
    
    @Test void scaleVectorByInverse(){
        var transform = Matrix.scaling(2, 3, 4).inverse();
        var v = new Vector(-4,6,8);
        assertEquals(new Vector(-2,2,2), transform.mul(v));
    }

    @Test void reflectPoint(){
        var transform = Matrix.scaling(-1,1,1);
        var p = new Point(2,3,4);
        assertEquals(new Point(-2,3,4), transform.mul(p));
    }

    @Test void rotatePointOverX(){
        var p = new Point(0,1,0);
        var halfQuarter = Matrix.rotationX(Math.PI/4);
        var fullQuarter = Matrix.rotationX(Math.PI/2);
        var inverse     = halfQuarter.inverse(); 
        var r2 = Math.sqrt(2)/2;

        assertEquals(new Point(0,r2,r2), halfQuarter.mul(p));
        assertEquals(new Point(0,0,1), fullQuarter.mul(p));

        assertEquals(new Point(0,r2,-r2), inverse.mul(p));

    }
    
    @Test void rotatePointOverY(){
        var p = new Point(0,0,1);
        var halfQuarter = Matrix.rotationY(Math.PI/4);
        var fullQuarter = Matrix.rotationY(Math.PI/2);
        var r2 = Math.sqrt(2)/2;

        assertEquals(new Point(r2,0,r2), halfQuarter.mul(p));
        assertEquals(new Point(1,0,0), fullQuarter.mul(p));
    }
        
    @Test void rotatePointOverZ(){
        var p = new Point(0,1,0);
        var halfQuarter = Matrix.rotationZ(Math.PI/4);
        var fullQuarter = Matrix.rotationZ(Math.PI/2);
        var r2 = Math.sqrt(2)/2;

        assertEquals(new Point(-r2,r2,0), halfQuarter.mul(p));
        assertEquals(new Point(-1,0,0), fullQuarter.mul(p));
    }

    @Test void shearPoint(){
        var p = new Point(2,3,4);
        var xy = Matrix.shearing(1, 0, 0, 0, 0, 0);
        var xz = Matrix.shearing(0, 1, 0, 0, 0, 0);
        var yx = Matrix.shearing(0, 0, 1, 0, 0, 0);
        var yz = Matrix.shearing(0, 0, 0, 1, 0, 0);
        var zx = Matrix.shearing(0, 0, 0, 0, 1, 0);
        var zy = Matrix.shearing(0, 0, 0, 0, 0, 1);

        assertEquals(new Point(5,3,4), xy.mul(p));
        assertEquals(new Point(6,3,4), xz.mul(p));
        assertEquals(new Point(2,5,4), yx.mul(p));
        assertEquals(new Point(2,7,4), yz.mul(p));
        assertEquals(new Point(2,3,6), zx.mul(p));
        assertEquals(new Point(2,3,7), zy.mul(p));
    }

    @Test void chainTransformations(){
        var p = new Point(1,0,1);
        var a = Matrix.rotationX(Math.PI/2);
        var b = Matrix.scaling(5, 5, 5);
        var c = Matrix.translation(10, 5, 7);

        var p2 = a.mul(p);
        assertEquals(new Point(1, -1, 0), p2);

        var p3 = b.mul(p2);
        assertEquals(new Point(5, -5, 0),p3);

        var p4 = c.mul(p3);
        assertEquals(new Point(15, 0, 7), p4);

        var t = c.mul(b).mul(a);
        var p5 = t.mul(p);
        assertEquals(new Point(15, 0, 7), p5);
        assertEquals(p4,p5);
    }
}
