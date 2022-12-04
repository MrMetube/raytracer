package raytracer;

import math.Color;
import raytracer.geometry.Geometry;

import java.awt.image.BufferedImage;
import shader.Shader;

public class Trace implements Runnable{
    final BufferedImage image;
    final Color def = new Color(0.44, 0.85, 0.93);
    final Camera camera;
    final Shader shader;
    final Scene scene;
    final int xS,xE,yS,yE;

    Trace(Scene scene, BufferedImage image, int xStart, int yStart, int width, int height, Shader shader){
        this.image = image;
        this.scene = scene;
        this.camera = scene.getCamera();
        this.shader = shader;
        xS = xStart;
        yS = yStart;
        xE = Math.min(xStart+width, camera.width());
        yE = Math.min(yStart+height, camera.height());
    }
    
    @Override 
    public void run(){
        for (int x = xS; x < xE; x++) for (int y = yS; y < yE; y++) {
            Payload[] payloads = camera.generatePayload(x, y);
            Color color = new Color(0, 0, 0);
            for (Payload payload : payloads) {
                for(Geometry geometry : scene.getGeometries()) geometry.intersect(payload);
                color = color.add( ( payload.target() != null ) ? shader.getColor(payload, scene) : def);
            }
            color = color.mul(1.0/payloads.length);
            image.setRGB(x, camera.height()-y-1, color.rgb() );
        }
    }
}
