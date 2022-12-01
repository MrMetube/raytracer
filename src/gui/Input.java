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

    HashMap<Integer,Vector> keyMap = new HashMap<>();
    HashSet<Vector> activeKeys = new HashSet<>();
    float cameraYaw = 0;
    float cameraPitch = 0;
    Robot robot;
    
    public Input(){
        
        setupKeyMap();
        try{ robot = new Robot(); }catch(Exception e){}

    }

    public Vector getCamDir(){ 
        Vector dir = Vector.ZERO;
        for (Vector v : activeKeys) dir = dir.add(v);
        return dir;
    }

    public void setupKeyMap(){
        keyMap.put(KeyEvent.VK_D, Vector.Xpos);
        keyMap.put(KeyEvent.VK_A, Vector.Xneg);
        keyMap.put(KeyEvent.VK_W, Vector.Zpos);
        keyMap.put(KeyEvent.VK_S, Vector.Zneg);
        keyMap.put(KeyEvent.VK_SPACE, Vector.Ypos);
        keyMap.put(KeyEvent.VK_SHIFT, Vector.Yneg);
    }

    @Override
    public void keyTyped(KeyEvent e) { /* System.out.println(e.getKeyChar()); */ }

    @Override
    public void keyPressed(KeyEvent e) {
        Vector v = keyMap.get(e.getKeyCode());
        if(v!=null) activeKeys.add(v);
        else if(e.getKeyCode()==KeyEvent.VK_F12){
            System.out.println("Screenshot saved");
            Menu.world.renderToFile(new AmbientShader(), false);
            Menu.world.renderToFile(new DiffuseShader(), false);
            Menu.world.renderToFile(new SpecularShader(), false);
            Menu.world.renderToFile(new PhongShader(), false);
        }
    }

    @Override
    public void keyReleased(KeyEvent e) {
        Vector v = keyMap.get(e.getKeyCode());
        if(v!=null) activeKeys.remove(v);
    }
    
    @Override
    public void mouseClicked(MouseEvent e) {}

    @Override
    public void mousePressed(MouseEvent e) {}

    @Override
    public void mouseReleased(MouseEvent e) { System.out.println(e); }

    @Override
    public void mouseEntered(MouseEvent e) {}

    @Override
    public void mouseExited(MouseEvent e) {}

    @Override
    public void mouseDragged(MouseEvent e) { System.out.println(e); }

    @Override
    public void mouseMoved(MouseEvent e) {
        System.out.println(e);
        float mouseSensitivity = 1;

        int centerX = Menu.viewport.getX() + Menu.viewport.getWidth() / 2;
        int centerY = Menu.viewport.getY() + Menu.viewport.getHeight() / 2;

        int mouseXOffset = e.getXOnScreen() - centerX;
        int mouseYOffset = e.getYOnScreen() - centerY;
        cameraYaw = (cameraYaw + mouseXOffset * mouseSensitivity);
        cameraPitch = (Math.min(90, Math.max(-90, cameraPitch + mouseYOffset * mouseSensitivity)));
        robot.mouseMove(centerX, centerY);
        System.out.printf("xOffset: %s, yOffset: %s %n", mouseXOffset,mouseYOffset);
    }
}
