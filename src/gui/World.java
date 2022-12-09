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
import raytracer.Trace;
import raytracer.stuff.SupersamplingMode;
import shader.Phong;
import shader.Shader;

import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.awt.event.MouseEvent;
import java.util.HashMap;
import java.util.HashSet;

import javax.swing.event.MouseInputListener;
import java.awt.Robot;

import math.Vector;
import raytracer.stuff.SupersamplingMode;
import shader.*;

public class World implements KeyListener, MouseInputListener {
    BufferedImage frameBuffer;
    int width,height;
    Camera camera;

    Scene scene = new Scene();
    Shader shader = new Phong();
    SupersamplingMode supersampling = SupersamplingMode.NONE;

    HashMap<Integer,Object> keyMap = new HashMap<>();
    HashSet<Vector> moveKeys = new HashSet<>();
    float xOffset = 0;
    float yOffset = 0;
    boolean captureMouse = false;
    Robot robot;


    private double cameraSpeed = 0.2;
    int frameBufferCount = 0;

    public World(int width, int height){
        this.width = width;
        this.height = height;
        this.camera = new Camera(new Point(0, 0, -1), Point.ZERO, 90, this);
        frameBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);

        setupKeyMap();
        try{ robot = new Robot(); }catch(Exception e){}
    }


    public void tick(){
        Vector dir = getCamMove();
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
        // BufferedImage tempBuffer = new BufferedImage(width,height,BufferedImage.TYPE_INT_ARGB);
        // frameBuffer = tempBuffer;
        // I tried using an additive FrameBuffer, but it didnt work
        // Because when colors are turned to rgb ints their values are clamped to not break to format.
        // It would require storing the image as a 2D-Color-Array to not lose information between frames.
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
        System.out.printf("%s Rendering took:    %s ms%n",name, (System.nanoTime()-start)/1_000_000);
        this.shader = backup;
    }

    public void writeImage(String name){
        File file = new File("./images/"+name+".png");
        try { ImageIO.write(frameBuffer, "png", file); } catch (Exception e) {}
    }

    public void setupKeyMap(){
        keyMap.put(KeyEvent.VK_D,     Vector.Xpos);
        keyMap.put(KeyEvent.VK_A,     Vector.Xneg);
        keyMap.put(KeyEvent.VK_W,     Vector.Zpos);
        keyMap.put(KeyEvent.VK_S,     Vector.Zneg);
        keyMap.put(KeyEvent.VK_RIGHT, Double.valueOf(40));
        keyMap.put(KeyEvent.VK_LEFT,  Double.valueOf(-40));
        keyMap.put(KeyEvent.VK_UP,    Double.valueOf(-40));
        keyMap.put(KeyEvent.VK_DOWN,  Double.valueOf(40));
        keyMap.put(KeyEvent.VK_SPACE, Vector.Ypos);
        keyMap.put(KeyEvent.VK_SHIFT, Vector.Yneg);

        keyMap.put(KeyEvent.VK_1, new Phong());
        keyMap.put(KeyEvent.VK_2, new BlinnPhong());
        keyMap.put(KeyEvent.VK_3, new Specular());
        keyMap.put(KeyEvent.VK_4, new Diffuse());
        keyMap.put(KeyEvent.VK_5, new Ambient());
        keyMap.put(KeyEvent.VK_6, new Intersect());
        keyMap.put(KeyEvent.VK_7, new Normal());
        keyMap.put(KeyEvent.VK_8, new Distance());

        keyMap.put(KeyEvent.VK_F1, SupersamplingMode.NONE);
        keyMap.put(KeyEvent.VK_F2, SupersamplingMode.X4);
        keyMap.put(KeyEvent.VK_F3, SupersamplingMode.X9);
    }

     @Override
    public void keyPressed(KeyEvent e) {
        Object o = keyMap.get(e.getKeyCode());
             if( o instanceof Vector) moveKeys.add((Vector)o);
        else if( o instanceof Double) {
            camera.rotate((double)o, 0);
            System.out.println("Should rotate");
        }else if( o instanceof Shader) {
            setShader((Shader) o);
            System.out.println("Shader: " + (Shader) o);
        }else if( o instanceof SupersamplingMode) {
            setSupersampling((SupersamplingMode) o);
            System.out.println("Supersamplingmode: " + ((SupersamplingMode) o).name());
        }else if( e.getKeyCode()==KeyEvent.VK_F12){
            renderToFile(new Ambient(), false);
            renderToFile(new Diffuse(), false);
            renderToFile(new Specular(), false);
            renderToFile(new Phong(), false);
            renderToFile(new BlinnPhong(), false);
            System.out.println("Screenshot saved");
        }
    }

    @Override
    public void keyReleased(KeyEvent e) {
        Object o = keyMap.get(e.getKeyCode());
        if(o instanceof Vector) moveKeys.remove((Vector)o);
    }
    
    @Override
    public void mouseMoved(MouseEvent e) {
        if(captureMouse) {
            // float mouseSensitivity = 1;

            // int centerX = window.getX() + window.getWidth() / 2;
            // int centerY = window.getY() + window.getHeight() / 2;

            // xOffset = ((float) e.getXOnScreen() - centerX) / window.getWidth();
            // yOffset = ((float) e.getYOnScreen() - centerY) / window.getHeight();
            
            // todo Rotation
            // robot.mouseMove(centerX, centerY);
        }
        // System.out.printf("xOffset: %s, yOffset: %s %n", mouseXOffset,mouseYOffset);
    }

    public double getXOffset(){ return xOffset; }
    public double getYOffset(){ return yOffset; }

    public Vector getCamMove(){ 
        Vector dir = Vector.ZERO;
        for (Vector vector : moveKeys) dir = dir.add(vector);
        return dir;   
    }

    @Override public void mouseClicked(MouseEvent e)  { captureMouse = !captureMouse;}
    @Override public void mouseEntered(MouseEvent e)  {}
    @Override public void mouseExited(MouseEvent e)   {}
    @Override public void mousePressed(MouseEvent e)  {}
    @Override public void mouseReleased(MouseEvent e) {}
    @Override public void mouseDragged(MouseEvent e)  {}
    @Override public void keyTyped(KeyEvent e)        {}

}
