package shader;

import math.Color;
import math.Ray;
import math.Vector;
import raytracer.Payload;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.IOException;

import javax.imageio.ImageIO;

import raytracer.Scene;

public class Skybox extends Shader{

    BufferedImage image;

    public Skybox(){
        try {
            image = ImageIO.read(new File("./res/Skybox.jpg"));
        } catch (IOException e) { }
    }

    @Override
    public Color getColor(Payload p, Scene scene) {
        Ray ray = p.ray();
        Vector dir = ray.dir().norm();
        float u = (float) (0.5 + (Math.atan2(dir.z(),dir.x())/(2*Math.PI)));
        float v = (float) (0.5 + Math.asin(dir.y())/Math.PI);
        int rgb = image.getRGB((int)(image.getWidth()*(1-u)), (int)(image.getHeight()*(1-v)));
        return new Color(rgb);
    }
    
}
