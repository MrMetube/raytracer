package shader.screenshader;

import math.Color;

public interface ScreenShader{
    Color getColor(int x, int y, int size);
    String getName();
}