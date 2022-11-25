package gui;

import javax.swing.*;

import java.awt.*;

public class Window extends JFrame{
    ImageIcon[] images = new ImageIcon[4];
    JLabel[] labels = new JLabel[4];

    public Window(){

        setLayout(new GridLayout(2,2));

        getNewImages();

        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setVisible(true);
        pack();
        setSize(800, 800);
        setResizable(false);
        setTitle("Output");
    }

    public void getNewImages(){
        images[0] = new ImageIcon("./images/AmbientShader.png",  "Ambient Color");
        images[1] = new ImageIcon("./images/DiffuseShader.png",  "Diffuse Color");
        images[2] = new ImageIcon("./images/SpecularShader.png", "Specular Color");
        images[3] = new ImageIcon("./images/LightShader.png",    "Light Color");

        for (ImageIcon image : images)
            image.setImage(image.getImage().getScaledInstance(400, 400, Image.SCALE_DEFAULT));

        for (JLabel label : labels) if(label != null) remove(label);

        labels[0] = new JLabel(images[0]);
        labels[1] = new JLabel(images[1]);
        labels[2] = new JLabel(images[2]);
        labels[3] = new JLabel(images[3]);

        for (JLabel label : labels) add(label);
        pack();
    }
}
