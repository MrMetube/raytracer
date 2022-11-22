package shader.screenshader;

import math.Color;
import math.Point;
import math.Ray;
import math.Vector;

public class ScreenNormalShader implements ScreenShader{

    @Override
    public Color getColor(int x, int y, int size) {
        Ray r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
        return new Color(Math.abs(r.dir().x())/255,Math.abs(r.dir().y())/255,Math.abs(r.dir().z())/255);
    }
        
    @Override
    public String getName() {
        return "Screen Normal";
    }
}
