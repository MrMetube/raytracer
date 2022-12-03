package gui;

import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.awt.event.MouseEvent;
import java.util.HashMap;
import java.util.HashSet;

import javax.swing.event.MouseInputListener;
import java.awt.Robot;

import math.Vector;
import shader.*;

public class Input implements KeyListener, MouseInputListener {

    HashMap<Integer,Object> keyMap = new HashMap<>();
    HashSet<Vector> activeKeys = new HashSet<>();
    float xOffset = 0;
    float yOffset = 0;
    Robot robot;
    boolean captureMouse = false;
    Window window;
    
    public Input(Window viewport){
        this.window = viewport;
        setupKeyMap();
        try{ robot = new Robot(); }catch(Exception e){}
    }

    public Vector getCamMove(){ 
        Vector dir = Vector.ZERO;
        for (Vector v : activeKeys) dir = dir.add(v);
        return dir;
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

        keyMap.put(KeyEvent.VK_1, new Ambient());
        keyMap.put(KeyEvent.VK_2, new Diffuse());
        keyMap.put(KeyEvent.VK_3, new Specular());
        keyMap.put(KeyEvent.VK_4, new Phong());
        keyMap.put(KeyEvent.VK_5, new BlinnPhong());
    }

    @Override
    public void keyPressed(KeyEvent e) {
        Object o = keyMap.get(e.getKeyCode());
        if( o instanceof Vector) activeKeys.add((Vector)o);
        else if( o instanceof Shader) window.setActiveShader((Shader) o);
        else if(e.getKeyCode()==KeyEvent.VK_F12){
            System.out.println("Screenshot saved");
            window.world.renderToFile(new Ambient(), false);
            window.world.renderToFile(new Diffuse(), false);
            window.world.renderToFile(new Specular(), false);
            window.world.renderToFile(new Phong(), false);
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
            float mouseSensitivity = 1;

            int centerX = window.getX() + window.getWidth() / 2;
            int centerY = window.getY() + window.getHeight() / 2;

            xOffset = ((float) e.getXOnScreen() - centerX) / window.getWidth();
            yOffset = ((float) e.getYOnScreen() - centerY) / window.getHeight();
            
            // TODO Rotation isnt working yet
            // robot.mouseMove(centerX, centerY);
        }
        // System.out.printf("xOffset: %s, yOffset: %s %n", mouseXOffset,mouseYOffset);
    }

    public double getYOffset(){ return yOffset; }
    public double getXOffset(){ return xOffset; }

    @Override public void mouseClicked(MouseEvent e)  { captureMouse = !captureMouse;}
    @Override public void mouseEntered(MouseEvent e)  {}
    @Override public void mouseExited(MouseEvent e)   {}
    @Override public void mousePressed(MouseEvent e)  {}
    @Override public void mouseReleased(MouseEvent e) {}
    @Override public void mouseDragged(MouseEvent e)  {}
    @Override public void keyTyped(KeyEvent e)        {}

}
