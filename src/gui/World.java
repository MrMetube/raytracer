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
 
    public World(int width, int height){
        this.width = width;
        this.height = height;
        this.scene = Menu.getActiveScene();
        frameBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
    }

    public void tick(){
        if(scene != Menu.getActiveScene()) scene = Menu.getActiveScene();
        Vector dir = Menu.input.getCamMove();
        Camera cam = scene.getCamera();
        double yOffset = Menu.input.getYOffset(), xOffset = Menu.input.getXOffset();
        System.out.println(yOffset + " " + xOffset);
        if(yOffset != 0 || xOffset != 0) cam.rotate(yOffset, xOffset);
        cam.move(dir.mul(cameraSpeed));
    }

    public void renderFrame(Shader shader){
        if(scene == null) return;
        BufferedImage tempBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
        scene.renderImage(shader, tempBuffer);
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
