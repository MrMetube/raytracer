package scene;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.HashMap;
import java.util.HashSet;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.imageio.ImageIO;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import geometry.Geometry;
import geometry.GeometryAdapter;
import math.Color;
import math.Ray;
import shader.Shader;

public class Scene {
    HashSet<Geometry> geometries;
    HashSet<LightSource> lightSources;
    HashMap<String,Material> materials;
    Camera camera;

    static Gson gson = new GsonBuilder()
                            .registerTypeAdapter(Geometry.class, new GeometryAdapter())
                            .registerTypeAdapter(LightSource.class, new LightSourceAdapter())
                            .create();

    public Scene(Camera camera) {
        this.geometries = new HashSet<>();
        this.lightSources = new HashSet<>();
        this.materials = new HashMap<String,Material>();
        this.materials.put(Geometry.NO_MATERIAL,Material.DEFAULT);
        this.camera = camera;
    }

    public Scene(String path){
        try {
            FileReader fR = new FileReader(new File(path));
            Scene s = gson.fromJson(fR, Scene.class);
            this.geometries = s.getGeometries();
            this.lightSources = s.getLightSources();
            this.materials = s.getMaterials();
            this.camera = s.getCamera();
        } catch (Exception e) {}
    }

    public boolean traceRay(Ray ray){
        double t = Double.MAX_VALUE;
        Geometry target = null;
        Ray clone;
        for(Geometry geometry : geometries){
            clone = new Ray(ray);
            geometry.intersect(clone);
            if(clone.t()<t){
                t = clone.t();
                target = clone.target();
            }
        }
        if(target != null) ray.hit(target,t);
        return t != Double.MAX_VALUE && target != null;
    }

    public void makeImage(Shader shader, String name, boolean time){
        File file = new File("./images/"+name+".png");

        Camera camera = getCamera();
        int width = camera.getWidth();
        int height = camera.getHeight();
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);

        long start = System.nanoTime();

        int threadCount = Runtime.getRuntime().availableProcessors();;
        ExecutorService exe =  Executors.newFixedThreadPool(threadCount);
        int dx = (width/threadCount)+1;
        int dy = (height/threadCount)+1;
        for (int i = 0; i < threadCount; i++) for (int j = 0; j < threadCount; j++) 
            exe.submit(new Trace(this, image, i*dx, (i+1)*dx, j*dy, (j+1)*dy, shader));
        exe.shutdown();
        while(!exe.isTerminated());

        if(time) System.out.printf("%s took %s ms%n",name, (System.nanoTime()-start)/1_000_000);

        try { ImageIO.write(image, "png", file); } catch (Exception e) {}
    }

    public void makeImage(Shader shader){ makeImage(shader,shader.getName(), false); }
    public void makeImage(Shader shader, boolean time){ makeImage(shader,shader.getName(), time); }

    private class Trace implements Runnable{
        final BufferedImage image;
        final Color def = new Color(0.44, 0.85, 0.93);
        final Camera camera;
        final Shader shader;
        final Scene scene;
        final int xS,xE,yS,yE;

        Trace(Scene scene, BufferedImage image, int xStart, int xEnd, int yStart, int yEnd, Shader shader){
            this.image = image;
            this.scene = scene;
            this.camera = scene.getCamera();
            this.shader = shader;
            xS = xStart;
            yS = yStart;
            xE = Math.min(xEnd, camera.getWidth());
            yE = Math.min(yEnd, camera.getHeight());
        }
        @Override 
        public void run(){
            for (int x = xS; x < xE; x++) for (int y = yS; y < yE; y++) {
                Ray ray = camera.generateRay(x, y);
                Color color = (traceRay(ray)) ? shader.getColor(ray, ray.target(), scene) : def;
                // color = color != null ? color : def; // shouldnt ever happen as the shader has been reworked
                image.setRGB(x, camera.getHeight()-y-1, color.rgb() );
            }
        }
    }

    public void toJson(String name){
        try {
            FileWriter fw = new FileWriter("./scenes/"+name+".json");
            fw.write(gson.toJson(this));
            fw.close();
        } catch (Exception e) {}
    }
    
    public void addGeometry(Geometry g){ 
        if(!materials.containsKey(g.material())){
            g.setMaterial(Geometry.NO_MATERIAL);
        }
        geometries.add(g);
    }
    public void addLightSource(LightSource l){ lightSources.add(l); }
    public void addMaterial(String key, Material m){ materials.put(key,m); } 

    public void addBasicMaterials(){
        addMaterial("red", Material.RED);
        addMaterial("green", Material.GREEN);
        addMaterial("blue", Material.BLUE);
        addMaterial("cyan", Material.CYAN);
        addMaterial("magenta", Material.MAGENTA);
        addMaterial("yellow", Material.YELLOW);
        addMaterial("white", Material.WHITE);
        addMaterial("gray", Material.GRAY);
        addMaterial("black", Material.BLACK);
    }

    public HashSet<Geometry>        getGeometries()   { return geometries; }
    public HashMap<String,Material> getMaterials()    { return materials; }
    public HashSet<LightSource>     getLightSources() { return lightSources; }
    public Camera                   getCamera()       { return camera; }

}
