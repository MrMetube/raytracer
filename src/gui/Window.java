package gui;


import java.awt.*;
import java.awt.event.*;
import java.awt.image.BufferedImage;

import javax.swing.*;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import math.Vector;
import raytracer.Scene;
import shader.Phong;
import shader.Shader;

public class Window extends JFrame implements ActionListener{
    JFileChooser chooser;

    JMenuItem fileItem;
    JMenuItem rndmItem;
    JMenuItem quitItem;

    View view;

    int randomCount = 100;
    String fileName = "simple.json";

    static Shader activeShader = new Phong();
    static Scene activeScene = Scene.EMPTY;

    private static int width = 800;
    private static int height = 800;

    public World world = new World(width, height, this);
    public Input input = new Input(this);

    BufferedImage image;
    Vector camMovement = Vector.ZERO;
    Timer clock = new Timer(16, this);

    public Window(){
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setTitle("Raytracer");
        setSize(800,800);
        setResizable(false);
        setLocationRelativeTo(null);
        setFocusTraversalKeysEnabled(false);
        
        JMenuBar menubar = new JMenuBar();
        JMenu sceneMenu = new JMenu("Scene");

        fileItem = new JMenuItem("Open File",KeyEvent.VK_F);
        rndmItem = new JMenuItem("Random Scene",KeyEvent.VK_R);
        quitItem = new JMenuItem("Quit",KeyEvent.VK_Q);

        fileItem.addActionListener(this);
        rndmItem.addActionListener(this);
        quitItem.addActionListener(this);

        sceneMenu.setMnemonic(KeyEvent.VK_C);
        sceneMenu.add(fileItem); 
        sceneMenu.add(rndmItem); 
        sceneMenu.add(quitItem); 

        menubar.add(sceneMenu);
        setJMenuBar(menubar);

        chooser = new JFileChooser("./scenes/");
        chooser.setDialogTitle("Scene auswählen");
        chooser.setFileSelectionMode(JFileChooser.FILES_ONLY);
        chooser.addChoosableFileFilter((FileFilter) new FileNameExtensionFilter("JSON File","json"));
        chooser.setAcceptAllFileFilterUsed(false);

        view = new View(width,height);
        view.setBounds(0, 100, width, 700);
        add(view);

        BufferedImage cursorImg = new BufferedImage(16,16, BufferedImage.TYPE_INT_ARGB);
        Cursor blank = Toolkit.getDefaultToolkit().createCustomCursor(cursorImg, new Point(0,0), "blank");
        getContentPane().setCursor(blank);

        addMouseListener(input);
        addMouseMotionListener(input);
        addKeyListener(input);

        setVisible(true);
        clock.start();
    }

    
    public void setActiveScene(Scene scene){ activeScene = scene; }
    public void setActiveShader(Shader shader){ activeShader = shader; }

    public Shader getActiveShader(){ return activeShader; }
    public Scene getActiveScene(){ return activeScene; }

    @Override
    public void actionPerformed(ActionEvent e) {
             if(e.getSource() == rndmItem) activeScene = Scene.randomSpheres(randomCount);
        else if(e.getSource() == fileItem && chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION){
            activeScene = new Scene("./scenes/" + chooser.getSelectedFile().getName());
        }else if(e.getSource() == clock && hasFocus()){
            world.tick();
            world.renderFrame();
            view.setImage(world.getFrameBuffer());
        }else if(e.getSource() == quitItem) System.exit(0);
    }
}
