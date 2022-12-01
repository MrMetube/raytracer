package gui;
import java.awt.image.BufferedImage;
import java.io.File;

import javax.imageio.ImageIO;

import math.Vector;
import raytracer.Camera;
import raytracer.Scene;
import shader.Shader;


public class World{
    BufferedImage frameBuffer;
    int width,height;
    Scene scene;
    double cameraSpeed = 0.9;
    Window viewport;
 
    public World(int width, int height, Window viewport){
        this.width = width;
        this.height = height;
        this.viewport = viewport;
        this.scene = viewport.getActiveScene();
        frameBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
    }

    public void tick(){
        if(scene != viewport.getActiveScene()) scene = viewport.getActiveScene();
        Vector dir = viewport.input.getCamMove();
        Camera cam = scene.getCamera();
        //Camera movement
        cam.move(dir.mul(cameraSpeed));
        //Camera rotation
        // double yOffset = Menu.input.getYOffset(), xOffset = Menu.input.getXOffset();
        // if(yOffset != 0 || xOffset != 0) cam.rotate(yOffset, xOffset);
        
    }

    public void renderFrame(){
        if(scene == null) return;
        BufferedImage tempBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
        scene.renderImage(viewport.getActiveShader(), tempBuffer);
        frameBuffer = tempBuffer;
    }

    public void renderToFile(Shader shader, boolean timed){
        if(scene == null) return;
        String name = shader.getName();

        long start = System.nanoTime();
        scene.renderImage(shader, frameBuffer);
        if(timed) System.out.printf("%s Rendering took: %s ms%n",name, (System.nanoTime()-start)/1_000_000);

        start = System.nanoTime();
        writeImage(name);
        if(timed) System.out.printf("%s Saving took:    %s ms%n",name, (System.nanoTime()-start)/1_000_000);
    }

    public void writeImage(String name){
        File file = new File("./images/"+name+".png");
        try { ImageIO.write(frameBuffer, "png", file); } catch (Exception e) {}
    }

    public BufferedImage getFrameBuffer(){ return frameBuffer;}
    
}
