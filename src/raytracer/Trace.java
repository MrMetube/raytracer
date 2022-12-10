package raytracer;

import math.Color;
import raytracer.geometry.Geometry;

import shader.Shader;
import shader.Skybox;

public class Trace implements Runnable{
    final Color[][] buffer;
    final Color def = new Color(0.44, 0.85, 0.93);
    final Shader shader;
    final Scene scene;
    final Camera camera;
    final int start,end, totalHeight, totalWidth;
    final Skybox skybox;

    public Trace(int totalWidth, int totalHeight,  int start, int deltaHeight, Scene scene, Camera camera, Color[][] buffer,Shader shader){
        this.buffer = buffer;
        this.scene = scene;
        this.shader = shader;
        this.camera = camera;
        this.totalHeight = totalHeight;
        this.totalWidth = totalWidth;
        this.start = start;
        end = Math.min(start+deltaHeight, totalHeight);
        skybox = new Skybox();
    }
    
    @Override 
    public void run(){
        for (int u = 0; u < totalWidth; u++) for (int v = start; v < end; v++) {
            Payload[] payloads = camera.generatePayload(u, v);
            Color color = new Color(0, 0, 0);
            for (Payload payload : payloads) {
                for(Geometry geometry : scene.getGeometries()) geometry.intersect(payload);
                color = color.add( ( payload.target() != null ) ? shader.getColor(payload, scene) : skybox.getColor(payload, scene));
            }
            color = color.div(payloads.length);
            buffer[u][totalHeight-v-1] = color;
        }
    }
}
