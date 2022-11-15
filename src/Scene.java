import java.util.HashSet;

import geometry.Camera;
import geometry.Geometry;
import math.Ray;

public class Scene {
    HashSet<Geometry> geometries;
    HashSet<LightSource> lightSources;
    HashSet<Material> materials;
    Camera camera;

    public Scene(HashSet<Geometry> geometries, Camera camera) {
        this.geometries = geometries;
        this.camera = camera;
    }

    public boolean traceRay(Ray ray){
        double z = Double.MAX_VALUE;
        Geometry g = null;
        for(Geometry geometry : geometries){
            Ray clone = ray.clone();
            geometry.intersect(clone);
            if(clone.t()<z){
                z = clone.t();
                g = clone.target();
            }
        }
        ray.hit(g,z);
        return z != Double.MAX_VALUE;
    }

    public HashSet<Geometry> getGeometries() { return geometries; }
    public Camera getCamera() { return camera; }
}
