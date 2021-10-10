/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.emitter;

import core.stdc.math;

import epanet.core.network;
import epanet.elements.pattern;
import epanet.elements.junction;
import epanet.core.units;

class Emitter
{
  public:

    // Constructor/Destructor
    this(){
        flowCoeff = 0;
        expon = 0.0;
        timePattern = null;
    }
    ~this(){}

    // Static factory method to add or edit an emitter
    static bool addEmitter(Junction junc, double c, double e, Pattern p){
        if ( junc.emitter is null )
        {
            junc.emitter = new Emitter();
            if ( junc.emitter is null ) return false;
        }
        junc.emitter.flowCoeff = c;
        junc.emitter.expon = e;
        junc.emitter.timePattern = p;

        return true;
    }

    // Converts emitter properties to internal units
    void convertUnits(Network network){
        // ... get units conversion factors

        double qUcf = network.ucf(Units.FLOW);
        double pUcf = network.ucf(Units.PRESSURE);

        // ... convert flowCoeff from user flow units per psi (or meter)
        //     to cfs per foot of head

        flowCoeff *= pow(pUcf, expon) / qUcf;
    }

    // Finds the emitter's outflow rate and its derivative given the pressure head
    double findFlowRate(double h, ref double dqdh){
        
        dqdh = 0.0;
        if ( h <= 0.0 ) return 0.0;
        double a = flowCoeff;
        if (timePattern) a *= timePattern.currentFactor();
        double q = a * pow(h, expon);
        dqdh = expon * q / h;
        return q;
    }

    // Properties
    double      flowCoeff;     // flow = flowCoeff*(head^expon)
    double      expon;
    Pattern    timePattern;   // pattern for time varying flowCoeff
}