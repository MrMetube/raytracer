import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.HashSet;

import javax.imageio.ImageIO;

class App {
    public static void main(String[] args) throws IOException{
        int size = 512;
        Plane p = new Plane(new Vector(0, 100, 0), new Point(0, 100, 100), 500);
        Sphere s = new Sphere(new Point(0, 0, 100), 150);
        Sphere s2 = new Sphere(new Point(100, 100, 200), 150);

        HashSet<Geometry> geometries = new HashSet<>();
        geometries.add(s);
        geometries.add(s2);
        geometries.add(p);

        // makeImage(size, new ScreenPixelShader());
        // makeImage(size, new ScreenDistanceShader());
        // makeImage(size, new ScreenNormalShader());

        makeImage(size, new DistanceShader(), geometries);
        makeImage(size, new NormalShader(), geometries);
        makeImage(size, new IntersectShader(), geometries);
    }

    static void makeImage(int size, Shader shader, HashSet<Geometry> geometries){
        BufferedImage image = new BufferedImage(size,size,BufferedImage.TYPE_INT_RGB);
        Color def = new Color(41, 139, 95); // default color
        for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) {
            Color c = null;
            for(Geometry geometry : geometries){
                // TODO only save the closest color
                c = shader.getColor(x, y, size, geometry);
            }
            // apply the color
            if(c == null) c = def;
            image.setRGB(x, y, c.rgb());
        };

        //write to file
        File file = new File("./images/"+shader.getName()+".png");
        try {
            ImageIO.write(image, "png", file);   
        } catch (Exception e) {
            System.out.println(e.getMessage());
        }
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

        //write to file
        File file = new File("./images/"+shader.getName()+".png");
        try {
            ImageIO.write(image, "png", file);   
        } catch (Exception e) {
            System.out.println(e.getMessage());
        }
    }
}