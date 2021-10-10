/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.solvers.hydsolver;

import epanet.core.network;
import epanet.solvers.matrixsolver;
import epanet.solvers.ggasolver;

//! \class HydSolver
//! \brief Interface for an equilibrium network hydraulic solver.
//!
//! This is an abstract class that defines an interface for a
//! specific algorithm used for solving pipe network hydraulics at a
//! given instance in time.

class HydSolver
{
  public:

    enum { // StatusCode
        SUCCESSFUL,
        FAILED_NO_CONVERGENCE,
        FAILED_ILL_CONDITIONED
    }

    this(Network nw, MatrixSolver ms){
        network = nw;
        matrixSolver = ms;
    }

    ~this(){}

    static HydSolver factory(const string name, Network nw, MatrixSolver ms){
        if (name == "GGA") return new GGASolver(nw, ms);
        return null;
    }

    abstract int solve(double tstep, ref int trials);

  protected:

    Network       network;
    MatrixSolver  matrixSolver;

}
