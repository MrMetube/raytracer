package scene;
import java.awt.image.BufferedImage;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.HashSet;

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
    // HashSet<LightSource> lightSources;
    // HashSet<Material> materials;
    Camera camera;

    static GsonBuilder gB = new GsonBuilder();
    static Gson gson = gB.registerTypeAdapter(Geometry.class, new GeometryAdapter()).create();

    public Scene(Camera camera) {
        this.geometries = new HashSet<>();
        // this.lightSources = new HashSet<>();
        // this.materials = new HashSet<>();
        this.camera = camera;
    }

    public Scene(String path){
        try {
            FileReader fR = new FileReader(new File(path));
            Scene s = gson.fromJson(fR, Scene.class);
            this.geometries = s.getGeometries();
            // this.lightSources = s.getLightSources();
            // this.materials = s.getMaterials();
            this.camera = s.getCamera();
        } catch (FileNotFoundException e) {
            e.printStackTrace();
        }
    }

    public void addGeometry(Geometry g){       geometries.add(g); }
    // public void addLightSource(LightSource l){ lightSources.add(l); }
    // public void addMaterial(Material m){       materials.add(m); } 

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

    public HashSet<Geometry> getGeometries() { return geometries; }
    public Camera getCamera() { return camera; }

    public void makeImage(Shader shader, String name){
        Camera camera = getCamera();

        int width = camera.getWidth();
        int height = camera.getHeight();

        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Color def = new Color(113, 216, 237); // default background color
        
        for (int x = 0; x < width; x++) for (int y = 0; y < height; y++) {
            Ray ray = camera.generateRay(x, y);
            Color color = (traceRay(ray)) ? shader.getColor(ray, ray.target()) : def;
            image.setRGB(x, height-y-1, color.rgb() );
        }

        File file = new File("./images/"+name+".png");
        try {
            ImageIO.write(image, "png", file);   
        } catch (Exception e) {
            System.out.println(e.getMessage());
        }
    }

    public void toJson(String name){
        try {
            FileWriter fw = new FileWriter("./scenes/"+name+".json");
            fw.write(gson.toJson(this));
            fw.close();
        } catch (Exception e) {
            System.out.println(e.getMessage());
        }
    }
    
}
