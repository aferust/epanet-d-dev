/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.demand;

import epanet.core.network;
import epanet.elements.pattern;

class Demand
{
  public:

    this(){
        baseDemand = 0.0;
        fullDemand = 0.0;
        timePattern = null;
    }
    ~this(){}

    double getFullDemand(double multiplier, double patternFactor){
        if ( timePattern ) patternFactor = timePattern.currentFactor();
        fullDemand = multiplier * baseDemand * patternFactor;
        return fullDemand;
    }

    double   baseDemand;          //!< baseline demand flow (cfs)
    double   fullDemand;          //!< pattern adjusted demand flow (cfs)
    Pattern timePattern;         //!< time pattern used to adjust baseline demand
}