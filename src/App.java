import shader.*;
import geometry.*;
import math.*;
import scene.*;

class App {
    public static void main(String[] args){
        new Scene("./scenes/myScene.json").makeImage(new NormalShader(), "Test");
    }
}