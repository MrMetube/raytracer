package gui;
import java.awt.Graphics;
import java.awt.image.BufferedImage;
import java.io.File;

import javax.imageio.ImageIO;
import javax.swing.ImageIcon;
import javax.swing.JLabel;
import javax.swing.JPanel;

import raytracer.Scene;
import shader.Shader;

public class Viewport extends JPanel{
    BufferedImage frameBuffer;
    ImageIcon image;
    JLabel label;

    public Viewport(int width, int height){
        setVisible(true);
        setSize(width, height);
        frameBuffer = new BufferedImage(getWidth(),getHeight(),BufferedImage.TYPE_INT_RGB);
        
    }

    public void render(Scene scene, Shader shader){
        // while(true){
            BufferedImage tempBuffer = new BufferedImage(getWidth(),getHeight(),BufferedImage.TYPE_INT_RGB);
            scene.renderImage(shader, tempBuffer);
            frameBuffer = tempBuffer;
            repaint();
        // }
    }

    @Override
    public void paint(Graphics g) {
        image.setImage(frameBuffer);
        label = new JLabel(image);
        add(label);
        g.drawImage(frameBuffer, 0, 0, this);
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
}
