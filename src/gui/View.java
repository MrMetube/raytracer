package gui;

import java.awt.Graphics;
import java.awt.image.BufferedImage;
import javax.swing.JPanel;

public class View extends JPanel {
    BufferedImage image;

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
    }
}
