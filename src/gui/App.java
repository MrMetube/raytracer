package gui;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

import javax.swing.JButton;
import javax.swing.JFrame;
import javax.swing.JTextField;

import scene.Scene;
import shader.AmbientShader;
import shader.DiffuseShader;
import shader.LightShader;
import shader.SpecularShader;

public class App extends JFrame implements ActionListener {
    
    JTextField field = new JTextField("simple");
    JButton button = new JButton("Render");
    Window window;

    public App(){
        button.setBounds(100,160,200,40);
        button.setFocusable(false);
        button.addActionListener(this);
        
        add(button);

        field.setBounds(100,100,200,40);
        field.addActionListener(this);
        add(field);
        
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setSize(400,400);
        setLayout(null);
        setVisible(true);
    }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource() == button || e.getSource() == field) {
            Scene s = new Scene("./scenes/"+field.getText()+".json");

            s.makeImage(new AmbientShader());
            s.makeImage(new DiffuseShader());
            s.makeImage(new SpecularShader());
            s.makeImage(new LightShader());

            if(window == null) window = new Window();
            else window.getNewImages();
            
        }
        
    }
}
