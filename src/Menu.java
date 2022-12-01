

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.event.KeyEvent;
import java.awt.event.KeyListener;
import java.util.HashMap;

import javax.swing.ImageIcon;
import javax.swing.JButton;
import javax.swing.JComboBox;
import javax.swing.JFileChooser;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.JSlider;
import javax.swing.event.ChangeEvent;
import javax.swing.event.ChangeListener;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import math.Vector;
import raytracer.Camera;
import raytracer.Scene;
import shader.*;

public class Menu extends JFrame implements ActionListener, ChangeListener, KeyListener {
    
    JButton render = new JButton("Render Scene");
    JButton open = new JButton("Open Scene");
    JButton random = new JButton("Random Scene");
    JSlider slider = new JSlider(0, 500, 250);
    JFileChooser chooser = new JFileChooser("./scenes/");
    JComboBox<Shader> shaderList = new JComboBox<>();
    JPanel panel = new JPanel();

    HashMap<Integer,Vector> keyMap = new HashMap<>();
    Vector camMovement = Vector.ZERO;

    int randomCount = 250;
    String fileName = "simple";
    Shader activeShader = new PhongShader();

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

        setupKeyMap();
        setFocusTraversalKeysEnabled(false);
        addKeyListener(this);
    }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource() == render) {
            Main.start(new Scene("./scenes/"+fileName+".json"),activeShader);
        }else if(e.getSource() == open){
            chooser.setFileSelectionMode(JFileChooser.FILES_ONLY);
            
            FileFilter filter = new FileNameExtensionFilter("JSON File","json");
            chooser.addChoosableFileFilter(filter);
            chooser.setAcceptAllFileFilterUsed(false);

            int returnVal = chooser.showOpenDialog(this);

            if (returnVal == JFileChooser.APPROVE_OPTION) {
                fileName = chooser.getSelectedFile().getName().replace(".json", "");
            } else System.out.println("Open command cancelled by user.");
        }else if(e.getSource() == random){
            Main.start(Scene.randomSpheres(randomCount),activeShader);
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

    public void setupKeyMap(){
        keyMap.put(KeyEvent.VK_A, Vector.Xpos);
        keyMap.put(KeyEvent.VK_D, Vector.Xneg);
        keyMap.put(KeyEvent.VK_S, Vector.Zpos);
        keyMap.put(KeyEvent.VK_W, Vector.Zneg);
        keyMap.put(KeyEvent.VK_SPACE, Vector.Ypos);
        keyMap.put(KeyEvent.VK_SHIFT, Vector.Yneg);
    }

    @Override
    public void keyTyped(KeyEvent e) {
        System.out.println(e.getKeyCode());
    }

    @Override
    public void keyPressed(KeyEvent e) {
        Vector v = keyMap.get(e);
        if(v==null) return;
        camMovement = camMovement.add(v);
        System.out.println(camMovement);
    }

    @Override
    public void keyReleased(KeyEvent e) {
        Vector v = keyMap.get(e);
        if(v==null) return;
        camMovement = camMovement.sub(v);
        System.out.println(camMovement);
    }
}
