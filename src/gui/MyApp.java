package gui;

import java.awt.Graphics;
import java.awt.image.BufferedImage;

import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JPanel;

import math.Vector;
import raytracer.Scene;
import shader.Shader;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.util.HashMap;

public class MyApp extends JFrame implements KeyListener{
    JLabel label;
    JPanel panel;
    BufferedImage image;
    HashMap<Integer,Vector> keyMap = new HashMap<>();

    public MyApp(int width, int height){
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setTitle("Raytracer");
        setSize(width,height);
        setLayout(null);
        setVisible(true);
        setLocationRelativeTo(null);
        setupKeyMap();
        addKeyListener(this);
    }

    public void setImage(BufferedImage image){
        this.image = image;
        repaint(0,0,getWidth(),getHeight());
    }

    @Override
    public void paint(Graphics g) {
        if(image != null) g.drawImage(image, 0, 0, this);
    }
    
    public void setupKeyMap(){
        keyMap.put(KeyEvent.VK_A, Vector.Xpos);
        keyMap.put(KeyEvent.VK_D, Vector.Xneg);
        keyMap.put(KeyEvent.VK_S, Vector.Zpos);
        keyMap.put(KeyEvent.VK_W, Vector.Zneg);
        keyMap.put(KeyEvent.VK_SPACE, Vector.Ypos);
        keyMap.put(KeyEvent.VK_SHIFT, Vector.Yneg);
    }

    @Override
    public void keyTyped(KeyEvent e) {
        System.out.println(e.getKeyCode());
    }

    @Override
    public void keyPressed(KeyEvent e) {
        Vector v = keyMap.get(e);
        if(v==null) return;
        camMovement = camMovement.add(v);
        System.out.println(camMovement);
    }

    @Override
    public void keyReleased(KeyEvent e) {
        Vector v = keyMap.get(e);
        if(v==null) return;
        camMovement = camMovement.sub(v);
        System.out.println(camMovement);
    }
}
