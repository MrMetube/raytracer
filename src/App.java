import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;
import java.time.Instant;
import java.util.Date;

import javax.imageio.ImageIO;

enum ImageMode{
    PIXEL,RAY,DISTANCE
}

class App {
    public static void main(String[] args) throws IOException{
        makeImage(ImageMode.RAY, 512);
    }

    static void makeImage(ImageMode mode, int size){
        BufferedImage image = new BufferedImage(size,size,BufferedImage.TYPE_INT_RGB);
        Color c;
        String name = "";
        for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) {
            switch(mode){
                case PIXEL:
                    c = new Color(x+0.5,y+0.5,0);
                    name = "Pixel";
                    break;
                case RAY:
                    Vector v = new Vector(x+0.5-size/2,y+0.5-size/2,100);
                    c = new Color(Math.abs(v.x()),Math.abs(v.y()),Math.abs(v.z()));
                    name = "Ray";
                    break;
                case DISTANCE:
                    double dis = new Vector(x+0.5-size/2,y+0.5-size/2,100).mag();
                    c = new Color(dis,dis,dis);
                    name = "Distance";
                    break;
                default:
                    c = new Color(0, 0, 0);
                    break;
            }
            // apply the color
            image.setRGB(x, y, c.rgb());
        };
        //write to file
        File file = new File(name + " " + Date.from(Instant.now()).toString().substring(4, 16).replace(":","-") + ".png");
        try {
            ImageIO.write(image, "png", file);   
        } catch (Exception e) {
            System.out.println(e.getMessage());
        }
    }
}