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
    Vector camMovement = Vector.ZERO;
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

    public Vector getCamMovement(){ return camMovement; }

    public void setupKeyMap(){
        keyMap.put(KeyEvent.VK_D, Vector.Xpos);
        keyMap.put(KeyEvent.VK_A, Vector.Xneg);
        keyMap.put(KeyEvent.VK_W, Vector.Zpos);
        keyMap.put(KeyEvent.VK_S, Vector.Zneg);
        keyMap.put(KeyEvent.VK_SPACE, Vector.Ypos);
        keyMap.put(KeyEvent.VK_SHIFT, Vector.Yneg);
    }

    @Override
    public void keyTyped(KeyEvent e) {
        System.out.println(e.getKeyChar());
    }

    @Override
    public void keyPressed(KeyEvent e) {
        Vector v = keyMap.get(e.getKeyCode());
        System.out.println(e.getKeyChar());
        if(v==null) return;
        camMovement = camMovement.add(v);
    }

    @Override
    public void keyReleased(KeyEvent e) {
        Vector v = keyMap.get(e.getKeyCode());
        if(v==null) return;
        camMovement = camMovement.sub(v);
    }
}
