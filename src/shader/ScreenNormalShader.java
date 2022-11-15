package shader;

import math.Color;
import math.Point;
import math.Ray;
import math.Vector;

public class ScreenNormalShader implements ScreenShader{

    @Override
    public Color getColor(int x, int y, int size) {
        Ray r = new Ray(new Point(0, 0, -100), new Vector(x+0.5-size/2,y+0.5-size/2,100));
        return new Color(Math.abs(r.dir().x()),Math.abs(r.dir().y()),Math.abs(r.dir().z()));
    }
        
    @Override
    public String getName() {
        return "SCREEN_NORMAL";
    }
}
