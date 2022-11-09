import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;

import javax.imageio.ImageIO;

enum ImageMode{
    PIXEL,RAY,DISTANCE, SPHERE_INTER, SPHERE_NORMAL, SPHERE_DIST
}

class App {
    public static void main(String[] args) throws IOException{
        int size = 512;
        // makeImage(ImageMode.PIXEL, size);
        // makeImage(ImageMode.RAY, size);
        // makeImage(ImageMode.DISTANCE, size);
        // makeImage(ImageMode.SPHERE_INTER, size);
        // makeImage(ImageMode.SPHERE_DIST, size);
        makeImage(ImageMode.SPHERE_NORMAL, size);
    }

    static void makeImage(ImageMode mode, int size){
        BufferedImage image = new BufferedImage(size,size,BufferedImage.TYPE_INT_RGB);
        Color c;
        Sphere s;
        Ray r;
        double dis;
        for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) {
            switch(mode){
                case PIXEL:
                    c = new Color((x+0.5)*255/size,(y+0.5)*255/size,0);
                    break;
                case RAY:
                    r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
                    c = new Color(Math.abs(r.dir().x()),Math.abs(r.dir().y()),Math.abs(r.dir().z()));
                    break;
                case DISTANCE:
                    dis = new Vector(x+0.5-size/2,y+0.5-size/2,100).mag();
                    c = new Color(dis,dis,dis);
                    break;
                case SPHERE_INTER:
                    s = new Sphere(new Point(0, 0, 100), 150);
                    r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
                    c = s.intersect(r) ? new Color(255,255,0) : new Color(0, 0, 255);
                    break;
                case SPHERE_DIST:
                    s = new Sphere(new Point(0, 0, 100), 150);
                    r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
                    
                    dis = r.dir().mag();
                    c = s.intersect(r) ? new Color(dis,dis,dis) : new Color(0, 0, 255);
                    break;
                case SPHERE_NORMAL:
                    s = new Sphere(new Point(0, 0, 100), 150);
                    r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
                    
                    c = s.intersect(r) ? new Color(Math.abs(r.dir().x()),Math.abs(r.dir().y()),Math.abs(r.dir().z())) : new Color(0, 0, 255);
                    break;
                default:
                    c = new Color(0, 0, 0);
                    break;
            }
            // apply the color
            image.setRGB(x, y, c.rgb());
        };
        //write to file
        File file = new File("./images/"+mode+".png");
        try {
            ImageIO.write(image, "png", file);   
        } catch (Exception e) {
            System.out.println(e.getMessage());
        }
    }
}