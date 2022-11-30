package raytracer;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Random;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.imageio.ImageIO;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import math.Color;
import math.Point;
import math.Ray;
import raytracer.geometry.Geometry;
import raytracer.geometry.Sphere;
import shader.Shader;

public class Scene {
    //#region Attributes
    HashSet<Geometry> geometries;
    HashSet<LightSource> lightSources;
    HashMap<String,Material> materials;
    Camera camera;

    static Gson gson = new GsonBuilder()
                            .registerTypeAdapter(Geometry.class, new GeometryAdapter())
                            .registerTypeAdapter(LightSource.class, new LightSourceAdapter())
                            .create();

    //#endregion
    
    //#region Constructor

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

    //#endregion

    public boolean traceRay(Ray ray){
        double t = Double.MAX_VALUE;
        Geometry target = null;
        for(Geometry geometry : geometries){
            geometry.intersect(ray);
            if(ray.t()<t){
                t = ray.t();
                target = ray.target();
            }
        }
        if(target != null) ray.hit(target,t);
        return t != Double.MAX_VALUE && target != null;
    }

    public void makeImage(Shader shader, String name, boolean timed){
        File file = new File("./images/"+name+".png");

        Camera camera = getCamera();
        int width = camera.getWidth();
        int height = camera.getHeight();
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);

        long start = System.nanoTime();

        int threadCount = Runtime.getRuntime().availableProcessors();
        ExecutorService exe =  Executors.newFixedThreadPool(threadCount);
        int dx = (width/threadCount)+1;
        int dy = (height/threadCount)+1;
        for (int i = 0; i < threadCount; i++) for (int j = 0; j < threadCount; j++) 
            exe.submit(new Trace(this, image, i*dx, (i+1)*dx, j*dy, (j+1)*dy, shader));
        exe.shutdown();
        while(!exe.isTerminated());
        
        if(timed) {
            System.out.printf("%s Rendering took: %s ms%n",name, (System.nanoTime()-start)/1_000_000);
            start = System.nanoTime();
        }
        
        try { ImageIO.write(image, "png", file); } catch (Exception e) {}
        
        // if(timed) System.out.printf("%s Saving took:    %s ms%n",name, (System.nanoTime()-start)/1_000_000);
    }

    public void makeImage(Shader shader){ makeImage(shader,shader.getName(), false); }
    public void makeImage(Shader shader, boolean time){ makeImage(shader,shader.getName(), time); }

    public void toJson(String name){
        try {
            FileWriter fw = new FileWriter("./scenes/"+name+".json");
            fw.write(gson.toJson(this));
            fw.close();
        } catch (Exception e) {}
    }
    
    //#region Other

    public static Scene randomSpheres(int count){
        Scene s = new Scene(new Camera(new Point(0, 12, -12), Point.ZERO, 90, 800, 800));
        s.addBasicMaterials();
        s.addLightSource(new PointLightSource(new Point(0, 20, 10), Color.WHITE, 1));
        s.addLightSource(new PointLightSource(new Point(0, 10, -10), Color.WHITE, 1));
        Object[] materials = s.getMaterials().keySet().toArray();
        Random rdm = new Random();
        for (int i = 0; i < count; i++) {
            double x = rdm.nextDouble(-10,10);
            double y = rdm.nextDouble(-10,10);
            double z = rdm.nextDouble(-10,10);
            double r = rdm.nextDouble(0.1,1);
            int m = rdm.nextInt(0,materials.length);
            if(materials[m] instanceof String)
                s.addGeometry(new Sphere(new Point(x,y,z), r, (String)materials[m]));
        }
        return s;
    }
    
    public void addGeometry(Geometry g){ 
        if(!materials.containsKey(g.material())){
            g.setMaterial(Geometry.NO_MATERIAL);
        }
        geometries.add(g);
    }
    public void addLightSource(LightSource l){ lightSources.add(l); }
    public void addMaterial(String key, Material m){ materials.put(key,m); } 
    public HashSet<Geometry>        getGeometries()   { return geometries; }
    public HashMap<String,Material> getMaterials()    { return materials; }
    public HashSet<LightSource>     getLightSources() { return lightSources; }
    public Camera                   getCamera()       { return camera; }

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
        
        addMaterial("pink", Material.PINK   );
        addMaterial("orange", Material.ORANGE );
        addMaterial("lemon", Material.LEMON    );
        addMaterial("lime", Material.LIME   );
        addMaterial("azure", Material.AZURE  );
        addMaterial("purple", Material.PURPLE );
        addMaterial("dark", Material.DARK   );
        addMaterial("light", Material.LIGHT  );
    }
    //#endregion
}
