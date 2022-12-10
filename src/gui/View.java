package gui;

import java.awt.Font;
import java.awt.Graphics;
import java.awt.image.BufferedImage;
import javax.swing.JPanel;

public class View extends JPanel {
    BufferedImage image;
    long time;
    int counter = 0;
    int maxfps = 0;
    int minfps = 2000;
    int showFps = 0;

    public View(int width, int height){
        super();
        setSize(width,height);
    }

    public void setImage(BufferedImage image){
        this.image = image;
        repaint(0,0,getWidth(),getHeight());
    }

    public void toggleFPS(){
        showFps++;
        showFps %= 3;
    }

    @Override
    public void paint(Graphics g) {
        super.paint(g);
        if(image != null) g.drawImage(image, 0, 0, this);
        
            counter++;
            double dif = System.nanoTime()-time;
            long fps = Math.round(1_000_000_000/dif);
        if(showFps >= 1){
            g.setColor(java.awt.Color.yellow);
            g.setFont(new Font("Verdana", Font.BOLD, 18));
            g.drawString(String.format("%d FPS",fps), 700, 20);
            if(showFps > 1){
                maxfps = Math.max((counter%50 == 0) ? 0 : maxfps, (int)fps);
                minfps = Math.min((counter%50 == 0) ? 2000 : minfps, (int)fps);
                g.drawString(String.format("%d min",minfps), 700, 40);
                g.drawString(String.format("%d max",maxfps), 700, 60);
            }
        }
        time = System.nanoTime();
    }
}
