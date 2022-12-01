package gui;


import java.awt.*;
import java.awt.event.*;
import java.awt.image.BufferedImage;

import javax.swing.*;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import math.Vector;
import raytracer.Scene;
import shader.PhongShader;
import shader.Shader;

public class Window extends JFrame implements ActionListener{
    
    JFileChooser chooser;

    JMenuItem openItem;
    JMenuItem randomItem;
    JMenuItem exitItem;

    View view;

    int randomCount = 100;
    String fileName = "simple.json";

    static Shader activeShader = new PhongShader();
    static Scene activeScene = Scene.EMPTY;

    private static int width = 800;
    private static int height = 800;

    public World world = new World(width, height, this);
    public Input input = new Input(this);

    BufferedImage image;
    Vector camMovement = Vector.ZERO;
    Timer clock = new Timer(1, this);

    public Window(){
        JMenuBar menubar = new JMenuBar();
        JMenu fileMenu = new JMenu("Scene");

        openItem = new JMenuItem("Open Scene");
        randomItem = new JMenuItem("Random Scene");
        exitItem = new JMenuItem("Exit");

        openItem.addActionListener(this);
        randomItem.addActionListener(this);
        exitItem.addActionListener(this);

        fileMenu.add(openItem); 
        fileMenu.add(randomItem); 
        fileMenu.add(exitItem); 

        menubar.add(fileMenu);

        setJMenuBar(menubar);

        chooser = new JFileChooser("./scenes/");
        chooser.setDialogTitle("Scene auswählen");
        chooser.setFileSelectionMode(JFileChooser.FILES_ONLY);
        chooser.addChoosableFileFilter((FileFilter) new FileNameExtensionFilter("JSON File","json"));
        chooser.setAcceptAllFileFilterUsed(false);

        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setTitle("Raytracer");
        setSize(800,800);
        setVisible(true);
        setResizable(false);
        setLocationRelativeTo(null);
        setFocusTraversalKeysEnabled(false);

        //--------------

        view = new View(800,800);
        view.setBounds(0, 0, 800, 800);
        add(view);

        BufferedImage cursorImg = new BufferedImage(16,16, BufferedImage.TYPE_INT_ARGB);
        Cursor blank = Toolkit.getDefaultToolkit().createCustomCursor(cursorImg, new Point(0,0), "blank");
        // getContentPane().setCursor(blank);
        addMouseListener(input);
        addMouseMotionListener(input);
        addKeyListener(input);

        clock.start();
    }

    public void changeScene(Scene scene){
        activeScene = scene;
    }
    
    public void setActiveShader(Shader shader){ activeShader = shader; }
    public Shader getActiveShader(){ return activeShader; }
    public Scene getActiveScene(){ return activeScene; }

    @Override
    public void actionPerformed(ActionEvent e) {
             if(e.getSource() == randomItem) changeScene(Scene.randomSpheres(randomCount));
        else if(e.getSource() == openItem){
            if (chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION)
                changeScene(new Scene("./scenes/" + chooser.getSelectedFile().getName()) );
        }
        else if(e.getSource() == clock && hasFocus()){
            world.tick();
            world.renderFrame(activeShader);
            view.setImage(world.getFrameBuffer());
        }else if(e.getSource() == exitItem) System.exit(0);
    }
}
