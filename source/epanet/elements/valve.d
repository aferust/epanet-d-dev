/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.valve;

import std.math;
import std.outbuffer;
import std.algorithm.comparison;

import epanet.elements.link;
import epanet.elements.curve;
import epanet.core.network;
import epanet.core.units;
import epanet.core.constants;
import epanet.models.headlossmodel;
//! \class Valve
//! \brief A Link that controls flow or pressure.
//! \note Isolation (or shutoff) valves can be modeled by setting a
//!       pipe's Status property to OPEN or CLOSED.

class Valve: Link
{
  public:

    enum {
        PRV,               //!< pressure reducing valve
        PSV,               //!< pressure sustaining valve
        FCV,               //!< flow control valve
        TCV,               //!< throttle control valve
        PBV,               //!< pressure breaker valve
        GPV                //!< general purpose valve
    }
    alias ValveType = int;

    static string[6] ValveTypeWords = ["PRV", "PSV", "FCV", "TCV", "PBV", "GPV"];
    enum MIN_LOSS_COEFF = 0.1;

    // Constructor/Destructor
    this(string name_){
        super(name_);
        valveType = TCV;
        lossFactor = 0.0;
        hasFixedStatus = false;
        elev = 0.0;

        initStatus = VALVE_ACTIVE;
        initSetting = 0;
    }
    ~this(){}

    // Methods
    override int type(){ return Link.VALVE; }

    override string typeStr(){return ValveTypeWords[valveType];}

    override void convertUnits(Network nw){
        import core.stdc.math;
         // ... convert diameter units
        diameter /= nw.ucf(Units.DIAMETER);

        // ... apply a minimum minor loss coeff. if necessary
        double c = lossCoeff;
        if ( c < MIN_LOSS_COEFF ) c = MIN_LOSS_COEFF;

        // ... convert minor loss from V^2/2g basis to Q^2 basis
        lossFactor = 0.02517 * c / pow(diameter, 4);

        // ... convert initial valve setting units
        initSetting = convertSetting(nw, initSetting);
    }

    override double convertSetting(Network nw, double s){
        switch (valveType)
        {
        // ... convert pressure valve setting
        case PRV:
        case PSV:
        case PBV: s /= nw.ucf(Units.PRESSURE); break;

        // ... convert flow valve setting
        case FCV: s /= nw.ucf(Units.FLOW); break;

        default: break;
        }
        if (valveType == PRV) elev = toNode.elev;
        if (valveType == PSV) elev = fromNode.elev;
        return s;
    }

    override void setInitFlow(){
        // ... flow at velocity of 1 ft/s
        flow = PI * diameter * diameter / 4.0;
        if (valveType == FCV)
        {
            flow = setting;
        }
    }

    override void setInitStatus(int s){
        initStatus = s;
        hasFixedStatus = true;
    }

    override void setInitSetting(double s){
        initSetting = s;
        initStatus = VALVE_ACTIVE;
        hasFixedStatus = false;
    }
    override void initialize(bool reInitFlow){
        status = initStatus;
        setting = initSetting;
        if ( reInitFlow ) setInitFlow();
        hasFixedStatus = (initStatus != VALVE_ACTIVE);
    }

    override bool isPRV(){ return valveType == PRV; }
    override bool isPSV(){ return valveType == PSV; }

    override void findHeadLoss(Network nw, double q){
        hLoss = 0.0;
        hGrad = 0.0;

        // ... valve is temporarily closed (e.g., tries to drain an empty tank)

        if ( status == TEMP_CLOSED)
        {
            HeadLossModel.findClosedHeadLoss(q, hLoss, hGrad);
        }

        // ... valve has fixed status (OPEN or CLOSED)

        else if ( hasFixedStatus )
        {
            if (status == LINK_CLOSED)
            {
                HeadLossModel.findClosedHeadLoss(q, hLoss, hGrad);
            }
            else if (status == LINK_OPEN) findOpenHeadLoss(q);
        }

        // ... head loss for active valves depends on valve type

        else switch (valveType)
        {
        case PBV: findPbvHeadLoss(q); break;
        case TCV: findTcvHeadLoss(q); break;
        case GPV: findGpvHeadLoss(nw, q); break;
        case FCV: findFcvHeadLoss(q); break;

        // ... PRVs & PSVs without fixed status can be either
        //     OPEN, CLOSED, or ACTIVE.
        case PRV:
        case PSV:
            if ( status == LINK_CLOSED )
            {
                HeadLossModel.findClosedHeadLoss(q, hLoss, hGrad);
            }
            else if ( status == LINK_OPEN ) findOpenHeadLoss(q);
            break;
        default: break;
        }
    }
    override void updateStatus(double q, double h1, double h2){
        if ( hasFixedStatus ) return;
        int newStatus = status;

        switch ( valveType )
        {
            case PRV: newStatus = updatePrvStatus(q, h1, h2); break;
            case PSV: newStatus = updatePsvStatus(q, h1, h2); break;
            default:  break;
        }

        if ( newStatus != status )
        {
            if ( newStatus == Link.LINK_CLOSED ) flow = ZERO_FLOW;
            status = newStatus;

        }
    }

    override bool changeStatus(int newStatus,
                             bool makeChange,
                             const string reason,
                             OutBuffer msgLog)
    {
        if ( !hasFixedStatus || status != newStatus )
        {
            if ( makeChange )
            {
                msgLog.writef("\n%s", reason);
                status = newStatus;
                hasFixedStatus = true;
                if ( status == LINK_CLOSED ) flow = ZERO_FLOW;
            }
            return true;
        }
        return false;
    }
    override bool changeSetting(double newSetting,
                              bool makeChange,
                              const string reason,
                              OutBuffer msgLog)
        {
        if ( newSetting != setting )
        {
            if ( makeChange )
            {
                hasFixedStatus = false;
                status = Link.LINK_OPEN;
                msgLog.writef("\n%s", reason);
                setting = newSetting;
            }
            return true;
        }
        return false;
    }

    override void validateStatus(Network nw, double qTol){
        switch (valveType)
        {
        case PRV:
        case PSV:
            if (flow < -qTol)
            {
                nw.msgLog.writef("\nValve %s flow = %f", name, flow*nw.ucf(Units.FLOW));
            }
            break;

        default: break;
        }
    }

    override double getVelocity(){
        double area = PI * diameter * diameter / 4.0;
        return flow / area;
    }

    override double getRe(const double q, const double viscos){
        return  abs(q) / (PI * diameter * diameter / 4.0) * diameter / viscos;
    }

    override double getSetting(Network nw){
        switch(valveType)
        {
        case PRV:
        case PSV:
        case PBV: return setting * nw.ucf(Units.PRESSURE);
        case FCV: return setting * nw.ucf(Units.FLOW);
        default:  return setting;
        }
    }

    // Properties
    ValveType   valveType;      //!< valve type
    double      lossFactor;     //!< minor loss factor

  protected:

    void findOpenHeadLoss(double q){
        hGrad = 2.0 * lossFactor * abs(q);
        if ( hGrad < MIN_GRADIENT )
        {
            hGrad = MIN_GRADIENT;
            hLoss = hGrad * q;
        }
        else hLoss = hGrad * q / 2.0;
    }

    void findPbvHeadLoss(double q){
        // ... treat as open valve if minor loss > valve setting

        double mloss = lossFactor * q * q;
        if ( mloss >= abs(setting) ) findOpenHeadLoss(q);

        // ... otherwise force head loss across valve equal to setting

        else
        {
            hGrad = MIN_GRADIENT;
            hLoss = setting;
        }
    }

    void findTcvHeadLoss(double q){
        //... save open valve loss factor

        double f = lossFactor;

        // ... convert throttled loss coeff. setting to a loss factor

        double d2 = diameter * diameter;
        lossFactor = 0.025173 * setting / d2 / d2;

        // ... throttled loss coeff. can't be less than fully open coeff.

        lossFactor = max(lossFactor, f);

        // ... use the setting's loss factor to compute head loss

        findOpenHeadLoss(q);

        // ... restore open valve loss factor

        lossFactor = f;
    }

    void findGpvHeadLoss(Network nw, double q){
        // ... retrieve head loss curve for valve

        int curveIndex = cast(int)setting;
        Curve curve = nw.curve(curveIndex);

        // ... retrieve units conversion factors (curve is in user's units)

        double ucfFlow = nw.ucf(Units.FLOW);
        double ucfHead = nw.ucf(Units.LENGTH);

        // ... find slope (r) and intercept (h0) of curve segment

        double qRaw = abs(q) * ucfFlow;
        double r, h0;
        curve.findSegment(qRaw, r, h0);

        // ... convert to internal units

        r *= ucfFlow / ucfHead;
        h0 /= ucfHead;

        // ... determine head loss and derivative for this curve segment

        hGrad = r; //+ 2.0 * lossFactor * abs(q);
        hLoss = h0 + r * abs(q); // + lossFactor * q * q;
        if ( q < 0.0 ) hLoss = -hLoss;
    }

    void findFcvHeadLoss(double q){
        double xflow = q - setting;    // flow in excess of the setting

        // ... apply a large head loss factor to the flow excess

        if (xflow > 0.0)
        {
            hLoss = lossFactor * setting * setting + HIGH_RESISTANCE * xflow;
            hGrad = HIGH_RESISTANCE;
        }

        // ... otherwise treat valve as an open valve

        else
        {
            if ( q < 0.0 )
            {
                HeadLossModel.findClosedHeadLoss(q, hLoss, hGrad);
            }
            else findOpenHeadLoss(q);
        }
    }

    int updatePrvStatus(double q, double h1, double h2){
        int    s = status;                      // new valve status
        double hset = setting + elev;           // head setting

        switch ( status )
        {
        case VALVE_ACTIVE:
            if      ( q < -ZERO_FLOW ) s = LINK_CLOSED;
            else if ( h1 < hset )      s = LINK_OPEN;
            break;

        case LINK_OPEN:
            if      ( q < -ZERO_FLOW ) s = LINK_CLOSED;
            else if ( h2 > hset )      s = VALVE_ACTIVE;
            break;

        case LINK_CLOSED:
            if      ( h1 > hset && h2 < hset ) s = VALVE_ACTIVE;
            else if ( h1 < hset && h1 > h2 )   s = LINK_OPEN;
            break;
        default: break;
        }
        return s;
    }

    int updatePsvStatus(double q, double h1, double h2){
        int s = status;                      // new valve status
        double hset = setting + elev;           // head setting

        switch (status)
        {
        case VALVE_ACTIVE:
            if      (q < -ZERO_FLOW ) s = LINK_CLOSED;
            else if (h2 > hset )      s = LINK_OPEN;
            break;

        case LINK_OPEN:
            if      (q < -ZERO_FLOW ) s = LINK_CLOSED;
            else if (h1 < hset )      s = VALVE_ACTIVE;
            break;

        case LINK_CLOSED:
            if      ( h2 < hset && h1 > hset) s = VALVE_ACTIVE;
            else if ( h2 > hset && h1 > h2 )  s = LINK_OPEN;
            break;
        default: break;
        }
        return s;
    }

    bool        hasFixedStatus;   //!< true if Open/Closed status is fixed
    double      elev;             //!< elevation of PRV/PSV valve
}