/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.junction;

import std.container.dlist;

import epanet.elements.node;
import epanet.elements.emitter;
import epanet.core.units;
import epanet.elements.demand;
import epanet.core.network;
import epanet.core.constants;
import epanet.core.options;

//! \class Junction
//! \brief A variable head Node with no storage volume.

class Junction: Node
{
  public:

    this(string name_){
        super(name_);
        pMin = MISSING;
        pFull = MISSING;
        emitter = null;
        primaryDemand = new Demand();
    }

    ~this(){
        foreach(dem; demands[]) // not required with GC but let's put it here for future things like nogc modifications.
            dem.destroy();
        demands.clear();
        primaryDemand.destroy();
        emitter.destroy();
    }

    override int type() { return Node.JUNCTION; }

    override void convertUnits(Network nw){
        import std.range: walkLength;
        // ... convert elevation & initial quality units
        
        elev /= nw.ucf(Units.LENGTH);
        initQual /= nw.ucf(Units.CONCEN);

        // ... if no demand categories exist, add primary demand to list
        
        if (demands[].walkLength == 0) demands.insertBack(primaryDemand);
        
        // ... convert flow units for base demand in each demand category

        double qcf = nw.ucf(Units.FLOW);
        foreach (ref demand; demands[])
        {
            demand.baseDemand /= qcf;
        }

        // ... convert emitter flow units

        if (emitter) emitter.convertUnits(nw);

        // ... use global pressure limits if no local limits assigned

        if ( pMin == MISSING )  pMin = nw.option(Options.MINIMUM_PRESSURE);
        if ( pFull == MISSING ) pFull = nw.option(Options.SERVICE_PRESSURE);

        // ... convert units of pressure limits

        double pUcf = nw.ucf(Units.PRESSURE);
        pMin /= pUcf;
        pFull /= pUcf;
    }
    override void initialize(Network nw){
        head = elev + (pFull - pMin) / 2.0;
        quality = initQual;
        actualDemand = 0.0;
        outflow = 0.0;
        fixedGrade = false;
    }

    override void findFullDemand(double multiplier, double patternFactor){
        fullDemand = 0.0;
        foreach (Demand demand; demands[])
        {
            fullDemand += demand.getFullDemand(multiplier, patternFactor);
        }
        actualDemand = fullDemand;
    }

    override double findActualDemand(Network nw, double h, ref double dqdh){
        return nw.demandModel.findDemand(this, h-elev, dqdh);
    }
    override double findEmitterFlow(double h, ref double dqdh){
        dqdh = 0.0;
        if ( emitter) return emitter.findFlowRate(h-elev, dqdh);
        return 0;
    }

    override bool isPressureDeficient(Network nw){
        return nw.demandModel.isPressureDeficient(this);
    }
    override bool hasEmitter() { return emitter !is null; }

    Demand            primaryDemand;   //!< primary demand
    DList!Demand      demands;              //!< collection of additional demands
    double            pMin;            //!< minimum pressure head to have demand (ft)
    double            pFull;           //!< pressure head required for full demand (ft)
    Emitter          emitter;         //!< emitter object
}