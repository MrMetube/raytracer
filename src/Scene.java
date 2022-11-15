import java.util.HashSet;

import geometry.Geometry;
import math.Ray;
import shader.IntersectShader;
import shader.Shader;

public class Scene {
    HashSet<Geometry> geometries;
    HashSet<LightSource> lightSources;
    HashSet<Material> materials;

    public Scene(HashSet<Geometry> geometries) {
        this.geometries = geometries;
    }

    public boolean traceRay(Ray ray){
        double z = Double.MAX_VALUE;
        for(Geometry geometry : geometries){
            // TODO generalize shader
            Shader shader = new IntersectShader();
            shader.getColor(ray, geometry);
            z = Math.min(z,ray.t());
        }
        return z!= Double.MAX_VALUE;
    }

    public HashSet<Geometry> getGeometries() { return geometries; }
}
