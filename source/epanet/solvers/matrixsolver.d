/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.solvers.matrixsolver;

import std.outbuffer;

import epanet.solvers.sparspaksolver;

class MatrixSolver
{
  public:

    this(){}
    ~this(){}

    static MatrixSolver factory(S)(auto ref S name, OutBuffer logger){
        //if (name == "CHOLMOD") return new CholmodSolver();
        if (name == "SPARSPAK") return new SparspakSolver(logger);
        return null;
    }

    abstract int init_(int nRows, int nOffDiags, int* offDiagRow, int* offDiagCol);
    abstract void reset();

    double getDiag(int i)    {return 0.0;}
    double getOffDiag(int i) {return 0.0;}
    double getRhs(int i)     {return 0.0;}

    abstract void   setDiag(int row, double a);
    abstract void   setRhs(int row, double b);
    abstract void   addToDiag(int row, double a);
    abstract void   addToOffDiag(int offDiag, double a);
    abstract void   addToRhs(int row, double b);
    abstract int    solve(int nRows, double* x);

    void debug_(OutBuffer out_) {}
}