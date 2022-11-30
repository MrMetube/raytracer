package gui;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

import javax.swing.JButton;
import javax.swing.JFileChooser;
import javax.swing.JFrame;
import javax.swing.JPanel;
import javax.swing.JSlider;
import javax.swing.JTextField;
import javax.swing.event.ChangeEvent;
import javax.swing.event.ChangeListener;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import scene.Scene;
import shader.AmbientShader;
import shader.DiffuseShader;
import shader.PhongShader;
import shader.SpecularShader;

public class App extends JFrame implements ActionListener, ChangeListener {
    
    JTextField field = new JTextField("simple");
    JButton render = new JButton("Render Scene");
    JButton open = new JButton("Open Scene");
    JButton random = new JButton("Random Scene");
    JSlider slider = new JSlider(0, 500, 250);
    JFileChooser chooser = new JFileChooser("./scenes/");
    JPanel panel = new JPanel();
    ImagePanel images = new ImagePanel();

    int RND_COUNT = 250;

    public App(){
        int btnWidth = 160;
        int btnHeight = 40;
        open.setBounds(40,20,btnWidth,btnHeight);
        open.setFocusable(false);
        open.addActionListener(this);
        
        add(open);

        chooser.setDialogTitle("Scene auswählen");

        field.setBounds(220,20,btnWidth,btnHeight);
        field.addActionListener(this);
        add(field);

        render.setBounds(400,20,btnWidth,btnHeight);
        render.setFocusable(false);
        render.addActionListener(this);
        add(render);

        random.setBounds(580,20,btnWidth,btnHeight);
        random.addActionListener(this);
        add(random);

        slider.setBounds(760, 20, btnWidth, 60);
        slider.addChangeListener(this);
        slider.setPaintTicks(true);
        slider.setSnapToTicks(true);
        slider.setMinorTickSpacing(50);
        slider.setMajorTickSpacing(250);
        slider.setPaintLabels(true);
        add(slider);

        panel.setBounds(100, 100, 800, 800);
        panel.add(images);
        add(panel);
        
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setTitle("Raytracer");
        setSize(1000,1000);
        setLayout(null);
        setVisible(true);
        setLocationRelativeTo(null);
    }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource() == render || e.getSource() == field) {
            Scene s = new Scene("./scenes/"+field.getText()+".json");

            s.makeImage(new AmbientShader());
            s.makeImage(new DiffuseShader());
            s.makeImage(new SpecularShader());
            s.makeImage(new PhongShader());

            images.getNewImages();
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
        }else if(e.getSource() == random){
            Scene s = Scene.randomSpheres(RND_COUNT);

            s.makeImage(new AmbientShader());
            s.makeImage(new DiffuseShader());
            s.makeImage(new SpecularShader());
            s.makeImage(new PhongShader());

            images.getNewImages();
        }
        
    }

    @Override
    public void stateChanged(ChangeEvent e) {
        if(e.getSource() == slider){
            RND_COUNT = slider.getValue();
        }
    }
}
