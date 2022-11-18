import java.util.HashSet;

import geometry.Camera;
import geometry.Geometry;
import math.Ray;

public class Scene {
    HashSet<Geometry> geometries;
    HashSet<LightSource> lightSources;
    HashSet<Material> materials;
    Camera camera;

    public Scene(Camera camera) {
        this.geometries = new HashSet<>();
        this.lightSources = new HashSet<>();
        this.materials = new HashSet<>();
        this.camera = camera;
    }

    public void addGeometry(Geometry g){       geometries.add(g); }
    public void addLightSource(LightSource l){ lightSources.add(l); }
    public void addMaterial(Material m){       materials.add(m); } 

    public boolean traceRay(Ray ray){
        double t = Double.MAX_VALUE;
        Geometry target = null;
        Ray clone;
        for(Geometry geometry : geometries){
            clone = ray.clone();
            geometry.intersect(clone);
            if(clone.t()<t){
                t = clone.t();
                target = clone.target();
            }
        }
        ray.hit(target,t);
        return t != Double.MAX_VALUE;
    }

    public HashSet<Geometry> getGeometries() { return geometries; }
    public Camera getCamera() { return camera; }
}
