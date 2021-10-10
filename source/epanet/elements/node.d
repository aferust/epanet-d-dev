/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.node;

import epanet.elements.element;
import epanet.elements.qualsource;
import epanet.elements.emitter;
import epanet.elements.tank;
import epanet.core.network;
import epanet.elements.junction;
import epanet.elements.reservoir;

class Node: Element
{
  public:

    enum {JUNCTION, TANK, RESERVOIR}
    
    alias NodeType = int;

    this(string name_){
        super(name_);
        rptFlag = false;
        elev = 0.0;
        xCoord = -1e20;
        yCoord = -1e20;
        initQual = 0.0;
        qualSource = null;
        fixedGrade = false;
        head = 0.0;
        qGrad = 0.0;
        fullDemand = 0.0;
        actualDemand = 0.0;
        outflow = 0.0;
        quality = 0.0;

        qualSource = new QualSource();
    }

    ~this(){
        // qualSource destruction if nogc is implemented
    }

    static Node factory(int type_, string name_/*, MemPool* memPool*/){
        switch (type_)
        {
        case JUNCTION:
            return new Junction(name_);
        case RESERVOIR:
            return new Reservoir(name_);
        case TANK:
            return new Tank(name_);
        default:
            return null;
        }
    }

    abstract int    type();
    abstract void   convertUnits(Network nw);

    void initialize(Network nw){
        head = elev;
        quality = initQual;
        if ( qualSource ) qualSource.quality = quality;
        actualDemand = 0.0;
        outflow = 0.0;
        if ( type() == JUNCTION ) fixedGrade = false;
        else fixedGrade = true;
    }

    // Overridden for Junction nodes
    void   findFullDemand(double multiplier, double patternFactor) { }
    
    double findActualDemand(Network nw, double h, ref double dqdh) { return 0; }
    double findEmitterFlow(double h, ref double dqdh) { return 0; }
    
    void   setFixedGrade() { fixedGrade = false; }
    bool   isPressureDeficient(Network nw) { return false; }
    bool   hasEmitter() { return false; }

    // Overridden for Tank nodes
    void   validate(Network nw){};
    bool   isReactive() { return false; }
    bool   isFull() { return false; }
    bool   isEmpty() { return false; }
    bool   isClosed(double flow) { return false; }
    double getVolume() { return 0.0; }

    // Input Parameters
    bool           rptFlag;       //!< true if results are reported
    double         elev;          //!< elevation (ft)
    double         xCoord;        //!< X-coordinate
    double         yCoord;        //!< Y-coordinate
    double         initQual;      //!< initial water quality concen.
    QualSource     qualSource;    //!< water quality source information

    // Computed Variables
    bool           fixedGrade;    //!< fixed grade status
    double         head;          //!< hydraulic head (ft)
    double         qGrad;         //!< gradient of outflow w.r.t. head (cfs/ft)
    double         fullDemand;    //!< full demand required (cfs)
    double         actualDemand;  //!< actual demand delivered (cfs)
    double         outflow;       //!< demand + emitter + leakage flow (cfs)
    double         quality;       //!< water quality concen. (mass/ft3)
}