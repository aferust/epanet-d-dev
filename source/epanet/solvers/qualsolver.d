/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.solvers.qualsolver;

import epanet.core.qualbalance;
import epanet.core.network;
import epanet.elements.link;
import epanet.solvers.ltdsolver;


//! \class QualSolver
//! \brief Abstract class from which a specific water quality solver is derived.

class QualSolver
{
  public:

    // Constructor/Destructor
    this(Network nw){network = nw;}
    ~this(){}

    // Factory method
    static QualSolver factory(const string name, Network nw){
        if ( name == "LTD" ) return new LTDSolver(nw);
        return null;
    }

    // Public Methods
    void init_() { }
    void reverseFlow(int linkIndex) { }
    abstract int solve(int* sortedLinks, int timeStep);

  protected:
    Network     network;
}
