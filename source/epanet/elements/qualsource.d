/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.qualsource;

import std.algorithm.comparison;

import epanet.elements.node;
import epanet.elements.pattern;
import epanet.core.constants;


//! \class QualSource
//! \brief Externally applied water quality at a source node.

class QualSource
{
  public:

    enum { // QualSourceType
        CONCEN,            //!< concentration of any external inflow
        MASS,              //!< adds a fixed mass inflow to a node
        FLOWPACED,         //!< boosts a node's concentration by a fixed amount
        SETPOINT           //!< sets the concentration of water leaving a node
    }

    static string[5] SourceTypeWords = ["CONCEN", "MASS", "FLOWPACED", "SETPOINT", null];

    this(){
        type = CONCEN;
        base = 0.0;
        pattern = null;
        strength = 0.0;
        outflow = 0.0;
        quality = 0.0;

    }
    
    ~this(){}

    /// Factory method for adding a new source (or modifying an existing one)
    static bool addSource(Node node, int t, double b, Pattern p){
        if ( node.qualSource is null )
        {
            node.qualSource = new QualSource();
            if ( node.qualSource is null ) return false;
        }
        node.qualSource.type = t;
        node.qualSource.base = b;
        node.qualSource.pattern = p;
        node.qualSource.quality = 0.0;
        node.qualSource.outflow = 0.0;
        return true;
    }

    /// Determines quality concen. that source adds to a node's outflow
    void setStrength(Node node){
        strength = base;
        if ( pattern ) strength *= pattern.currentFactor();
        if ( type == MASS ) strength *= 60.0;         // mass/min . mass/sec
        else                strength /= FT3perL;      // mass/L . mass/ft3
    }

    double getQuality(Node node){
        // ... no source contribution if no flow out of node
        quality = node.quality;
        if ( outflow == 0.0 ) return quality;

        switch (type)
        {
        case CONCEN:
            switch (node.type())
            {
            // ... for junctions, outflow quality is the node's quality plus the
            //     source's quality times the fraction of outflow to the network
            //     contributed by external inflow (i.e., negative demand)
            //     NOTE: qualSource.outflow is flow in links leaving the node,
            //           node.outflow is node's external outflow (demands, etc.)
            case Node.JUNCTION:
                if ( node.outflow < 0.0 )
                {
                    quality += strength * (-node.outflow / outflow);
                }
                break;

            // ... for tanks, the outflow quality is the larger of the
            //     tank's value and the source's value
            case Node.TANK:
                quality = max(quality, strength);
                break;

            // ... for reservoirs, outflow quality equals the source strength
            case Node.RESERVOIR:
                quality = strength;
                break;
            default: break; // assert?
            }
            break;

        case MASS:
            // ... outflow quality is node's quality plus the source's
            //     mass flow rate divided by the node's outflow to the network
            quality += strength / outflow;
            break;

        case SETPOINT:
            // ... outflow quality is larger of node quality and setpoint strength
            quality = max(quality, strength);
            break;

        case FLOWPACED:
            // ... outflow quality is node's quality + source's strength
            quality += strength;
            break;
        default: break; // assert ?
        }
        return quality;
    }

    int         type;        //!< source type
    double      base;        //!< baseline source quality (mass/L or mass/sec)
    Pattern     pattern;     //!< source time pattern
    double      strength;    //!< pattern adjusted source quality (mass/ft3 or mass/sec)
    double      outflow;     //!< flow rate released from node into network (cfs)
    double      quality;     //!< node quality after source is added on (mass/ft3)
}