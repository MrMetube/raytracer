package gui;

import java.awt.Graphics;
import java.awt.image.BufferedImage;

import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.Timer;
import javax.swing.event.MouseInputListener;

import math.Vector;
import raytracer.Scene;
import shader.*;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.awt.event.MouseEvent;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.util.HashMap;
import java.util.HashSet;
import java.awt.Robot;

public class Viewport extends JFrame implements KeyListener, ActionListener, MouseInputListener{
    JLabel label;
    JPanel panel;
    BufferedImage image;
    Vector camMovement = Vector.ZERO;
    HashMap<Integer,Vector> keyMap = new HashMap<>();
    HashSet<Vector> activeKeys = new HashSet<>();
    World world;
    Timer clock = new Timer(1000/60, this);
    Robot robot;
    float cameraYaw = 0;
    float cameraPitch = 0;
    Shader activeShader;
    
    public Viewport(int width, int height, World world, Shader shader){
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
        setTitle("Raytracer");
        setSize(width,height);
        setLayout(null);
        setVisible(true);
        setLocationRelativeTo(null);
        setupKeyMap();
        addKeyListener(this);
        
        this.world = world;
        activeShader = shader;
        world.setViewport(this);
        
        clock.start();
        try{ robot = new Robot(); }catch(Exception e){}
    }

    public void setImage(BufferedImage image){
        this.image = image;
        repaint(0,0,getWidth(),getHeight());
    }

    @Override
    public void paint(Graphics g) {
        if(image != null) g.drawImage(image, 0, 0, this);
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
            world.renderToFile(new AmbientShader(), false);
            world.renderToFile(new DiffuseShader(), false);
            world.renderToFile(new SpecularShader(), false);
            world.renderToFile(new PhongShader(), false);
        }
    }

    @Override
    public void keyReleased(KeyEvent e) {
        Vector v = keyMap.get(e.getKeyCode());
        if(v!=null) activeKeys.remove(v);
    }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource()==clock){
            world.tick();
            world.renderFrame(activeShader);
            setImage(world.getFrameBuffer());
        }
        
    }

    @Override
    public void mouseClicked(MouseEvent e) { System.out.println(e); }

    @Override
    public void mousePressed(MouseEvent e) { System.out.println(e); }

    @Override
    public void mouseReleased(MouseEvent e) { System.out.println(e); }

    @Override
    public void mouseEntered(MouseEvent e) { System.out.println(e); }

    @Override
    public void mouseExited(MouseEvent e) { System.out.println(e); }

    @Override
    public void mouseDragged(MouseEvent e) { System.out.println(e); }

    @Override
    public void mouseMoved(MouseEvent e) {
        System.out.println(e);
        float mouseSensitivity = 1;

        int centerX = getX() + getWidth() / 2;
        int centerY = getY() + getHeight() / 2;

        int mouseXOffset = e.getXOnScreen() - centerX;
        int mouseYOffset = e.getYOnScreen() - centerY;
        cameraYaw = (cameraYaw + mouseXOffset * mouseSensitivity);
        cameraPitch = (Math.min(90, Math.max(-90, cameraPitch + mouseYOffset * mouseSensitivity)));
        robot.mouseMove(centerX, centerY);
    }
}
