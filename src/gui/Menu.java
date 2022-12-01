package gui;


import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

import javax.swing.JButton;
import javax.swing.JComboBox;
import javax.swing.JFileChooser;
import javax.swing.JFrame;
import javax.swing.JSlider;
import javax.swing.event.ChangeEvent;
import javax.swing.event.ChangeListener;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import raytracer.Scene;
import shader.*;

public class Menu extends JFrame implements ActionListener, ChangeListener {
    
    JButton render = new JButton("Render Scene");
    JButton open = new JButton("Open Scene");
    JButton random = new JButton("Random Scene");
    JSlider slider = new JSlider(0, 500, 250);
    JFileChooser chooser = new JFileChooser("./scenes/");
    JComboBox<Shader> shaderList = new JComboBox<>();

    int randomCount = 250;
    String fileName = "simple.json";
    Shader activeShader = new PhongShader();
    World world;
    Viewport viewport;

    public Menu(){
        int btnWidth = 160;
        int btnHeight = 40;

        shaderList.addItem(new AmbientShader());
        shaderList.addItem(new DiffuseShader());
        shaderList.addItem(new SpecularShader());
        shaderList.addItem(new PhongShader());
        shaderList.setSelectedIndex(3);
        shaderList.setBounds(220,20,btnWidth,btnHeight);
        shaderList.addActionListener(this);
        add(shaderList);

        open.setBounds(40,20,btnWidth,btnHeight);
        open.setFocusable(false);
        open.addActionListener(this);
        add(open);

        chooser.setDialogTitle("Scene auswählen");

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

        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setTitle("Raytracer");
        setSize(1000,1000);
        setLayout(null);
        setVisible(true);
        setLocationRelativeTo(null);

        setFocusTraversalKeysEnabled(false);
    }

    public void start(Scene scene, Shader shader){
        int height = 800, width = height;
        World world = new World(width,height,scene);
        new Viewport(width,height,world,shader);
    }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource() == render) {
            start(new Scene("./scenes/"+fileName),activeShader);
        }else if(e.getSource() == open){
            chooser.setFileSelectionMode(JFileChooser.FILES_ONLY);
            
            FileFilter filter = new FileNameExtensionFilter("JSON File","json");
            chooser.addChoosableFileFilter(filter);
            chooser.setAcceptAllFileFilterUsed(false);

            int returnVal = chooser.showOpenDialog(this);

            if (returnVal == JFileChooser.APPROVE_OPTION) {
                fileName = chooser.getSelectedFile().getName();
            } else System.out.println("Open command cancelled by user.");
        }else if(e.getSource() == random){
            start(Scene.randomSpheres(randomCount),activeShader);
        }else if(e.getSource() == shaderList){
            activeShader = (Shader) shaderList.getSelectedItem();
        }
        
    }

    @Override
    public void stateChanged(ChangeEvent e) {
        if(e.getSource() == slider){
            randomCount = slider.getValue();
        }
    }
}
