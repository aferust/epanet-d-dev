/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.link;

import std.outbuffer;

import epanet.utilities.mempool;
import epanet.elements.node;
import epanet.elements.element;
import epanet.elements.pump;
import epanet.elements.pipe;
import epanet.elements.valve;
import epanet.core.network;
import epanet.core.constants;


static const string s_From = " status changed from ";
static const string s_To =   " to ";
static const string[4] linkStatusWords = ["CLOSED", "OPEN", "ACTIVE", "TEMP_CLOSED"];


class Link: Element
{
  public:

    enum {PIPE, PUMP, VALVE} // LinkType
    enum {LINK_CLOSED, LINK_OPEN, VALVE_ACTIVE, TEMP_CLOSED} // LinkStatus
    enum {BULK, WALL} // LinkReaction

    this(string name_){
        super(name_);
        rptFlag = false;
        fromNode = null;
        toNode = null;
        initStatus = LINK_OPEN;
        diameter = 0.0;
        lossCoeff = 0.0;
        initSetting = 1.0;
        status = 0;
        flow = 0.0;
        leakage = 0.0;
        hLoss = 0.0;
        hGrad = 0.0;
        setting = 0.0;
        quality = 0.0;
    }

    ~this(){}

    static  Link  factory(int type_, string name_/*, MemPool memPool*/){
        switch (type_)
        {
        case PIPE:
            return new Pipe(name_);
        case PUMP:
            return new Pump(name_);
        case VALVE:
            return new Valve(name_);
        default:
            return null;
        }
    }

    int         type(){return -1;}
    string      typeStr(){return null;}
    void        convertUnits(Network nw){}
    double      convertSetting(Network nw, double s) { return s; }
    void        validate(Network nw){}
    bool        isReactive() { return false; }

    // Initializes hydraulic settings
    void   initialize(bool reInitFlow){
        status = initStatus;
        setting = initSetting;
        if ( reInitFlow )
        {
            if ( status == LINK_CLOSED ) flow = ZERO_FLOW;
            else setInitFlow();
        }
        leakage = 0.0;
    }
    void   setInitFlow(){}
    void   setInitStatus(int s){}
    void   setInitSetting(double s){}
    void   setResistance(Network nw){}

    // Retrieves hydraulic variables
    double getVelocity() {return 0.0;}
    double getRe(const double q, const double viscos) {return 0.0;}
    double getResistance() {return 0.0;}

    double getUnitHeadLoss(){
        return hLoss;
    }
    
    double getSetting(Network nw) { return setting; }

    // Computes head loss, energy usage, and leakage
    void   findHeadLoss(Network nw, double q){}
    double updateEnergyUsage(Network nw, int dt) { return 0.0; }
    bool   canLeak() { return false; }
    double findLeakage(Network nw, double h, ref double dqdh) { return 0.0; }


    // Determines special types of links
    bool   isPRV() {return false;}
    bool   isPSV() {return false;}
    bool   isHpPump() {return false;}

    // Used to update and adjust link status/setting
    void   updateStatus(double q, double h1, double h2){}
    bool   changeStatus(int newStatus,
                    bool makeChange,
                    const string reason,
                    OutBuffer msgLog)
                    { return false; }
    bool changeSetting(double newSetting,
                                 bool makeChange,
                                 const string reason,
                                 OutBuffer msgLog)
                                 { return false; }
    void   validateStatus(Network nw, double qTol){}
    void   applyControlPattern(OutBuffer msgLog){}

    string writeStatusChange(int oldStatus){
        OutBuffer b = new OutBuffer;

        b.writef("    "); b.writef(typeStr()); b.writef(" ");
        b.writef(name); b.writef(s_From); b.writef(linkStatusWords[oldStatus]);
        b.writef(s_To); b.writef(linkStatusWords[status]);

        return b.toString();
    }

    // Used for water quality routing
    double getVolume() { return 0.0; }

    // Properties
    bool           rptFlag;          //!< true if results are reported
    Node           fromNode;         //!< pointer to the link's start node
    Node           toNode;           //!< pointer to the link's end node
    int            initStatus;       //!< initial Open/Closed status
    double         diameter;         //!< link diameter (ft)
    double         lossCoeff;        //!< minor head loss coefficient
    double         initSetting;      //!< initial pump speed or valve setting

    // Computed Variables
    int            status;           //!< current status
    double         flow;             //!< flow rate (cfs)
    double         leakage;          //!< leakage rate (cfs)
    double         hLoss;            //!< head loss (ft)
    double         hGrad;            //!< head loss gradient (ft/cfs)
    double         setting;          //!< current setting
    double         quality;          //!< avg. quality concen. (mass/ft3)
}