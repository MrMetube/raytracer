class Environment {
    private Vector gravity;
    private Vector wind;

    Environment(Vector gravity, Vector wind){
        this.gravity = gravity;
        this.wind = wind;
    }

    public Vector grav() { return gravity; }
    public Vector wind() { return wind; }
    
}
