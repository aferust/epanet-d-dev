/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.pipe;

import std.math;
import std.outbuffer;

import epanet.elements.link;
import epanet.core.network;
import epanet.core.constants;
import epanet.core.units;
import epanet.core.options;
import epanet.models.headlossmodel;
import epanet.models.leakagemodel;

//! \class Pipe
//! \brief A circular conduit Link through which water flows.

class Pipe: Link
{
  public:

    // Constructor/Destructor

    this(string name){
        super(name);
        hasCheckValve = false;
        length = 0.0;
        roughness = 0.0;
        resistance = 0.0;
        lossFactor = 0.0;
        leakCoeff1 = MISSING;
        leakCoeff2 = MISSING;
        bulkCoeff = MISSING;
        wallCoeff = MISSING;
        massTransCoeff = 0.0;
    }
    

    ~this(){}

    // Methods

    override int type() { return Link.PIPE; }
    override string typeStr() { return "Pipe"; }

    override void convertUnits(Network nw){
        import core.stdc.math;

        diameter /= nw.ucf(Units.DIAMETER);
        length   /= nw.ucf(Units.LENGTH);

        // ... convert minor loss coeff. from V^2/2g basis to Q^2 basis

        lossFactor = 0.02517 * lossCoeff / pow(diameter, 4);

        // ... convert roughness length units of Darcy-Weisbach headloss model
        //     (millifeet or millimeters to feet)

        if ( nw.option(Options.HEADLOSS_MODEL ) == "D-W")
        {
            roughness = roughness / nw.ucf(Units.LENGTH) / 1000.0;
        }

        // ... apply global default leakage coeffs.

        if ( leakCoeff1 == MISSING ) leakCoeff1 = nw.option(Options.LEAKAGE_COEFF1);
        if ( leakCoeff2 == MISSING ) leakCoeff2 = nw.option(Options.LEAKAGE_COEFF2);

        // ... apply global default reaction coeffs.

        if ( bulkCoeff == MISSING ) bulkCoeff = nw.option(Options.BULK_COEFF);
        if ( wallCoeff == MISSING ) wallCoeff = nw.option(Options.WALL_COEFF);
    }

    override bool isReactive(){
        if ( bulkCoeff != 0.0 ) return true;
        if ( wallCoeff != 0.0 ) return true;
        return false;
    }

    override void setInitFlow(){
        // ... flow at velocity of 1 ft/s
        flow = PI * diameter * diameter / 4.0;
    }

    override void setInitStatus(int s){initStatus = s;}

    override void setInitSetting(double s){
        if ( s == 0.0 ) initStatus = LINK_CLOSED;
        else            initStatus = LINK_OPEN;
    }

    override void setResistance(Network nw){
        nw.headLossModel.setResistance(this);
    }

    override double getRe(const double q, const double viscos){
        return  abs(q) / (PI * diameter * diameter / 4.0) * diameter / viscos;
    }

    override double getResistance() {return resistance;}

    override double getVelocity(){
        double area = PI * diameter * diameter / 4.0;
        return abs(flow) / area;
    }

    override double getUnitHeadLoss(){
        if ( length > 0.0 ) return abs(hLoss) * 1000.0 / length;
        return 0.0;
    }

    override double getSetting(Network nw) { return roughness; }
    override double getVolume() { return 0.785398 * length * diameter * diameter; }

    override void findHeadLoss(Network nw, double q){
        if ( status == LINK_CLOSED || status == TEMP_CLOSED )
        {
            HeadLossModel.findClosedHeadLoss(q, hLoss, hGrad);
        }
        else
        {
            nw.headLossModel.findHeadLoss(this, q, hLoss, hGrad);
            if ( hasCheckValve ) HeadLossModel.addCVHeadLoss(q, hLoss, hGrad);
        }
    }

    override bool canLeak() { return leakCoeff1 > 0.0; }

    override double findLeakage(Network nw, double h, ref double dqdh){
        return nw.leakageModel.findFlow(leakCoeff1, leakCoeff2, length, h, dqdh);
    }
    
    override bool changeStatus(int s, bool makeChange,
                            const string reason,
                            OutBuffer msgLog){
        if ( status != s )
        {
            if ( makeChange )
            {
                msgLog.writef("\n    %s", reason);
                status = s;
            }
            return true;
        }
        return false;
    }

    override void validateStatus(Network nw, double qTol){
        if ( hasCheckValve && flow < -qTol )
        {
            nw.msgLog.writef("\nCV %s flow = %f", name, flow*nw.ucf(Units.FLOW));
        }
    }

    // Properties

    bool   hasCheckValve;    //!< true if pipe has a check valve
    double length;           //!< pipe length (ft)
    double roughness;        //!< roughness parameter (units depend on head loss model)
    double resistance;       //!< resistance factor (units depend head loss model)
    double lossFactor;       //!< minor loss factor (ft/cfs^2)
    double leakCoeff1;       //!< leakage coefficient (user units)
    double leakCoeff2;       //!< leakage coefficient (user units)
    double bulkCoeff;        //!< bulk reaction coefficient (mass^n/sec)
    double wallCoeff;        //!< wall reaction coefficient (mass^n/sec)
    double massTransCoeff;   //!< mass transfer coefficient (mass^n/sec)
 }