package gui;

import java.awt.Frame;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

import javax.swing.JButton;
import javax.swing.JFileChooser;
import javax.swing.JFrame;
import javax.swing.JTextField;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import scene.Scene;
import shader.AmbientShader;
import shader.DiffuseShader;
import shader.LightShader;
import shader.SpecularShader;

public class App extends JFrame implements ActionListener {
    
    JTextField field = new JTextField("simple");
    JButton render = new JButton("Render");
    JButton open = new JButton("Open");
    JFileChooser chooser = new JFileChooser("./scenes/");
    Window window;

    public App(){
        render.setBounds(100,160,200,40);
        render.setFocusable(false);
        render.addActionListener(this);

        add(render);

        open.setBounds(100,40,200,40);
        open.setFocusable(false);
        open.addActionListener(this);
        
        add(open);

        chooser.setDialogTitle("Scene auswählen");

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
        if(e.getSource() == render || e.getSource() == field) {
            Scene s = new Scene("./scenes/"+field.getText()+".json");

            s.makeImage(new AmbientShader());
            s.makeImage(new DiffuseShader());
            s.makeImage(new SpecularShader());
            s.makeImage(new LightShader());

            if(window == null) window = new Window();
            else {
                if(window.getState() == Frame.ICONIFIED) window.setState(Frame.NORMAL);
                window.getNewImages();
            }
        }else if(e.getSource() == open){
            chooser.setFileSelectionMode(JFileChooser.FILES_ONLY);
            
            FileFilter filter = new FileNameExtensionFilter("JSON File","json");
            chooser.addChoosableFileFilter(filter);
            chooser.setAcceptAllFileFilterUsed(false);

            int returnVal = chooser.showOpenDialog(this);

            if (returnVal == JFileChooser.APPROVE_OPTION) {
                String s = chooser.getSelectedFile().getName().replace(".json", "");
                field.setText(s);
            } else System.out.println("Open command cancelled by user.");
        }
        
    }
}
