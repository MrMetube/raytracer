package gui;


import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;

import javax.swing.JFileChooser;
import javax.swing.JFrame;
import javax.swing.JMenu;
import javax.swing.JMenuBar;
import javax.swing.JMenuItem;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import raytracer.Scene;
import shader.*;

public class Menu extends JFrame implements ActionListener{
    
    JFileChooser chooser;

    JMenuItem openItem;
    JMenuItem randomItem;
    JMenuItem exitItem;

    int randomCount = 100;
    String fileName = "simple.json";

    static Shader activeShader = new PhongShader();
    static Scene activeScene = Scene.EMPTY;

    private static int height = 800, width = height;

    public static World world = new World(width, height);
    public static Viewport viewport;
    // public static Viewport viewport = new Viewport(width, height); // this doesnt work because focus is weird
    public static Input input = new Input();

    public Menu(){
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
        setSize(800,150);
        setLayout(null);
        setVisible(true);
        setLocation(2560/2-getWidth()/2, 50);
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
        if(e.getSource() == randomItem) changeScene(Scene.randomSpheres(randomCount));
        else if(e.getSource() == openItem){
            if (chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION)
                changeScene(new Scene("./scenes/" + chooser.getSelectedFile().getName()) );
        }

    }
}
