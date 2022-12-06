package gui;

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

public class Input implements KeyListener, MouseInputListener {

    HashMap<Integer,Object> keyMap = new HashMap<>();
    HashSet<Vector> activeKeys = new HashSet<>();
    float xOffset = 0;
    float yOffset = 0;
    Robot robot;
    boolean captureMouse = false;
    World world;
    
    public Input(World world){
        this.world = world;
        setupKeyMap();
        try{ robot = new Robot(); }catch(Exception e){}
    }

    public void setupKeyMap(){
        keyMap.put(KeyEvent.VK_D,     Vector.Xpos);
        keyMap.put(KeyEvent.VK_A,     Vector.Xneg);
        keyMap.put(KeyEvent.VK_W,     Vector.Zpos);
        keyMap.put(KeyEvent.VK_S,     Vector.Zneg);
        keyMap.put(KeyEvent.VK_RIGHT, Vector.Xpos);
        keyMap.put(KeyEvent.VK_LEFT,  Vector.Xneg);
        keyMap.put(KeyEvent.VK_UP,    Vector.Zpos);
        keyMap.put(KeyEvent.VK_DOWN,  Vector.Zneg);
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
            if( o instanceof Vector) activeKeys.add((Vector)o);
        else if( o instanceof Shader) {
            world.setShader((Shader) o);
            System.out.println("Shader: " + (Shader) o);
        }else if( o instanceof SupersamplingMode) {
            world.setSupersampling((SupersamplingMode) o);
            System.out.println("Supersamplingmode: " + ((SupersamplingMode) o).name());
        }else if(e.getKeyCode()==KeyEvent.VK_F12){
            world.renderToFile(new Ambient(), false);
            world.renderToFile(new Diffuse(), false);
            world.renderToFile(new Specular(), false);
            world.renderToFile(new Phong(), false);
            world.renderToFile(new BlinnPhong(), false);
            System.out.println("Screenshot saved");
        }
    }

    @Override
    public void keyReleased(KeyEvent e) {
        Object o = keyMap.get(e.getKeyCode());
        if(o instanceof Vector) activeKeys.remove((Vector)o);
    }
    
    @Override
    public void mouseMoved(MouseEvent e) {
        if(captureMouse) {
            // float mouseSensitivity = 1;

            // int centerX = window.getX() + window.getWidth() / 2;
            // int centerY = window.getY() + window.getHeight() / 2;

            // xOffset = ((float) e.getXOnScreen() - centerX) / window.getWidth();
            // yOffset = ((float) e.getYOnScreen() - centerY) / window.getHeight();
            
            // TODO Rotation
            // robot.mouseMove(centerX, centerY);
        }
        // System.out.printf("xOffset: %s, yOffset: %s %n", mouseXOffset,mouseYOffset);
    }

    public double getXOffset(){ return xOffset; }
    public double getYOffset(){ return yOffset; }

    public Vector getCamMove(){ 
        Vector dir = Vector.ZERO;
        for (Vector vector : activeKeys) dir = dir.add(vector);
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
