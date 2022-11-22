package shader.screenshader;

import math.Color;
import math.Vector;

public class ScreenDistanceShader implements ScreenShader{
    @Override
    public Color getColor(int x, int y, int size) {
        double dis = new Vector(x+0.5-size/2,y+0.5-size/2,100).mag()/255;
        return new Color(dis,dis,dis);
    }
        
    @Override
    public String getName() {
        return "Screen Distance";
    }
}
