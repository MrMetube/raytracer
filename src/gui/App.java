package gui;

import java.awt.*;
import java.awt.Robot;
import java.awt.event.*;
import java.awt.image.BufferedImage;
import java.io.File;
import java.util.HashMap;
import java.util.HashSet;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.imageio.ImageIO;
import javax.swing.*;
import javax.swing.event.MouseInputListener;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import math.Point;
import math.Color;
import raytracer.*;
import raytracer.stuff.Move;
import raytracer.stuff.Supersampling;
import raytracer.stuff.Turn;
import shader.*;

public class App extends JFrame implements ActionListener, KeyListener, MouseInputListener {
    int width = 800;
    int height = 800;
    Color[][] frameBuffer;
    int frameBufferCount;

    Scene scene = new Scene();
    Shader shader = new Phong();
    Supersampling supersampling = Supersampling.NONE;

    HashMap<Integer,Object> keyMap = new HashMap<>();
    HashSet<Move> moveKeys = new HashSet<>();
    HashSet<Turn> turnKeys = new HashSet<>();
    float xOffset = 0;
    float yOffset = 0;
    boolean captureMouse = false;
    Robot robot;

    Timer clock = new Timer(1, this);

    int randomCount = 100;

    int threadCount = Runtime.getRuntime().availableProcessors();

    JFileChooser chooser;
    JMenuItem fileItem;
    JMenuItem rndmItem;
    JMenuItem quitItem;
    View view;

    BufferedImage image;

    Camera camera;

    public App(){
        { // setup Frame
            setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            setTitle("Raytracer");
            setSize(width,height);
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
            view.setBounds(0, 0, width, height);
            add(view);

            BufferedImage cursorImg = new BufferedImage(16,16, BufferedImage.TYPE_INT_ARGB);
            Cursor blank = Toolkit.getDefaultToolkit().createCustomCursor(cursorImg, new java.awt.Point(0,0), "blank");
            getContentPane().setCursor(blank);

            addMouseListener(this);
            addMouseMotionListener(this);
            addKeyListener(this);

            try{ robot = new Robot(); }catch(Exception e){}

            setVisible(true);
        }

        { // setup KeyMap
            keyMap.put(KeyEvent.VK_W, Move.FORWARD);
            keyMap.put(KeyEvent.VK_A, Move.LEFT);
            keyMap.put(KeyEvent.VK_S, Move.BACKWARD);
            keyMap.put(KeyEvent.VK_D, Move.RIGHT);
            keyMap.put(KeyEvent.VK_SPACE, Move.UP);
            keyMap.put(KeyEvent.VK_SHIFT, Move.DOWN);

            keyMap.put(KeyEvent.VK_UP,    Turn.UP);
            keyMap.put(KeyEvent.VK_DOWN,  Turn.DOWN);
            keyMap.put(KeyEvent.VK_LEFT,  Turn.LEFT);
            keyMap.put(KeyEvent.VK_RIGHT, Turn.RIGHT);

            keyMap.put(KeyEvent.VK_1, new Phong());
            keyMap.put(KeyEvent.VK_2, new BlinnPhong());
            keyMap.put(KeyEvent.VK_3, new Specular());
            keyMap.put(KeyEvent.VK_4, new Diffuse());
            keyMap.put(KeyEvent.VK_5, new Ambient());
            keyMap.put(KeyEvent.VK_6, new Intersect());
            keyMap.put(KeyEvent.VK_7, new Normal());
            keyMap.put(KeyEvent.VK_8, new Distance());

            keyMap.put(KeyEvent.VK_F1, Supersampling.NONE);
            keyMap.put(KeyEvent.VK_F2, Supersampling.X4);
            keyMap.put(KeyEvent.VK_F3, Supersampling.X9);
        }

        camera = new Camera(new Point(0, 0, -10), Point.ZERO, 90, this);
        image = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);

        resetFrameBuffer();

        clock.start();
    }


    private void resetFrameBuffer(){
        frameBuffer = new Color[width][height];
        for (int x = 0; x < width; x++) for (int y = 0; y < height; y++)
            frameBuffer[x][y] = Color.BLACK;
        frameBufferCount = 0;
        counter = 0;
    }

    public void tick(){
        if(!moveKeys.isEmpty())
            camera.move(moveKeys);
        if(!turnKeys.isEmpty())
            camera.rotate(turnKeys);
        if(!moveKeys.isEmpty() || !turnKeys.isEmpty())
            resetFrameBuffer();
    }

    int counter;

    public void renderFrame(){
        Color[][] tempBuffer = new Color[width][height];
        renderImage(tempBuffer);
        // Add the new image to the buffer
        counter++;
        frameBufferCount++;

        for (int x = 0; x < width; x++) for (int y = 0; y < height; y++){
            if(tempBuffer[x][y] != null) frameBuffer[x][y] = frameBuffer[x][y].add(tempBuffer[x][y]);
        // }
        // // Set the image for the view
        // for (int x = 0; x < width; x++) for (int y = 0; y < height; y++) {
            image.setRGB(x, y, frameBuffer[x][y].div(frameBufferCount).rgb());
        }
    }

    public void renderImage(Color[][] buffer){
        ExecutorService exe =  Executors.newFixedThreadPool(threadCount);
        int deltaHeight = (height / threadCount)+1;
        for (int i = 0; i < threadCount; i++) 
            exe.submit(new Trace(width, height, i*deltaHeight, deltaHeight, scene, camera, buffer, shader));
        exe.shutdown();
        while(!exe.isTerminated());
    }

    public void renderToFile(Shader shader, boolean timed){
        Shader backup = this.shader;
        this.shader = shader;
        String name = shader.getName();

        long start = System.nanoTime();
        renderImage(frameBuffer);
        if(timed) System.out.printf("%s Rendering took: %s ms%n",name, (System.nanoTime()-start)/1_000_000);

        start = System.nanoTime();
        writeImage(name);
        if(timed) System.out.printf("%s Saving took:    %s ms%n",name, (System.nanoTime()-start)/1_000_000);
        this.shader = backup;
    }

    public void timedRender(Shader shader, int count){
        Shader backup = this.shader;
        this.shader = shader;
        String name = shader.getName();
        scene = Scene.randomSpheres(100);
        Color[][] image = new Color[width][height];
        
        long start = System.nanoTime();
        for (int i = 0; i < count; i++) renderImage(image);
        System.out.printf("%s Rendering took:    %s ms%n",name, (System.nanoTime()-start)/1_000_000);
        this.shader = backup;
    }

    public void writeImage(String name){
        File file = new File("./images/"+name+".png");
        try { ImageIO.write(image, "png", file); } catch (Exception e) {}
    }

    public void setScene(Scene scene){ 
        this.scene = scene; 
        resetFrameBuffer();
    }
    public void setShader(Shader shader){ 
        this.shader = shader; 
        resetFrameBuffer();
    }
    public void setSupersampling(Supersampling mode){ 
        camera.setSupersampling(mode);
        resetFrameBuffer();
    }
    
    public int getWidth() { return width; }
    public int getHeight() { return height; }
    public Scene getScene() { return scene; }
    public Shader getShader(){ return shader; }
    public BufferedImage getImage(){ return image;}
    public Supersampling getSupersampling() { return supersampling; }

    @Override
    public void keyPressed(KeyEvent e) {
        Object o = keyMap.get(e.getKeyCode());
             if( o instanceof Move) 
            moveKeys.add((Move)o);
        else if( o instanceof Turn) {
            turnKeys.add((Turn)o);
        } else if( o instanceof Shader) {
            setShader((Shader) o);
            System.out.println("Shader: " + (Shader) o);
        }else if( o instanceof Supersampling) {
            setSupersampling((Supersampling) o);
            System.out.println("Supersamplingmode: " + ((Supersampling) o).name());
        }else if( e.getKeyCode()==KeyEvent.VK_F5){
            view.toggleFPS();
        }else if( e.getKeyCode()==KeyEvent.VK_F12){
            renderToFile(new Ambient(), false);
            renderToFile(new Diffuse(), false);
            renderToFile(new Specular(), false);
            renderToFile(new Phong(), false);
            renderToFile(new BlinnPhong(), false);
            System.out.println("Screenshot saved");
        }
    }

    @Override
    public void keyReleased(KeyEvent e) {
        Object o = keyMap.get(e.getKeyCode());
        if(o instanceof Move) moveKeys.remove((Move)o);
        else if(o instanceof Turn) turnKeys.remove((Turn)o);
    }
    
    @Override
    public void mouseMoved(MouseEvent e) {
        if(captureMouse) {
            // float mouseSensitivity = 1;

            // int centerX = window.getX() + window.getWidth() / 2;
            // int centerY = window.getY() + window.getHeight() / 2;

            // xOffset = ((float) e.getXOnScreen() - centerX) / window.getWidth();
            // yOffset = ((float) e.getYOnScreen() - centerY) / window.getHeight();
            
            // todo Rotation
            // robot.mouseMove(centerX, centerY);
        }
        // System.out.printf("xOffset: %s, yOffset: %s %n", mouseXOffset,mouseYOffset);
    }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource() == clock){
            tick();
            renderFrame();
            view.setImage(image);
        }else if(e.getSource() == rndmItem) {
            setScene(Scene.randomSpheres(randomCount));
            System.out.println("Random Scene selected");
        }else if(e.getSource() == fileItem && chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION){
            setScene(new Scene("./scenes/" + chooser.getSelectedFile().getName()));
            System.out.println("File selected: "+chooser.getSelectedFile().getName());
        }else if(e.getSource() == quitItem) 
            System.exit(0);
        
    }

    @Override public void mouseClicked(MouseEvent e)  { captureMouse = !captureMouse;}
    @Override public void mouseEntered(MouseEvent e)  {}
    @Override public void mouseExited(MouseEvent e)   {}
    @Override public void mousePressed(MouseEvent e)  {}
    @Override public void mouseReleased(MouseEvent e) {}
    @Override public void mouseDragged(MouseEvent e)  {}
    @Override public void keyTyped(KeyEvent e)        {}
}
