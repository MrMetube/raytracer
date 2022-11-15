import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.HashSet;

import javax.imageio.ImageIO;

import geometry.*;
import math.*;
import shader.*;

class App {
    public static void main(String[] args) throws IOException{
        myScene();
        // scene1();
        // scene2();
        // scene3();
        // screen();
    }

    static void myScene(){
        int size = 512;
        
        HashSet<Geometry> geometries = new HashSet<>();
        geometries.add(new Sphere(new Point(0, 0, 150), 150));

        geometries.add(new Plane(new Vector(0, 100, 45), new Point(0, -200, 100)));

        geometries.add(new Sphere(new Point( 200, 000, 150), 100));
        geometries.add(new Sphere(new Point(-200, 000, 150), 100));

        geometries.add(new Plane(new Vector(0, -200, 100), new Point(0, 0, 150), 200));

        Camera camera = new Camera(new Point(0, 0, -100), new Point(0, 0, 0), 110, size, size);

        makeImage(new Scene(geometries,camera), new DistanceShader());
        makeImage(new Scene(geometries,camera), new IntersectShader());
        makeImage(new Scene(geometries,camera), new NormalShader());
    }

    static void makeImage(Scene scene, Shader shader){
        Camera camera = scene.getCamera();

        int width = camera.getWidth();
        int height = camera.getHeight();

        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Color def = new Color(113, 216, 237); // default color
        
        for (int x = 0; x < width; x++) for (int y = 0; y < height; y++) {
            Ray ray = camera.generateRay(x, y);
            Color color = (scene.traceRay(ray)) ? shader.getColor(ray, ray.target()) : def;
            image.setRGB(x, height-y-1, color.rgb() );
        }

        writeImage(image, shader.getName());
    }

    static void makeImage(int size, ScreenShader shader){
        BufferedImage image = new BufferedImage(size,size,BufferedImage.TYPE_INT_RGB);
        Color def = new Color(41, 139, 95); // default color
        Color c = null;
        for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) {
            c = shader.getColor(x, y, size);
            // apply the color
            if(c == null) c = def;
            image.setRGB(x, y, c.rgb());
        };

        writeImage(image, shader.getName());
    }

    static void writeImage(BufferedImage image, String name){
        File file = new File("./images/"+name+".png");
            try {
                ImageIO.write(image, "png", file);   
            } catch (Exception e) {
                System.out.println(e.getMessage());
            }
        }



    static void screen(){
        int size = 512;

        makeImage(size, new ScreenPixelShader());
        makeImage(size, new ScreenDistanceShader());
        makeImage(size, new ScreenNormalShader());
    }

    static void scene1(){
        HashSet<Geometry> geometries = new HashSet<>();
        geometries.add(new Sphere(new Point(0, 0, 0), 0.5));
        makeImage(new Scene(
            geometries, 
            new Camera(new Point(0, 0, -10), new Point(0, 0, 0), 7.7, 800, 600) ), 
            new IntersectShader());
    }

    static void scene2(){
        HashSet<Geometry> geometries = new HashSet<>();
        geometries.add(new Sphere(new Point(0, 0, 0), 0.5));
        makeImage(new Scene(
            geometries, 
            new Camera(new Point(0, 0, -10), new Point(1, 1, 0), 11, 600, 600) ), 
            new IntersectShader());
    }

    static void scene3(){
        HashSet<Geometry> geometries = new HashSet<>();
        geometries.add(new Sphere(new Point(0, 0, 0), 0.5));
        makeImage(new Scene(
            geometries, 
            new Camera(new Point(10, 10, -10), new Point(0, 0, 0), 3.3, 600, 600) ), 
            new IntersectShader());
    }
}