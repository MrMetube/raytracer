package math;

public class Matrix {
    //#region constants
    public static final Matrix zero2 = new Matrix(
        0,0,
        0,0);
    public static final Matrix zero3 = new Matrix(
        0,0,0,
        0,0,0,
        0,0,0);
    public static final Matrix zero4 = new Matrix(
        0,0,0,0,
        0,0,0,0,
        0,0,0,0,
        0,0,0,0);
    public static final Matrix identity2 = new Matrix(
        1,0,
        0,1);
    public static final Matrix identity3 = new Matrix(
        1,0,0,
        0,1,0,
        0,0,1);
    public static final Matrix identity4 = new Matrix(
        1,0,0,0,
        0,1,0,0,
        0,0,1,0,
        0,0,0,1);
    //#endregion
    
    double[] m;
    int dimension;
    double determinant = Double.POSITIVE_INFINITY;

    public Matrix(double... elements){
        // We only need square matrices so this is fine
        assert(Math.sqrt(elements.length)%1==0);
        dimension = (int) Math.sqrt(elements.length);
        m = elements;
    }

    public Matrix mul(Matrix m){
        assert(dimension==m.dimension());

        var res = new double[dimension*dimension];
        for (int row = 0; row < dimension; row++)
            for (int col = 0; col < dimension; col++){
                double value = 0;
                for (int i = 0; i < dimension; i++)
                    value += get(row,i) * m.get(i,col);
                res[row*dimension+col] = value;
            }

        return new Matrix(res);
    }

    public Tuple mul(Tuple t){
        assert(dimension == 4);
        double x = 
            get(0,0) * t.x() + 
            get(0,1) * t.y() + 
            get(0,2) * t.z() + 
            get(0,3) * t.w();
        double y = 
            get(1,0) * t.x() + 
            get(1,1) * t.y() + 
            get(1,2) * t.z() + 
            get(1,3) * t.w();
        double z = 
            get(2,0) * t.x() + 
            get(2,1) * t.y() + 
            get(2,2) * t.z() + 
            get(2,3) * t.w();
        double w = 
            get(3,0) * t.x() + 
            get(3,1) * t.y() + 
            get(3,2) * t.z() + 
            get(3,3) * t.w();
        return new Tuple(x,y,z,w);
    }

    public Matrix mul(double s){
        var res = new double[dimension*dimension];
        for (int i = 0; i < m.length; i++)
            res[i] = m[i] * s;

        return new Matrix(res);
    }

    public Matrix transpose(){
        var res = new double[dimension*dimension];
        for (int row = 0; row < dimension; row++)
            for (int col = 0; col < dimension; col++)
                res[col*dimension+row] = m[row*dimension+col];
        return new Matrix(res);
    }

    public double determinant(){
        if(determinant != Double.POSITIVE_INFINITY) return determinant;

        if(dimension == 2)
            determinant = get(0,0)*get(1,1) - get(0,1)*get(1,0);
        else{
            determinant = 0;
            for(int col = 0; col < dimension; col++)
                determinant += get(0,col) * cofactor(0, col);
        }
        return determinant;
    }

    public Matrix submatrix(int remRow, int remCol){
        assert(remRow >= 0 && remRow < dimension && remCol >= 0 && remCol < dimension);
        var res = new double[(dimension-1) * (dimension-1)];
        int dif = 0;
        int i;
        for (int row = 0; row < dimension; row++)
            for (int col = 0; col < dimension; col++){
                if(row == remRow || col == remCol) 
                    dif++;
                else{
                    i = row*dimension+col;
                    res[i-dif] = m[i];
                }
            }
        return new Matrix(res);
    }

    public Matrix inverse(){
        assert(isInvertible());

        var cofac = new double[dimension*dimension];
        for (int row = 0; row < dimension; row++)
            for (int col = 0; col < dimension; col++)
                cofac[row*dimension+col] = cofactor(row, col);
        
        return new Matrix(cofac).transpose().mul(1/determinant);
    }

    public double minor(int row, int col){
        return submatrix(row, col).determinant();
    }

    public double cofactor(int row, int col){
        return ((row+col)%2 * -2 + 1) * minor(row, col);
        // Its equivalent to this, but without branching
        // return ((row+col%2==0) ? 1 : -1) * minor(row, col);
    }

    public double get(int row, int col){
        assert(row >= 0 && row < dimension && col >= 0 && col < dimension);
        return m[row*dimension+col];
    }

    public int dimension(){ return dimension; }

    public boolean isInvertible(){
        determinant();
        return determinant != 0;
    }

    @Override
    public boolean equals(Object o) {
        if(o==null) return false;
        if(o==this) return true;
        if(!(o instanceof Matrix)) return false;
        
        var that = (Matrix) o;
        if(that.dimension() != dimension) return false;
        var res = true;
        for (int row = 0; row < dimension; row++)
            for (int col = 0; col < dimension; col++)
                if(!Util.approxEqual(get(row,col), that.get(row, col),Util.EPSILON)) 
                    res = false;
        return res;
    }
}
