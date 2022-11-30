package gui;
import java.awt.Graphics;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.awt.image.BufferedImage;
import java.io.File;

import javax.imageio.ImageIO;
import javax.swing.ImageIcon;
import javax.swing.JLabel;
import javax.swing.JPanel;

import math.Vector;
import raytracer.Camera;
import raytracer.Scene;
import shader.Shader;

public class Viewport extends JPanel implements KeyListener{
    BufferedImage frameBuffer;
    ImageIcon image;
    JLabel label;
    Vector camMovement = Vector.ZERO;

    public Viewport(int width, int height){
        setFocusable(true);
        requestFocus();
        setVisible(true);
        setSize(width, height);
        frameBuffer = new BufferedImage(getWidth(),getHeight(),BufferedImage.TYPE_INT_RGB);
    }

    public void renderScene(Scene scene, Shader shader){
        BufferedImage tempBuffer;
        while(true){
            tempBuffer = new BufferedImage(getWidth(),getHeight(),BufferedImage.TYPE_INT_RGB);
            scene.renderImage(shader, tempBuffer);
            Camera camera = scene.getCamera();
            camera.move(camMovement);
            frameBuffer = tempBuffer;
            paintImmediately(0,0,getWidth(),getHeight());
        }
    }

    @Override
    public void paint(Graphics g) {
        if(frameBuffer != null) g.drawImage(frameBuffer, 0, 0, this);
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

    @Override
    public void keyTyped(KeyEvent e) {}

    @Override
    public void keyPressed(KeyEvent e) {
        switch(e.getKeyCode()){
            case KeyEvent.VK_D : 
                camMovement = camMovement.add(Vector.Xneg);
                break;
            case KeyEvent.VK_A : 
                camMovement = camMovement.add(Vector.Xpos);
                break;
            case KeyEvent.VK_S : 
                camMovement = camMovement.add(Vector.Zneg);
                break;
            case KeyEvent.VK_W : 
                camMovement = camMovement.add(Vector.Zpos);
                break;
            case KeyEvent.VK_SPACE : 
                camMovement = camMovement.add(Vector.Ypos);
                break;
            case KeyEvent.VK_SHIFT : 
                camMovement = camMovement.add(Vector.Yneg);
                break;
            default:
                break;
        }
        System.out.println(camMovement);
        
    }

    @Override
    public void keyReleased(KeyEvent e) {
        switch(e.getKeyCode()){
            case KeyEvent.VK_D : 
                camMovement = camMovement.sub(Vector.Xneg);
                break;
            case KeyEvent.VK_A : 
                camMovement = camMovement.sub(Vector.Xpos);
                break;
            case KeyEvent.VK_S : 
                camMovement = camMovement.sub(Vector.Zneg);
                break;
            case KeyEvent.VK_W : 
                camMovement = camMovement.sub(Vector.Zpos);
                break;
            case KeyEvent.VK_SPACE : 
                camMovement = camMovement.sub(Vector.Ypos);
                break;
            case KeyEvent.VK_SHIFT : 
                camMovement = camMovement.sub(Vector.Yneg);
                break;
            default:
                break;
        }
        System.out.println(camMovement);
    }
}
