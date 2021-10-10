/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.models.pumpenergy;

import core.stdc.math;
import std.algorithm.comparison;

import epanet.elements.pump;
import epanet.elements.pattern;
import epanet.elements.curve;
import epanet.elements.node;
import epanet.core.network;
import epanet.core.constants;
import epanet.elements.link;
import epanet.core.options;
import epanet.core.units;

enum NO_FLOW = 2.23e-4;    // cfs ( = 0.1 gpm)

//! \class PumpEnergy
//! \brief Accumulates energy usage metrics for a pump.

class PumpEnergy
{
  public:

    // Constructor
    this(){
        init_();
    }

    // Methods
    void   init_(){
        hrsOnLine = 0.0;
        efficiency = 0.0;
        kwHrsPerCFS = 0.0;
        kwHrs = 0.0;
        maxKwatts = 0.0;
        totalCost = 0.0;
    }

    double updateEnergyUsage(Pump pump, Network network, int dt){
        // ... return if pump is off line

        if ( pump.status == Link.LINK_CLOSED ||
            pump.speed == 0 ||
            pump.flow < NO_FLOW ) return 0.0;

        // ... find head delivered by pump

        double head = pump.toNode.head - pump.fromNode.head;

        // ... find pump's efficiency (%)

        double e = findEfficiency(pump, network);

        // ... find energy (kwatts) consumed

        double sg = network.option(Options.SPEC_GRAVITY);
        double kw = head * pump.flow * sg / 8.814 / (e / 100.0) * KWperHP;

        // ... convert time step to hours

        double hrs = dt / 3600.0;
        double totalHrs = hrsOnLine + hrs;

        // ... update cumulative energy usage variables

        efficiency = ((efficiency * hrsOnLine) + (e * hrs)) / totalHrs;
        kwHrs = ((kwHrs * hrsOnLine) + (kw * hrs)) / totalHrs;

        kwHrsPerCFS = ( (kwHrsPerCFS * hrsOnLine) +
                        (kw / pump.flow * hrs) ) / totalHrs;

        totalCost = ( (totalCost * hrsOnLine) +
                    (kw * findCostFactor(pump, network) * hrs) ) / totalHrs;

        hrsOnLine = totalHrs;
        if ( kw > maxKwatts ) maxKwatts = kw;
        return kw;
    }

    // Computed Properties
    double hrsOnLine;        //!< hours pump is online
    double efficiency;       //!< total time wtd. efficiency
    double kwHrsPerCFS;      //!< total kw-hrs per cfs of flow
    double kwHrs;            //!< total kw-hrs consumed
    double maxKwatts;        //!< max. kw consumed
    double totalCost;        //!< total pumping cost

  private:

    double findCostFactor(Pump pump, Network network){
        // ... determine cost per Kwh

        double costPerKwh = network.option(Options.ENERGY_PRICE);
        if ( pump.costPerKwh > 0.0 ) costPerKwh = pump.costPerKwh;

        // ... determine time pattern adjustment

        double costFactor = 1.0;
        int patIndex = network.option(Options.ENERGY_PRICE_PATTERN);
        if ( patIndex >= 0 )
        {
            costFactor = network.pattern(patIndex).currentFactor();
        }
        if ( pump.costPattern ) costFactor = pump.costPattern.currentFactor();

        // ... return pattern-adjusted cost

        return costFactor * costPerKwh;
    }
    double findEfficiency(Pump pump, Network network){
        // ... use 100% efficiency if pump is closed

        if ( pump.flow * pump.speed == 0.0 ) return 100.0;

        // ... default efficiency is global value

        double effic = network.option(Options.PUMP_EFFICIENCY);

        // ... if pump has an efficiency curve then use it

        if ( pump.efficCurve )
        {
            // ... adjust pump flow for speed setting since curve applies to
            //     a speed setting of 1
            double q = pump.flow / pump.speed * network.ucf(Units.FLOW);

            // ... look up efficiency for the adjusted flow
            effic = pump.efficCurve.getYofX(q);

            // ... apply the Sarbu and Borza pump speed adjustment
            effic = 100.0 - ((100.0-effic) * pow(1.0/pump.speed, 0.1));
            effic = min(effic, 100.0);
            effic = max(effic, 1.0);
        }
        return effic;
    }
}