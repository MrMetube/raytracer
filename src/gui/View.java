package gui;

import java.awt.Graphics;
import java.awt.image.BufferedImage;
import javax.swing.JPanel;

public class View extends JPanel {
    BufferedImage image;
    long time;
    int counter = 0;
    int maxfps = 0;
    int minfps = 2000;

    public View(int width, int height){
        super();
        setSize(width,height);
    }

    public void setImage(BufferedImage image){
        this.image = image;
        repaint(0,0,getWidth(),getHeight());
    }

    @Override
    public void paint(Graphics g) {
        super.paint(g);
        if(image != null) g.drawImage(image, 0, 0, this);
        
        counter++;
        double dif = System.nanoTime()-time;
        long fps = Math.round(1_000_000_000/dif);
        maxfps = Math.max((counter%50 == 0) ? 0 : maxfps, (int)fps);
        minfps = Math.min((counter%50 == 0) ? 2000 : minfps, (int)fps);

        g.drawString(String.format("%d FPS",fps), 5, 15);
        g.drawString(String.format("%d minFPS",minfps), 5, 30);
        g.drawString(String.format("%d maxFPS",maxfps), 5, 45);

        
        time = System.nanoTime();
    }
}
