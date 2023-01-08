package raytracer;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Random;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import math.Color;
import math.Point;
import math.Vector;
import raytracer.geometry.BoundingBox;
import raytracer.geometry.Geometry;
import raytracer.geometry.Plane;
import raytracer.geometry.Sphere;
import raytracer.light.*;
import raytracer.stuff.GeometryAdapter;
import raytracer.stuff.LightSourceAdapter;

public class Scene {
    HashSet<Geometry> geometries;
    HashSet<LightSource> lightSources;
    HashMap<String,Material> materials;

    static Gson gson = new GsonBuilder()
        .registerTypeAdapter(Geometry.class, new GeometryAdapter())
        .registerTypeAdapter(LightSource.class, new LightSourceAdapter())
        .create();

    public Scene() {
        this.geometries = new HashSet<>();
        this.lightSources = new HashSet<>();
        this.materials = new HashMap<String,Material>();
        this.materials.put(Geometry.NO_MATERIAL,Material.DEFAULT);
    }

    public Scene(String path){
        try {
            var fR = new FileReader(new File(path));
            var s = gson.fromJson(fR, Scene.class);
            this.geometries = s.getGeometries();
            this.lightSources = s.getLightSources();
            this.materials = s.getMaterials();
        } catch (Exception e) {}
    }

    public void toJson(String name){
        try {
            var fw = new FileWriter("./scenes/"+name+".json");
            fw.write(gson.toJson(this));
            fw.close();
        } catch (Exception e) {}
    }
    
    public static Scene randomSpheres(int count){
        var s = new Scene();
        s.addBasicMaterials();
        s.addLightSource(new PointLight(new Point(0, 10, -10), Color.WHITE, 1));
        s.addLightSource(new DirectionalLight(new Vector(0, -1, 0), Color.WHITE, 1));
        Object[] materials = s.getMaterials().keySet().toArray();
        var rdm = new Random();
        double bounds = Math.sqrt(count);
        for (int i = 0; i < count; i++) {
            double x  = rdm.nextDouble(-bounds,bounds);
            double y  = rdm.nextDouble(-bounds,bounds);
            double z  = rdm.nextDouble(-bounds,bounds);
            double r  = rdm.nextDouble(.5,1.5);
            double r2 = rdm.nextDouble(.5,1.5);
            double r3 = rdm.nextDouble(.5,1.5);
            String m = (String)materials[rdm.nextInt(0,materials.length)];
            s.addGeometry(
                switch(rdm.nextInt(2)){
                    case 0 -> new Sphere(new Point(x,y,z), r, m);
                    case 1 -> new BoundingBox(new Point(x,y,z), new Point(x+r,y+r2,z+r3), m);
                    case 2 -> new Plane(new Vector(rdm.nextDouble(-1,1), rdm.nextDouble(-1,1), rdm.nextDouble(-1,1)), new Point(x, y, z), r, m);
                    default -> null;
                }
            );
                
        }
        return s;
    }
    
    public void addGeometry(Geometry g){ 
        if(!materials.containsKey(g.material())) g.setMaterial(Geometry.NO_MATERIAL);
        geometries.add(g);
    }
    public void addLightSource(LightSource l){ lightSources.add(l); }
    public void addMaterial(String key, Material m){ materials.put(key,m); } 
    public HashSet<Geometry>        getGeometries()   { return geometries; }
    public HashMap<String,Material> getMaterials()    { return materials; }
    public HashSet<LightSource>     getLightSources() { return lightSources; }

    public void addBasicMaterials(){
        addMaterial("red",       Material.RED);
        addMaterial("green",     Material.GREEN);
        addMaterial("blue",      Material.BLUE);
        addMaterial("cyan",      Material.CYAN);
        addMaterial("magenta",   Material.MAGENTA);
        addMaterial("yellow",    Material.YELLOW);
        addMaterial("white",     Material.WHITE);
        addMaterial("gray",      Material.GRAY);
        
        addMaterial("pink",      Material.PINK   );
        addMaterial("orange",    Material.ORANGE );
        addMaterial("lemon",     Material.LEMON    );
        addMaterial("lime",      Material.LIME   );
        addMaterial("turquoise", Material.TURQUOISE  );
        addMaterial("purple",    Material.PURPLE );
        addMaterial("light",     Material.LIGHT  );
        
        addMaterial("gold",      Material.GOLD  );
        addMaterial("silver",    Material.SILVER  );
        addMaterial("bronze",    Material.BRONZE  );
        addMaterial("copper",    Material.COPPER  );
    }
}
