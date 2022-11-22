package shader;

import math.Color;

public class ScreenPixelShader implements ScreenShader {

    @Override
    public Color getColor(int x, int y, int size) {
        return new Color((x+0.5)/size,(y+0.5)/size,0);
    }
    
    @Override
    public String getName() {
        return "Screen Pixel";
    }
}
