import shader.*;
import scene.*;

class App {
    public static void main(String[] args){
        new Scene("./scenes/myScene.json").makeImage(new NormalShader(), "test");
    }
}