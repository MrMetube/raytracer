package gui;

import java.awt.Graphics;
import java.awt.image.BufferedImage;

import javax.swing.JFrame;
import javax.swing.Timer;

import math.Vector;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

public class Viewport extends JFrame implements ActionListener{
    BufferedImage image;
    Vector camMovement = Vector.ZERO;
    Timer clock = new Timer(1000/60, this);

    World world = Menu.world;
    Input input = Menu.input;
    
    public Viewport(int width, int height){
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
        setTitle("Raytracer");
        setSize(width,height);
        setLayout(null);
        setVisible(true);
        setLocationRelativeTo(null);
        addMouseListener(input);
        addKeyListener(input);
        
        clock.start();
    }

    public void setImage(BufferedImage image){
        this.image = image;
        repaint(0,0,getWidth(),getHeight());
    }

    @Override
    public void paint(Graphics g) {
        if(image != null) g.drawImage(image, 0, 0, this);
    }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource()==clock){
            world.tick();
            world.renderFrame(Menu.getActiveShader());
            setImage(world.getFrameBuffer());
        }
        
    }
}
