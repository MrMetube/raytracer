package shader;

import math.Color;
import math.Ray;
import math.Util;
import math.Vector;
import raytracer.Payload;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;

import javax.imageio.ImageIO;

import gui.App;
import raytracer.Scene;

public class Skybox extends Shader{

    BufferedImage image;
    Color defaultColor = new Color(0.44, 0.85, 0.93);
    int size = 1000;

    double[] vLookUp = new double[size*2];
    double[][] uLookUp = new double[size*2][size*2];

    public Skybox(){
        //Setup LookUp-Table
        for (int y = 0; y < vLookUp.length; y++) {
            double d = (double)(y-size)/size;
            vLookUp[y] = 0.5 + Math.asin(d) / Math.PI;
        }
        for (int x = 0; x < uLookUp.length; x++) for (int z = 0; z < uLookUp[0].length; z++){
            double d = (double)(x-size)/size;
            double e = (double)(z-size)/size;
            uLookUp[x][z] = 0.5 + (Math.atan2(e,d) / (2*Math.PI));
        }

        if(App.useSkybox){
            try {
                image = hdrToBufferedImage(new File("./res/Skybox.hdr"));
            } catch (Exception e) {
                image = new BufferedImage(800,800,BufferedImage.TYPE_INT_RGB);
                e.printStackTrace();
            }
        }
    }

    @Override
    public void getColor(Payload p, Scene scene) {
        if(App.useSkybox){
            Ray ray = p.ray();
            Vector dir = ray.dir().norm();

            double u = uLookUp[clamp(dir.x())][clamp(dir.z())];
            double v = vLookUp[clamp(dir.y())];

            int rgb = image.getRGB((int)(image.getWidth()*(1-u)), (int)(image.getHeight()*(1-v)));
            p.setColor(new Color(rgb));
        }else{
            p.setColor(defaultColor);
        }
    }

    int clamp(double x){
        return Util.clamp((int) Math.round(x*size)+size, 1, size*2-1);
    }
    
    public BufferedImage hdrToBufferedImage(File hdrFile) throws IOException {
        BufferedImage hdr = ImageIO.read(hdrFile);
        int width = hdr.getWidth();
        int height = hdr.getHeight();
        BufferedImage bi = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        double colorToneCorrection = 0.85;
        for (int x = 0; x < width; x++) {
            for (int y = 0; y < height; y++) {
                bi.setRGB(x, y, new Color(hdr.getRGB(x, y)).mul(colorToneCorrection).rgb());
            }
        }
        return bi;
    }

}
