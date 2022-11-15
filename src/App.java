import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.util.HashSet;

import javax.imageio.ImageIO;

class App {
    public static void main(String[] args) throws IOException{
        int size = 512;
        
        HashSet<Geometry> geometries = new HashSet<>();
        geometries.add(new Sphere(new Point(0, 0, 200), 150));

        geometries.add(new Plane(new Vector(0, 0, 100), new Point(0, -100, 0)));

        geometries.add(new Sphere(new Point( 200, 000, 100), 75));
        geometries.add(new Sphere(new Point(-200, 000, 100), 75));
        geometries.add(new Sphere(new Point( 000, 200, 100), 75));
        geometries.add(new Sphere(new Point( 000,-200, 100), 75));

        geometries.add(new Plane(new Vector( 90, 45, 90), new Point( 100, 100, 100), 120));
        geometries.add(new Plane(new Vector(-90, 45, 90), new Point(-100, 100, 100), 120));
        geometries.add(new Plane(new Vector( 90,-45, 90), new Point( 100,-100, 100), 120));
        geometries.add(new Plane(new Vector(-90,-45, 90), new Point(-100,-100, 100), 120));

        // makeImage(size, new ScreenPixelShader());
        // makeImage(size, new ScreenDistanceShader());
        // makeImage(size, new ScreenNormalShader());

        makeImage(size, new DistanceShader(),  geometries);
        makeImage(size, new NormalShader(),    geometries);
        makeImage(size, new IntersectShader(), geometries);
    }

    static void makeImage(int size, Shader shader, HashSet<Geometry> geometries){
        BufferedImage image = new BufferedImage(size,size,BufferedImage.TYPE_INT_RGB);
        Color def = new Color(113, 216, 237); // default color
        for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) {
            //setup
            Color  color = null;
            double z = Integer.MAX_VALUE;
            Ray ray = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
            
            //use shader on geometries
            for(Geometry geometry : geometries){
                Color maybeColor = shader.getColor(ray, geometry);
                if(ray.t() < z){
                    color = maybeColor;
                    z = ray.t();
                }
            }
            if(ray.t() == Double.MAX_VALUE) color = def;
            // apply the color
            image.setRGB(x, size-y-1, color.rgb() );
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