import shader.*;
import geometry.*;
import math.*;
import scene.*;

class App {
    public static void main(String[] args){
        new Scene("./scenes/myScene.json").makeImage(new NormalShader(),   "test1");
        new Scene("./scenes/Example 1.json").makeImage(new NormalShader(), "test2");
        new Scene("./scenes/Example 2.json").makeImage(new NormalShader(), "test3");
        new Scene("./scenes/Example 3.json").makeImage(new NormalShader(), "test4");
        new Scene("./scenes/Example 4.json").makeImage(new NormalShader(), "test5");
    }
}