/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.reservoir;

import epanet.core.network;
import epanet.core.units;
import epanet.elements.node;
import epanet.elements.pattern;

//! \class Reservoir
//! \brief A fixed head Node with no storage volume.
//!
//! \note The reservoir's fixed head can be made to vary over time by
//!       specifying a time pattern.

class Reservoir: Node
{
  public:

    // Constructor/Destructor
    this(string name_){
        super(name_);
        headPattern = null;
        fullDemand = 0.0;
        fixedGrade = true;
    }

    ~this(){}

    // Methods
    override int type() { return Node.RESERVOIR; }

    override void convertUnits(Network nw){
        elev /= nw.ucf(Units.LENGTH);
        initQual /= nw.ucf(Units.CONCEN);
    }

    override void setFixedGrade(){
        double f = 1.0;
        if ( headPattern )
        {
            f = headPattern.currentFactor();
        }
        head = elev * f;
        fixedGrade = true;
    }

    // Properties
    Pattern headPattern;    //!< time pattern for reservoir's head
}