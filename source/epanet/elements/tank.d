/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.tank;

import std.algorithm.comparison;
import std.math: PI;

import epanet.elements.node;
import epanet.elements.curve;
import epanet.core.options;
import epanet.core.error;
import epanet.core.units;
import epanet.core.network;
import epanet.core.constants;
import epanet.models.tankmixmodel;

//! \class Tank
//! \brief A fixed head Node with storage volume.
//!
//! The fixed head for the tank varies from one time period to the next
//! depending on the filling or withdrawal rate.

class Tank: Node
{
  public:

    // Constructor/Destructor
    this(string name){
        super(name);
        initHead = 0.0;
        minHead = 0.0;
        maxHead = 0.0;
        diameter = 0.0;
        minVolume = 0.0;
        bulkCoeff = MISSING;
        volCurve = null;
        maxVolume = 0.0;
        volume = 0.0;
        area = 0.0;
        ucfLength = 1.0;
        pastHead = 0.0;
        pastVolume = 0.0;
        pastOutflow = 0.0;

        fullDemand = 0.0;
        fixedGrade = true;

        mixingModel = new TankMixModel();
    }
    //~Tank() {}

    // Overridden virtual methods
    override int type() { return Node.TANK; }

    override void validate(Network nw){
        // ... check for enough info to compute volume
        if ( diameter == 0.0 && volCurve is null )
        {
            throw new NetworkError(NetworkError.INVALID_VOLUME_CURVE, name);
        }

        // ... check that volume curve (depth v. volume in user units)
        //     covers range of depth limits
        if ( volCurve )
        {
            if ( volCurve.size() < 2 )
            {
                throw new NetworkError(NetworkError.INVALID_VOLUME_CURVE, name);
            }
            double tankHead = volCurve.x(0) / ucfLength + elev;
            minHead = max(minHead, tankHead);
            tankHead = volCurve.x(volCurve.size() - 1) / ucfLength + elev;
            maxHead = min(maxHead, tankHead);
        }

        // ... check for consistent depth limits
        if ( maxHead < minHead )
        {
            throw new NetworkError(NetworkError.INVALID_TANK_LEVELS, name);
        }
        initHead = max(initHead, minHead);
        initHead = min(initHead, maxHead);
    }
    override void convertUnits(Network nw){
        // ... convert from user to internal units
        ucfLength = nw.ucf(Units.LENGTH);
        initHead /= ucfLength;
        minHead /= ucfLength;
        maxHead /= ucfLength;
        diameter /= ucfLength;
        area = PI * diameter * diameter / 4.0;
        elev /= ucfLength;
        minVolume /= nw.ucf(Units.VOLUME);
        initQual /= nw.ucf(Units.CONCEN);

        // ... assign default bulk reaction rate coeff.
        if ( bulkCoeff == MISSING ) bulkCoeff = nw.option(Options.BULK_COEFF);
    }
    override void initialize(Network nw){
        head = initHead;
        pastHead = initHead;
        outflow = 0.0;
        pastOutflow = 0.0;
        quality = initQual;
        updateArea();
        if ( volCurve ) minVolume = findVolume(minHead);
        else if ( minVolume == 0.0 ) minVolume = (minHead - elev) * area;
        volume = findVolume(head);
        maxVolume = findVolume(maxHead);
        fixedGrade = true;
    }
    override bool isReactive() { return bulkCoeff != 0.0; }
    override bool isFull()     { return head >= maxHead; }
    override bool isEmpty()    { return head <= minHead; }
    override bool isClosed(double flow){
        if ( !fixedGrade ) return false;
        if ( head >= maxHead && flow < 0.0 ) return true;
        if ( head <= minHead && flow > 0.0 ) return true;
        return false;
    }

    // Tank-specific methods
    override double getVolume() { return volume; }
    double findVolume(double aHead){
        // ... convert head to water depth

        double depth = aHead - elev;

        // ... tank has a volume curve (in original user units)

        if ( volCurve )
        {
            // ... find slope and intercept of curve segment containing depth

            depth *= ucfLength;
            double slope, intercept;
            volCurve.findSegment(depth, slope, intercept);

            // ... compute volume and convert to ft3

            double ucfArea = ucfLength * ucfLength;
            return (slope * depth + intercept) / (ucfArea * ucfLength);
        }

        // ... tank is cylindrical

        if ( minVolume > 0.0 ) depth = max(aHead - minHead, 0.0);
        return minVolume + area * depth;
    }

    double findHead(double aVolume){
        // ... tank has a volume curve (in original user units)

        if ( volCurve )
        {
            double ucfArea = ucfLength * ucfLength;
            aVolume *= ucfArea * ucfLength;
            return elev + volCurve.getXofY(aVolume) / ucfLength;
        }

        // ... tank is cylindrical

        else
        {
            aVolume = max(0.0, aVolume - minVolume);
            return minHead + aVolume / area;
        }
    }
    override void setFixedGrade(){
        fixedGrade = true;
        //head = findHead(volume)
    }

    void updateVolume(int tstep){
        // ... new volume based on current outflow

        volume += outflow * tstep;

        // ... check if min/max levels reached within an additional 1 second of flow

        double v1 = volume + outflow;
        if ( v1 <= minVolume )
        {
            volume = minVolume;
            head = minHead;
        }
        else if ( v1 >= maxVolume )
        {
            volume = maxVolume;
            head = maxHead;
        }

        // ... find head at new volume

        else head = findHead(volume);
    }

    void   updateArea(){
        // ... tank has a volume curve (in original user units)

        if ( volCurve )
        {
            // ... find slope of curve segment containing depth

            double slope, intercept;
            double depth = head - elev;
            volCurve.findSegment(depth*ucfLength, slope, intercept);

            // ... curve segment slope (dV/dy) is avg. area over interval;
            //     convert to internal units

            area = slope / ucfLength / ucfLength;
        }

        // ... area of cylindrical tank remains constant
    }

    //  Find time to fill (or empty) tank to a given volume
    int timeToVolume(double v){
        // ... make sure target volume is within bounds

        v = max(v, minVolume);
        v = min(v, maxVolume);

        // ... make sure outflow is positive for filling or negative for emptying

        if ( (v-volume) * outflow  <= 0.0 ) return -1;

        // ... required time is volume change over outflow rate

        double t = (v - volume) / outflow;
        return cast(int) (t + 0.5);
    }

    // Properties
    double initHead;               //!< initial water elevation (ft)
    double minHead;                //!< minimum water elevation (ft)
    double maxHead;                //!< maximum water elevation (ft)
    double diameter;               //!< nominal diameter (ft)
    double minVolume;              //!< minimum volume (ft3)
    double bulkCoeff;              //!< water quality reaction coeff. (per day)
    Curve  volCurve;               //!< volume v. water depth curve
    TankMixModel mixingModel;      //!< mixing model used

    double maxVolume;              //!< maximum volume (ft3)
    double volume;                 //!< current volume in tank (ft3)
    double area;                   //!< current surface area of tank (ft2)
    double ucfLength;              //!< units conversion factor for length
    double pastHead;               //!< water elev. in previous time period (ft)
    double pastVolume;             //!< volume in previous time period (ft3)
    double pastOutflow;            //!< outflow in previous time period (cfs)
}