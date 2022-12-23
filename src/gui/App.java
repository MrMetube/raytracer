package gui;

import java.awt.*;
import java.awt.Robot;
import java.awt.event.*;
import java.awt.image.BufferedImage;
import java.util.HashMap;
import java.util.HashSet;
import java.util.concurrent.BrokenBarrierException;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.swing.*;
import javax.swing.event.MouseInputListener;
import javax.swing.filechooser.FileFilter;
import javax.swing.filechooser.FileNameExtensionFilter;

import math.Point;
import math.Color;
import raytracer.*;
import raytracer.geometry.Geometry;
import raytracer.stuff.Move;
import raytracer.stuff.Supersampling;
import raytracer.stuff.Turn;
import shader.*;

public class App extends JFrame implements ActionListener, KeyListener, MouseInputListener {
    public static boolean useSkybox = true;

    int width = 600;
    int height = 600;

    Scene  scene  = new Scene();
    Shader shader = new Phong();
    Skybox skybox = new Skybox();

    Supersampling supersampling = Supersampling.NONE;

    HashMap<Integer,Object> keyMap = new HashMap<>();
    HashSet<Move> moveKeys = new HashSet<>();
    HashSet<Turn> turnKeys = new HashSet<>();
    float xOffset = 0;
    float yOffset = 0;
    boolean captureMouse = false;
    Robot robot;

    int randomCount = 100;

    int threadCount = Runtime.getRuntime().availableProcessors();
    ExecutorService exe =  Executors.newFixedThreadPool(threadCount);
    CyclicBarrier barrier = new CyclicBarrier(threadCount,()->{ onRenderFinish(); });

    JFileChooser chooser;
    JMenuItem fileItem;
    JMenuItem rndmItem;
    JMenuItem emptyItem;
    JMenuItem quitItem;
    View view;

    BufferedImage image;

    Camera camera;

    Timer clock = new Timer(1, this); // tickrate != framerate

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
            emptyItem = new JMenuItem("Empty Scene",KeyEvent.VK_E);
            quitItem = new JMenuItem("Quit",KeyEvent.VK_Q);

            fileItem.addActionListener(this);
            rndmItem.addActionListener(this);
            emptyItem.addActionListener(this);
            quitItem.addActionListener(this);

            sceneMenu.setMnemonic(KeyEvent.VK_C);
            sceneMenu.add(fileItem);
            sceneMenu.add(rndmItem);
            sceneMenu.add(emptyItem);
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

        camera = new Camera(new Point(0, 0, -1), Point.ZERO, 90, this);
        image = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);

        // clock.start();
        renderToView();
    }

    void tick(){
        if(!moveKeys.isEmpty())
            camera.move(moveKeys);
        if(!turnKeys.isEmpty())
            camera.rotate(turnKeys);
    }

    Color[][] secondaryBuffer = new Color[width][height];
    Color[][] primaryBuffer = new Color[width][height];
    boolean renderToPrimary = true;

    void renderToView(){
        if(renderToPrimary)
            renderImage(primaryBuffer,shader);
        else
            renderImage(secondaryBuffer,shader);
    }

    void renderImage(Color[][] buffer, Shader shader){
        //Copy the camera to not change to view mid rendering
        Camera camCopy = new Camera(camera);
        int deltaHeight = (height / threadCount)+1;
        for (int i = 0; i < threadCount; i++){
            int start = i*deltaHeight;
            int end =  Math.min(start+deltaHeight, height);
            exe.submit( () -> {
                for (int u = 0; u < width; u++) for (int v = start; v < end; v++) {
                    Payload[] payloads = camCopy.generatePayload(u, v);
                    Color color = new Color(0, 0, 0);
                    for (Payload payload : payloads)
                        traceRay(payload);
                    for (Payload payload : payloads)
                        color = color.add(payload.color());
                    color = color.div(payloads.length);
                    buffer[u][height-v-1] = color;
                }
                try { barrier.await(); } catch (InterruptedException | BrokenBarrierException e) {
                    e.printStackTrace();
                }
            });
        }
    }

    private Color traceRay(Payload payload){
        for(Geometry geometry : scene.getGeometries()) 
            geometry.intersect(payload);
        if (payload.target() != null)
            shader.getColor(payload, scene);
        else 
            skybox.getColor(payload, scene);
        if(payload.reflection()!=null){
            payload.setColor(payload.color().add(traceRay(new Payload(payload.reflection())).mul(payload.reflectStrength())));
        }
        return payload.color();
    }

    void onRenderFinish() {
        if(renderToPrimary)
            for (int x = 0; x < width; x++) for (int y = 0; y < height; y++)
                image.setRGB(x, y, primaryBuffer[x][y].rgb());
        else
            for (int x = 0; x < width; x++) for (int y = 0; y < height; y++)
                image.setRGB(x, y, secondaryBuffer[x][y].rgb());
        renderToPrimary = !renderToPrimary;
        renderToView();
        view.setImage(image);
        if(!clock.isRunning()) tick();
    }

    @Override
    public void keyPressed(KeyEvent e) {
        Object o = keyMap.get(e.getKeyCode());
             if( o instanceof Move) 
            moveKeys.add((Move)o);
        else if( o instanceof Turn) {
            turnKeys.add((Turn)o);
        } else if( o instanceof Shader) {
            shader = (Shader) o;
            System.out.println("Shader: " + (Shader) o);
        }else if( o instanceof Supersampling) {
            camera.setSupersampling((Supersampling) o);
            System.out.println("Supersamplingmode: " + ((Supersampling) o).name());
        }else if( e.getKeyCode()==KeyEvent.VK_ESCAPE){
            captureMouse = false;
            getContentPane().setCursor(null);
        }else if( e.getKeyCode()==KeyEvent.VK_F5){
            view.toggleFPS();
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
            int mouseSensitivity = 100;

            int centerX = getX() + getWidth() / 2;
            int centerY = getY() + getHeight() / 2;

            xOffset = ((float) e.getXOnScreen() - centerX) / getWidth();
            yOffset = ((float) e.getYOnScreen() - centerY) / getHeight();
            // Should not allow turning more than 80° up or down
            camera.rotate(yOffset*mouseSensitivity,xOffset*mouseSensitivity);
            robot.mouseMove(centerX, centerY);
        }
    }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource() == clock){
            tick();
        }else if(e.getSource() == emptyItem) {
            scene = new Scene();
            System.out.println("Empty Scene selected");
        }else if(e.getSource() == rndmItem) {
            scene = Scene.randomSpheres(randomCount);
            System.out.println("Random Scene selected");
        }else if(e.getSource() == fileItem && chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION){
            scene = new Scene("./scenes/" + chooser.getSelectedFile().getName());
            System.out.println("File selected: "+chooser.getSelectedFile().getName());
        }else if(e.getSource() == quitItem) 
            System.exit(0);
        
    }

    @Override public void mouseClicked(MouseEvent e)  { 
        captureMouse = !captureMouse;
        if(captureMouse){
            BufferedImage cursorImg = new BufferedImage(16,16, BufferedImage.TYPE_INT_ARGB);
            Cursor blank = Toolkit.getDefaultToolkit().createCustomCursor(cursorImg, new java.awt.Point(0,0), "blank");
            getContentPane().setCursor(blank);
        }else{
            getContentPane().setCursor(null);
        }
    }
    @Override public void mouseEntered(MouseEvent e)  {}
    @Override public void mouseExited(MouseEvent e)   {}
    @Override public void mousePressed(MouseEvent e)  {}
    @Override public void mouseReleased(MouseEvent e) {}
    @Override public void mouseDragged(MouseEvent e)  {}
    @Override public void keyTyped(KeyEvent e)        {}
}
