package gui;
import java.awt.Graphics;
import java.awt.image.BufferedImage;
import java.io.File;

import javax.imageio.ImageIO;

import math.Vector;


public class World{
    BufferedImage frameBuffer;
    int width,height;
    Vector camMovement = Vector.ZERO;
 
    public World(int width, int height){
        this.width = width;
        this.height = height;
        frameBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
    }

    public void setCamMovement(Vector dir){
        this.camMovement = dir;
    }

    public void tick(Scene scene){
        if (camMovement != Vector.ZERO){
            scene.getCamera().move(camMovement);
        }
    }

    public void renderScene(Scene scene, Shader shader){
        BufferedImage tempBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
        scene.renderImage(shader, tempBuffer);
        frameBuffer = tempBuffer;
    }

    public void renderToFile(Scene scene, Shader shader, boolean timed){
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
