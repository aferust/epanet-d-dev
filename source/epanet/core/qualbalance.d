/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.core.qualbalance;

import std.outbuffer: OutBuffer;

// import epanet.core.network;
import epanet.elements.element;
import epanet.core.network;

struct QualBalance
{
    double    initMass;
    double    inflowMass;
    double    outflowMass;
    double    reactedMass;
    double    storedMass;

    void init_(const double initMassStored){
        initMass = initMassStored;
        inflowMass = 0.0;
        outflowMass = 0.0;
        reactedMass = 0.0;
        storedMass = initMass;
    }

    void updateInflow(const double massIn){
        inflowMass += massIn;
    }

    void updateOutflow(const double massOut){
        outflowMass += massOut;
    }

    void updateReacted(const double massReacted){
        reactedMass += massReacted;
    }

    void updateStored(const double massStored){
        storedMass = massStored;
    }

    void writeBalance(OutBuffer msgLog){
        msgLog.writef("\n  Water Quality Mass Balance");
        msgLog.writef("\n  --------------------------");
        msgLog.writef("\n  Initial Storage           %f", initMass / 1.0e6);
        msgLog.writef("\n  Mass Inflow               %f", inflowMass / 1.0e6);
        msgLog.writef("\n  Mass Outflow              %f", outflowMass / 1.0e6);
        msgLog.writef("\n  Mass Reacted              %f", reactedMass / 1.0e6);
        msgLog.writef("\n  Final Storage             %f", storedMass / 1.0e6);

        double massIn = initMass + inflowMass;
        double massOut = outflowMass + reactedMass + storedMass;
        double pctDiff = (massIn - massOut);
        if ( massIn > 0.0 ) pctDiff = 100.0 * pctDiff / massIn;
        else if (massOut > 0.0 ) pctDiff = 100.0 * pctDiff / massOut;
        else pctDiff = 0.0;
        msgLog.writef("\n  Percent Imbalance         %f\n", pctDiff);
    }
}