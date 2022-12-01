package gui;
import java.awt.image.BufferedImage;
import java.io.File;

import javax.imageio.ImageIO;

import math.Vector;
import raytracer.Scene;
import shader.Shader;


public class World{
    BufferedImage frameBuffer;
    int width,height;
    Scene scene;
 
    public World(int width, int height, Scene scene){
        this.width = width;
        this.height = height;
        this.scene = scene;
        frameBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
    }

    public void setScene(Scene scene){ this.scene = scene; }

    public void tick(){
        if(scene == null) return;
        Vector dir = Menu.input.getCamDir();
        scene.getCamera().move(dir);
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
