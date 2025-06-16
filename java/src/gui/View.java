package gui;

import java.awt.Font;
import java.awt.Graphics;
import java.awt.image.BufferedImage;
import javax.swing.JPanel;
public class View extends JPanel {
    final Font font = new Font(Font.MONOSPACED, Font.BOLD, 18);
    BufferedImage image;
    long time;
    int counter = 0;
    boolean showFps = false;

    public View(int width, int height){
        super();
        setSize(width,height);
    }

    public void setImage(BufferedImage image){
        this.image = image;
        repaint(0,0,getWidth(),getHeight());
    }

    public void toggleFPS(){
        showFps = !showFps;
    }

    @Override
    public void paint(Graphics g) {
        super.paint(g);
        if(image != null)
            g.drawImage(image, 0, 0, this);
        
        counter++;
        double dif = System.nanoTime()-time;
        long fps = Math.round(1_000_000_000/dif);

        if(showFps){
            g.setColor(java.awt.Color.yellow);
            g.setFont(font);
            g.drawString(String.format("%d FPS",fps), getWidth()-100, 20);
        }
        time = System.nanoTime();
    }
}
