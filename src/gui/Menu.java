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
    
    JButton open = new JButton("Open Scene");
    JButton random = new JButton("Random Scene");
    JSlider slider = new JSlider(0, 500, 250);
    JFileChooser chooser = new JFileChooser("./scenes/");
    JComboBox<Shader> shaderList = new JComboBox<>();

    int randomCount = 50;
    String fileName = "simple.json";

    static Shader activeShader = new PhongShader();
    static Scene activeScene = Scene.EMPTY;

    private static int height = 800, width = height;

    public static World world = new World(width, height);
    public static Viewport viewport;
    // public static Viewport viewport = new Viewport(width, height); // this doesnt work because focus is weird
    public static Input input = new Input();

    public Menu(){
        int btnWidth = 160;
        int btnHeight = 40;

        open.setBounds(40,20,btnWidth,btnHeight);
        open.setFocusable(false);
        open.addActionListener(this);
        add(open);

        shaderList.addItem(new AmbientShader());
        shaderList.addItem(new DiffuseShader());
        shaderList.addItem(new SpecularShader());
        shaderList.addItem(new PhongShader());
        shaderList.setSelectedIndex(3);
        shaderList.setBounds(220,20,btnWidth,btnHeight);
        shaderList.addActionListener(this);
        add(shaderList);

        chooser.setDialogTitle("Scene auswählen");

        random.setBounds(400,20,btnWidth,btnHeight);
        random.addActionListener(this);
        add(random);

        slider.setBounds(580, 20, btnWidth, 60);
        slider.addChangeListener(this);
        slider.setPaintTicks(true);
        slider.setSnapToTicks(true);
        slider.setMinorTickSpacing(50);
        slider.setMajorTickSpacing(250);
        slider.setPaintLabels(true);
        slider.setValue(randomCount);
        add(slider);

        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setTitle("Raytracer");
        setSize(800,150);
        setLayout(null);
        setVisible(true);
        // setLocationRelativeTo(null);
        setFocusTraversalKeysEnabled(false);
    }

    public void changeScene(Scene scene){
        activeScene = scene;
        if(viewport==null) viewport = new Viewport(width, height);
        viewport.setVisible(true);
        viewport.requestFocus();
    }

    public static void setActiveShader(Shader shader){ activeShader = shader; }
    public static Shader getActiveShader(){ return activeShader; }
    public static Scene getActiveScene(){ return activeScene; }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource() == random){
            changeScene(Scene.randomSpheres(randomCount));
        }else if(e.getSource() == shaderList){
            activeShader = (Shader) shaderList.getSelectedItem();
        }else if(e.getSource() == open){
            chooser.setFileSelectionMode(JFileChooser.FILES_ONLY);
            
            FileFilter filter = new FileNameExtensionFilter("JSON File","json");
            chooser.addChoosableFileFilter(filter);
            chooser.setAcceptAllFileFilterUsed(false);

            int returnVal = chooser.showOpenDialog(this);

            if (returnVal == JFileChooser.APPROVE_OPTION) {
                fileName = chooser.getSelectedFile().getName();
                changeScene(new Scene("./scenes/"+fileName));
            } else System.out.println("Open command cancelled by user.");
        }
        
    }

    @Override
    public void stateChanged(ChangeEvent e) {
        if(e.getSource() == slider){
            randomCount = slider.getValue();
        }
    }
}
