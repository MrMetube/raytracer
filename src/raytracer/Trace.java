package raytracer;

import math.Color;
import math.Ray;

import java.awt.image.BufferedImage;
import shader.Shader;

public class Trace implements Runnable{
        final BufferedImage image;
        final Color def = new Color(0.44, 0.85, 0.93);
        final Camera camera;
        final Shader shader;
        final Scene scene;
        final int xS,xE,yS,yE;

        Trace(Scene scene, BufferedImage image, int xStart, int xEnd, int yStart, int yEnd, Shader shader){
            this.image = image;
            this.scene = scene;
            this.camera = scene.getCamera();
            this.shader = shader;
            xS = xStart;
            yS = yStart;
            xE = Math.min(xEnd, camera.getWidth());
            yE = Math.min(yEnd, camera.getHeight());
        }
        @Override 
        public void run(){
            for (int x = xS; x < xE; x++) for (int y = yS; y < yE; y++) {
                Ray ray = camera.generateRay(x, y);
                Color color = (scene.traceRay(ray)) ? shader.getColor(ray, ray.target(), scene) : def;
                image.setRGB(x, camera.getHeight()-y-1, color.rgb() );
            }
        }
    }
