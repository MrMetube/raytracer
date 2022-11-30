package tests;

import java.awt.image.BufferedImage;
import java.io.File;

import javax.imageio.ImageIO;

import math.Color;
import shader.screenshader.ScreenDistanceShader;
import shader.screenshader.ScreenNormalShader;
import shader.screenshader.ScreenPixelShader;
import shader.screenshader.ScreenShader;

public class TestScreen {
    public static void runTest(){
        int size = 512;

        makeScreenImage(size, new ScreenPixelShader());
        makeScreenImage(size, new ScreenDistanceShader());
        makeScreenImage(size, new ScreenNormalShader());
    }

    public static void makeScreenImage(int size, ScreenShader shader){
        BufferedImage image = new BufferedImage(size,size,BufferedImage.TYPE_INT_RGB);
        Color def = new Color(41, 139, 95); // default color
        Color c = null;
        for (int x = 0; x < size; x++) for (int y = 0; y < size; y++) {
            c = shader.getColor(x, y, size);
            if(c == null) c = def;
            image.setRGB(x, y, c.rgb());
        };
        File file = new File("./images/"+shader.getName()+".png");
        try {
            ImageIO.write(image, "png", file);   
        } catch (Exception e) {
            System.out.println(e.getMessage());
        }
    }
}
