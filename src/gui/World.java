package gui;
import java.awt.image.BufferedImage;
import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.imageio.ImageIO;

import math.Point;
import math.Vector;
import raytracer.Camera;
import raytracer.Scene;
import raytracer.SupersamplingMode;
import raytracer.Trace;
import shader.Phong;
import shader.Shader;


public class World{
    BufferedImage frameBuffer;
    int width,height;
    Camera camera;

    Scene scene = new Scene();
    Shader shader = new Phong();
    SupersamplingMode supersampling = SupersamplingMode.NONE;


    private double cameraSpeed = 0.2;
    int frameBufferCount = 0;
    Input input = new Input(this);

    public World(int width, int height){
        this.width = width;
        this.height = height;
        this.camera = new Camera(new Point(0, 0, -10), Point.ZERO, 90, this);
        frameBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
    }


    public void tick(){
        Vector dir = input.getCamMove();
        if( dir != Vector.ZERO) {
            //Camera movement
            camera.move(dir.mul(cameraSpeed));
            //Camera rotation
            // double yOffset = Menu.input.getYOffset(), xOffset = Menu.input.getXOffset();
            // if(yOffset != 0 || xOffset != 0) cam.rotate(yOffset, xOffset);
            // frameBufferCount = 0;
            // frameBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
        }
    }

    public void setScene(Scene scene){ this.scene = scene; }
    public void setShader(Shader shader){ this.shader = shader; }
    public void setSupersampling(SupersamplingMode mode){ camera.setSupersampling(mode);}
    
    public int getWidth() { return width; }
    public int getHeight() { return height; }
    public Scene getScene() { return scene; }
    public Input getInput() { return input; }
    public Shader getShader(){ return shader; }
    public BufferedImage getFrameBuffer(){ return frameBuffer;}
    public SupersamplingMode getSupersampling() { return supersampling; }

    public void renderImage(BufferedImage image){
        int threadCount = Runtime.getRuntime().availableProcessors();
        ExecutorService exe =  Executors.newFixedThreadPool(threadCount);
        int deltaHeight = (height / threadCount)+1;
        for (int i = 0; i < threadCount; i++) 
            exe.submit(new Trace(scene, width, height, camera, image, i*deltaHeight, deltaHeight, shader));
        exe.shutdown();
        while(!exe.isTerminated());
    }

    public void renderFrame(){
        renderImage(frameBuffer);
        // BufferedImage tempBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
        // frameBuffer = tempBuffer;
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
        Shader backup = this.shader;
        this.shader = shader;
        String name = shader.getName();

        long start = System.nanoTime();
        renderImage(frameBuffer);
        if(timed) System.out.printf("%s Rendering took: %s ms%n",name, (System.nanoTime()-start)/1_000_000);

        start = System.nanoTime();
        writeImage(name);
        if(timed) System.out.printf("%s Saving took:    %s ms%n",name, (System.nanoTime()-start)/1_000_000);
        this.shader = backup;
    }

    public void timedRender(Shader shader, int count){
        Shader backup = this.shader;
        this.shader = shader;
        String name = shader.getName();
        scene = Scene.randomSpheres(100);
        BufferedImage image = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);
        
        long start = System.nanoTime();
        for (int i = 0; i < count; i++) renderImage(image);
        System.out.printf("%s Saving took:    %s ms%n",name, (System.nanoTime()-start)/1_000_000);
        this.shader = backup;
    }

    public void writeImage(String name){
        File file = new File("./images/"+name+".png");
        try { ImageIO.write(frameBuffer, "png", file); } catch (Exception e) {}
    }

}
