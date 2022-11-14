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
        Sphere s = new Sphere(new Point(0, 0, 100), 150);;
        Color def = new Color(41, 139, 95); // default color
        Color c;
        Ray r;
        double dis;
        Vector v;
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
                    r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
                    c = s.intersect(r) ? new Color(50, 51, 68) : def;
                    break;
                case SPHERE_DIST:
                    r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
                    dis = r.dir().mag();
                    c = s.intersect(r) ? new Color(dis,dis,dis).mul(def) : def;
                    break;
                case SPHERE_NORMAL:
                    Sphere s2 = new Sphere(new Point(100,50,100),100);
                    r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
                    if(s.intersect(r)){
                        v = s.normal(r.hitPoint());
                        c = new Color(Math.abs(v.x()),Math.abs(v.y()),Math.abs(v.z()));
                    }else if (s2.intersect(r)){
                        v = s2.normal(r.hitPoint());
                        c = new Color(Math.abs(v.x()),Math.abs(v.y()),Math.abs(v.z()));
                    }else{
                        c = def;
                    }
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