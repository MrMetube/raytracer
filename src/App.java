import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;

import javax.imageio.ImageIO;

import geometry.*;
import math.*;
import shader.*;

class App {
    public static void main(String[] args) throws IOException{
        myScene();
        // examples();
    }

    static void myScene(){
        int size = 512;

        Camera camera = new Camera(new Point(0, 0, -100), new Point(0, 0, 0), 110, size, size);
        Scene scene = new Scene(camera);
                
        scene.addGeometry(new Sphere(new Point(0, 0, 150), 150));
        scene.addGeometry(new Plane(new Vector(0, 100, 45), new Point(0, -200, 100)));
        scene.addGeometry(new Sphere(new Point( 200, 000, 150), 100));
        scene.addGeometry(new Sphere(new Point(-200, 000, 150), 100));
        scene.addGeometry(new Plane(new Vector(0, -200, 100), new Point(0, 0, 150), 200));

        writeImage(makeImage(scene, new DistanceShader()),  new DistanceShader().getName());
        writeImage(makeImage(scene, new IntersectShader()), new IntersectShader().getName());
        writeImage(makeImage(scene, new NormalShader()),    new NormalShader().getName());
    }

    static BufferedImage makeImage(Scene scene, Shader shader){
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
        return image;
    }

    static BufferedImage makeImage(int size, ScreenShader shader){
        BufferedImage image = new BufferedImage(size,size,BufferedImage.TYPE_INT_RGB);
        Color def = new Color(41, 139, 95); // default color
        Color c = null;
        for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) {
            c = shader.getColor(x, y, size);
            // apply the color
            if(c == null) c = def;
            image.setRGB(x, y, c.rgb());
        };
        return image;
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

        writeImage(makeImage(size, new ScreenPixelShader()), new ScreenPixelShader().getName());
        writeImage(makeImage(size, new ScreenDistanceShader()), new ScreenDistanceShader().getName());
        writeImage(makeImage(size, new ScreenNormalShader()), new ScreenNormalShader().getName());
    }

    static void examples(){
        Sphere sphere = new Sphere(new Point(0, 0, 0), 0.5);

        Scene s1 = new Scene(new Camera(new Point(0, 0, -10), new Point(0, 0, 0), 7.7, 800, 600));
        s1.addGeometry(sphere);
        BufferedImage image1 = makeImage(s1, new IntersectShader());

        Scene s2 = new Scene(new Camera(new Point(0, 0, -10), new Point(1, 1, 0), 11, 600, 600));
        s2.addGeometry(sphere);
        BufferedImage image2 = makeImage(s2, new IntersectShader());

        Scene s3 = new Scene(new Camera(new Point(10, 10, -10), new Point(0, 0, 0), 3.3, 600, 600));
        s3.addGeometry(sphere);
        BufferedImage image3 = makeImage(s3, new IntersectShader());

        writeImage(image1, "Example Scene 1");
        writeImage(image2, "Example Scene 2");
        writeImage(image3, "Example Scene 3");
    }
}