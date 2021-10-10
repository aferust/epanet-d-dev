/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.pump;

import std.outbuffer;

import epanet.core.network;
import epanet.core.error;
import epanet.core.constants;
import epanet.elements.pattern;
import epanet.elements.curve;
import epanet.elements.link;
import epanet.models.pumpenergy;
import epanet.models.headlossmodel;
import epanet.elements.pumpcurve;
import epanet.core.units;

//! \class Pump
//! \brief A Link that raises the head of water flowing through it.

class Pump: Link
{
  public:

    // Constructor/Destructor

    this(string name_){
        super(name_);
        speed=1.0;
        speedPattern = null;
        efficCurve = null;
        costPattern = null;
        costPerKwh = 0.0;

        pumpCurve = new PumpCurve();
        pumpEnergy = new PumpEnergy();
    }

    ~this(){
        pumpCurve.destroy();
        pumpEnergy.destroy();
    }

    // Methods

    override int type() { return Link.PUMP; }

    override string typeStr() { return "Pump"; }

    override void convertUnits(Network nw){
        pumpCurve.horsepower /= nw.ucf(Units.POWER);
    }

    override void validate(Network nw){
        if ( pumpCurve.curve || pumpCurve.horsepower > 0.0 )
        {
            int err = pumpCurve.setupCurve(nw);
            if ( err ) throw new NetworkError(err, name);
        }
        else throw new NetworkError(NetworkError.NO_PUMP_CURVE, name);
    }

    override void setInitFlow(){
        // ... initial flow is design point of pump curve
        flow = pumpCurve.qInit * initSetting;
    }

    override void setInitStatus(int s){
        initStatus = s;
        if (s == LINK_OPEN)   initSetting = 1.0;
        if (s == LINK_CLOSED) initSetting = 0.0;
    }

    override void setInitSetting(double s){
        initSetting = s;
        speed = s;
        if ( s <= 0.0 ) initStatus = LINK_CLOSED;
        else            initStatus = LINK_OPEN;
    }

    double getSetting(Network* nw) { return speed; }

    override bool isHpPump() { return pumpCurve.isConstHP(); }

    override void findHeadLoss(Network nw, double q){
        // --- use high resistance head loss if pump is shut down
        if ( speed == 0.0  || status == LINK_CLOSED || status == TEMP_CLOSED )
        {
            HeadLossModel.findClosedHeadLoss(q, hLoss, hGrad);
        }

        // --- get head loss from pump curve and add a check valve
        //     head loss in case of reverse flow
        else
        {
            pumpCurve.findHeadLoss(speed, q, hLoss, hGrad);
            if ( !isHpPump() ) HeadLossModel.addCVHeadLoss(q, hLoss, hGrad);
        }
    }

    override double updateEnergyUsage(Network nw, int dt){
        return pumpEnergy.updateEnergyUsage(this, nw, dt);
    }

    override bool changeStatus(int s, bool makeChange,
                             const string reason,
                             OutBuffer msgLog)
    {
        if ( status != s )
        {
            if ( makeChange )
            {
                if ( s == LINK_OPEN && speed == 0.0 ) speed = 1.0;
                if ( s == LINK_CLOSED )
                {
                    flow = ZERO_FLOW;
                    speed = 0.0;
                }
                msgLog.writef("\n    %s", reason);
                status = s;
            }
            return true;
        }
        return false;
    }

    override bool changeSetting(double s, bool makeChange,
                              const string reason,
                              OutBuffer msgLog)
    {
        if ( speed != s )
        {
            if ( status == Link.LINK_CLOSED && s == 0.0 )
            {
                speed = s;
                return false;
            }

            if ( makeChange )
            {
                if ( s == 0.0 )
                {
                    status = Link.LINK_CLOSED;
                    flow = ZERO_FLOW;
                }
                else status = Link.LINK_OPEN;
                speed = s;
                msgLog.writef("\n    %s", reason);
            }
            return true;
        }
        return false;
    }

    override void validateStatus(Network nw, double qTol){
        if (flow < -qTol)
        {
            nw.msgLog.writef("\nPump %s flow = %f", name, flow*nw.ucf(Units.FLOW));
        }
    }

    override void applyControlPattern(OutBuffer msgLog){
        if ( speedPattern )
        {
            changeSetting(speedPattern.currentFactor(), true, "speed pattern", msgLog);
        }
    }

    // Properties

    PumpCurve  pumpCurve;      //!< pump's head v. flow relation
    double     speed;          //!< relative pump speed
    Pattern   speedPattern;   //!< speed time pattern
    PumpEnergy pumpEnergy;     //!< pump's energy usage
    Curve     efficCurve;     //!< efficiency. v. flow curve
    Pattern   costPattern;    //!< energy cost pattern
    double     costPerKwh;     //!< unit energy cost (cost/kwh)
 }