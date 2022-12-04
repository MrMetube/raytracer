package gui;
import java.awt.image.BufferedImage;
import java.io.File;

import javax.imageio.ImageIO;

import math.Color;
import math.Vector;
import raytracer.Camera;
import raytracer.Scene;
import raytracer.SupersamplingMode;
import shader.Shader;


public class World{
    BufferedImage frameBuffer;
    int width,height;
    Scene scene;
    double cameraSpeed = 0.2;
    Window viewport;
    int frameBufferCount = 0;
 
    public World(int width, int height, Window viewport){
        this.width = width;
        this.height = height;
        this.viewport = viewport;
        this.scene = viewport.getActiveScene();
        frameBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
    }

    public World(int width, int height){
        // This is only used when I want to time the render. I dont need UI here.
        // Obviously the other methods wont function properly.
        this.width = width;
        this.height = height;
    }

    public void tick(){
        if(scene != viewport.getActiveScene()) scene = viewport.getActiveScene();
        Vector dir = viewport.input.getCamMove();
        if( dir != Vector.ZERO) {
            Camera cam = scene.getCamera();
            //Camera movement
            cam.move(dir.mul(cameraSpeed));
            //Camera rotation
            // double yOffset = Menu.input.getYOffset(), xOffset = Menu.input.getXOffset();
            // if(yOffset != 0 || xOffset != 0) cam.rotate(yOffset, xOffset);
            frameBufferCount = 0;
            frameBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
        }
        
    }

    public void renderFrame(){
        if(scene == null) return;
        BufferedImage tempBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
        scene.renderImage(viewport.getActiveShader(), tempBuffer);
        frameBuffer = tempBuffer;
        // I tried using an additive FrameBuffer, but it didnt work
        // Because when colors are turned to rgb ints their values are clamped to not break to format.
        // It would require stroing the image as a 2D-Color-Array to not lose information between frames.
        // frameBufferCount++;
        // for (int x=0; x<frameBuffer.getWidth(); x++) for (int y = 0; y < frameBuffer.getHeight(); y++) {
        //     Color current = new Color(tempBuffer.getRGB(x, y));
        //     Color old = new Color(frameBuffer.getRGB(x, y));
        //     Color next = old.add(current);
        //     frameBuffer.setRGB(x, y, next.div(frameBufferCount).rgb());
        // }
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

    public void timedRender(Shader shader, int count){
        String name = shader.getName();
        scene = Scene.randomSpheres(100);
        BufferedImage image = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
        
        long start = System.nanoTime();
        for (int i = 0; i < count; i++)
            scene.renderImage(shader, image);
        System.out.printf("%s Saving took:    %s ms%n",name, (System.nanoTime()-start)/1_000_000);
    }

    public void writeImage(String name){
        File file = new File("./images/"+name+".png");
        try { ImageIO.write(frameBuffer, "png", file); } catch (Exception e) {}
    }

    public void setSupersampling(SupersamplingMode mode){ scene.getCamera().setSupersampling(mode);}
    public BufferedImage getFrameBuffer(){ return frameBuffer;}
    
}
