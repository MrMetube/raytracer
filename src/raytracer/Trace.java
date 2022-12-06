package raytracer;

import math.Color;
import raytracer.geometry.Geometry;

import java.awt.image.BufferedImage;

import shader.Shader;

public class Trace implements Runnable{
    final BufferedImage image;
    final Color def = new Color(0.44, 0.85, 0.93);
    final Shader shader;
    final Scene scene;
    final Camera camera;
    final int start,end, totalHeight, totalWidth;

    public Trace(Scene scene, int totalWidth, int totalHeight, Camera camera, BufferedImage image, int start, int deltaHeight, Shader shader){
        this.image = image;
        this.scene = scene;
        this.shader = shader;
        this.camera = camera;
        this.totalHeight = totalHeight;
        this.totalWidth = totalWidth;
        this.start = start;
        this.end = Math.min(start+deltaHeight, totalHeight);
    }
    
    @Override 
    public void run(){
        for (int u = 0; u < totalWidth; u++) for (int v = start; v < end; v++) {
            Payload[] payloads = camera.generatePayload(u, v);
            Color color = new Color(0, 0, 0);
            for (Payload payload : payloads) {
                for(Geometry geometry : scene.getGeometries()) geometry.intersect(payload);
                color = color.add( ( payload.target() != null ) ? shader.getColor(payload, scene) : def);
            }
            color = color.div(payloads.length);
            image.setRGB(u, totalHeight-v-1, color.rgb() );
        }
    }
}
