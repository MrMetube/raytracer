class ScreenPixelShader implements ScreenShader {

    @Override
    public Color getColor(int x, int y, int size) {
        return new Color((x+0.5)*255/size,(y+0.5)*255/size,0);
    }
    
    @Override
    public String getName() {
        return "SCREEN_PIXEL";
    }
}
