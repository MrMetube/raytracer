package gui;

import java.awt.*;
import java.awt.Robot;
import java.awt.event.*;
import java.awt.image.BufferedImage;
import java.util.HashMap;
import java.util.HashSet;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.swing.*;
import javax.swing.event.MouseInputListener;
import javax.swing.filechooser.FileNameExtensionFilter;

import math.Point;
import math.Color;
import raytracer.*;
import raytracer.stuff.*;
import shader.*;

public class App extends JFrame implements ActionListener, KeyListener, MouseInputListener {
    public static boolean useSkybox = false;

    int width = 960;
    int height = 540;

    public Scene scene = new Scene();
    Shader shader = new Phong();
    Skybox skybox = new Skybox();

    HashMap<Integer,Object> keyMap = new HashMap<>();
    HashSet<Move> moveKeys = new HashSet<>();
    HashSet<Turn> turnKeys = new HashSet<>();
    boolean isActive = false;
    Robot robot;

    int randomCount = 100;

    int threadCount = Runtime.getRuntime().availableProcessors();
    ExecutorService exe =  Executors.newFixedThreadPool(threadCount);
    CyclicBarrier barrier = new CyclicBarrier(threadCount, this::onRenderFinish);

    JFileChooser chooser;
    JMenuItem fileItem;
    JMenuItem rndmItem;
    JMenuItem emptyItem;
    JMenuItem quitItem;
    View view;

    BufferedImage image;

    Camera camera;

    public App(){
        setupFrame();
        setupKeymap();

        camera = new Camera(new Point(0, 0, -1), Point.zero, 90, this);
        image = new BufferedImage(width,height,BufferedImage.TYPE_INT_RGB);

        renderToView();
    }

    void setupKeymap(){
        keyMap.put(KeyEvent.VK_W,       Move.FORWARD);
        keyMap.put(KeyEvent.VK_A,       Move.LEFT);
        keyMap.put(KeyEvent.VK_S,       Move.BACKWARD);
        keyMap.put(KeyEvent.VK_D,       Move.RIGHT);
        keyMap.put(KeyEvent.VK_SPACE,   Move.UP);
        keyMap.put(KeyEvent.VK_SHIFT,   Move.DOWN);

        keyMap.put(KeyEvent.VK_UP,      Turn.UP);
        keyMap.put(KeyEvent.VK_DOWN,    Turn.DOWN);
        keyMap.put(KeyEvent.VK_LEFT,    Turn.LEFT);
        keyMap.put(KeyEvent.VK_RIGHT,   Turn.RIGHT);

        keyMap.put(KeyEvent.VK_1,       new Phong());
        keyMap.put(KeyEvent.VK_2,       new BlinnPhong());
        keyMap.put(KeyEvent.VK_3,       new Specular());
        keyMap.put(KeyEvent.VK_4,       new Diffuse());
        keyMap.put(KeyEvent.VK_5,       new Ambient());
        keyMap.put(KeyEvent.VK_6,       new Intersect());
        keyMap.put(KeyEvent.VK_7,       new Normal());
        keyMap.put(KeyEvent.VK_8,       new Distance());

        keyMap.put(KeyEvent.VK_F1,      Supersampling.NONE);
        keyMap.put(KeyEvent.VK_F2,      Supersampling.X4);
        keyMap.put(KeyEvent.VK_F3,      Supersampling.X9);
    }

    void setupFrame() {
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setTitle("Raytracer");
        setSize(width,height);
        setResizable(false);
        setLocationRelativeTo(null);
        setFocusTraversalKeysEnabled(false);

        var menubar = new JMenuBar();
        var sceneMenu = new JMenu("Scene");

        fileItem  = new JMenuItem("Open File",KeyEvent.VK_F);
        rndmItem  = new JMenuItem("Random Scene",KeyEvent.VK_R);
        emptyItem = new JMenuItem("Empty Scene",KeyEvent.VK_E);
        quitItem  = new JMenuItem("Quit",KeyEvent.VK_Q);

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
        chooser.addChoosableFileFilter(new FileNameExtensionFilter("JSON File","json"));
        chooser.setAcceptAllFileFilterUsed(false);

        view = new View(width,height);
        view.setBounds(0, 0, width, height);
        add(view);

        addMouseListener(this);
        addMouseMotionListener(this);
        addKeyListener(this);

        try{ robot = new Robot(); }catch(Exception ignored){}

        setVisible(true);
    }

    void tick(){
        camera.rotate(camDesiredX,camDesiredY);
        camDesiredX = 0;
        camDesiredY = 0;

        if(!moveKeys.isEmpty())
            camera.move(moveKeys);
        if(!turnKeys.isEmpty())
            camera.rotate(turnKeys);
    }

    Color[][] secondaryBuffer = new Color[width][height];
    Color[][] primaryBuffer   = new Color[width][height];
    Color[][] activeBuffer;
    boolean renderToPrimary = true;

    void renderToView(){
        renderImage(renderToPrimary ? primaryBuffer : secondaryBuffer);
        tick();
    }

    void renderImage(Color[][] buffer){
        int deltaHeight = (height / threadCount)+1;
        for (int i = 0; i < threadCount; i++){
            int start = i*deltaHeight;
            int end =  Math.min(start+deltaHeight, height);
            exe.submit( () -> {
                Payload[] payloads;
                for (int u = 0; u < width; u++) for (int v = start; v < end; v++) {
                    payloads = camera.generatePayload(u, v);
                    var color = new Color(0, 0, 0);
                    for (var payload : payloads)
                        color = color.add(traceRay(payload));
                    
                    buffer[u][height-v-1] = color.div(payloads.length);
                }
                try { barrier.await(); } catch (Exception e) { e.printStackTrace(); }
            });
        }
    }

    Color traceRay(Payload payload){
        for(var geometry : scene.getGeometries()) 
            geometry.intersect(payload);
        if (payload.target() != null)
            shader.getColor(payload, scene);
        else 
            skybox.getColor(payload, scene);

        if (payload.reflection() != null)
            payload.reflect(traceRay(payload.reflection()));

        return payload.color();
    }

    void onRenderFinish() {
        activeBuffer = renderToPrimary ? primaryBuffer : secondaryBuffer;
        for (int x = 0; x < width; x++) for (int y = 0; y < height; y++)
            image.setRGB(x, y, activeBuffer[x][y].rgb());
        
        renderToPrimary = !renderToPrimary;
        renderToView();
        view.setImage(image);
    }

    @Override
    public void keyPressed(KeyEvent e) {
        var o = keyMap.get(e.getKeyCode());
             if( isActive && o instanceof Move)
            moveKeys.add((Move) o);
        else if( isActive && o instanceof Turn)
            turnKeys.add((Turn)o);
        else if( o instanceof Shader) {
            shader = (Shader) o;
            System.out.println("Shader: " + shader);
        }else if( o instanceof Supersampling s) {
            camera.setSupersampling(s);
            System.out.println("Supersampling mode: " + s.name());
        }else if( e.getKeyCode()==KeyEvent.VK_ESCAPE){
            isActive = false;
            getContentPane().setCursor(null);
        }else if( e.getKeyCode()==KeyEvent.VK_F5)
            view.toggleFPS();
    }

    @Override
    public void keyReleased(KeyEvent e) {
        var o = keyMap.get(e.getKeyCode());
             if(o instanceof Move m) moveKeys.remove(m);
        else if(o instanceof Turn t) turnKeys.remove(t);
    }

    double camDesiredX;
    double camDesiredY;

    final int mouseSensitivity = 100;

    @Override
    public void mouseMoved(MouseEvent e) {
        if(isActive) {

            int centerX = getX() + getWidth() / 2;
            int centerY = getY() + getHeight() / 2;

            double xOffset = ( (double) e.getXOnScreen() - centerX) / getWidth();
            double yOffset = ( (double) e.getYOnScreen() - centerY) / getHeight();

            camDesiredX += xOffset*mouseSensitivity;
            camDesiredY += yOffset*mouseSensitivity;
            robot.mouseMove(centerX, centerY);
        }
    }

    @Override
    public void actionPerformed(ActionEvent e) {
        if(e.getSource() == emptyItem) {
            scene = new Scene();
            System.out.println("Empty Scene selected");
        }else if(e.getSource() == rndmItem) {
            scene = Scene.randomSpheres(randomCount);
            System.out.println("Random Scene selected");
        }else if(e.getSource() == fileItem && chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION){
            scene = new Scene(chooser.getSelectedFile().getName());
            System.out.println("File selected: "+chooser.getSelectedFile().getName());
        }else if(e.getSource() == quitItem) 
            System.exit(0);
    }

    Cursor blankCursor = Toolkit.getDefaultToolkit().createCustomCursor(new BufferedImage(16,16, BufferedImage.TYPE_INT_ARGB), new java.awt.Point(0,0), "blank");

    @Override 
    public void mouseClicked(MouseEvent e)  { 
        isActive = !isActive;
        getContentPane().setCursor(isActive ? blankCursor : null);
    }
    
    @Override public void mouseEntered(MouseEvent e)  {}
    @Override public void mouseExited(MouseEvent e)   {}
    @Override public void mousePressed(MouseEvent e)  {}
    @Override public void mouseReleased(MouseEvent e) {}
    @Override public void mouseDragged(MouseEvent e)  {}
    @Override public void keyTyped(KeyEvent e)        {}
}
