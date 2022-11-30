package gui;
import java.awt.Graphics;
import javax.swing.JPanel;

import raytracer.Scene;
import shader.Shader;

public class Viewport extends JPanel{
    World tn;

    public Viewport(int width, int height){
        setSize(width,height);
        setVisible(true);
        tn = new World(getWidth(), getHeight());
    }

    public void renderScene(Scene scene, Shader shader){
        while(true){
            tn.renderScene(scene, shader);
            paintImmediately(0,0,getWidth(),getHeight());
        }
    }

    @Override
    public void paint(Graphics g) {
        if(tn.getFrameBuffer() != null) g.drawImage(tn.getFrameBuffer(), 0, 0, this);
    }
    
}
