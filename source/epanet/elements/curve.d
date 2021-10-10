/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.curve;

import std.outbuffer;
import std.container.array: Array;

import epanet.elements.element;

//! \class Curve
//! \brief An ordered collection of x,y data pairs.
//!
//! Curves can be used to describe how tank volume varies with height, how
//! pump head or efficiency varies with flow, or how a valve's head loss
//! varies with flow.

//  NOTE: Curve data are stored in the user's original units.
//-----------------------------------------------------------------------------

class Curve: Element
{
  public:

    // Curve type enumeration
    enum {UNKNOWN, PUMP, EFFICIENCY, VOLUME, HEADLOSS}
    alias CurveType = int;

    // Names of curve types
    static string[6] CurveTypeWords = ["", "PUMP", "EFFICIENCY", "VOLUME", "HEADLOSS", null];

    // Constructor/Destructor
    this(string name_){
        super(name_);
        type = UNKNOWN;
    }

    ~this(){
        xData.clear();
        yData.clear();
    }

    // Data provider methods
    void   setType(int curveType){ type = cast(CurveType)curveType; }
    void   addData(double x, double y){ xData.insertBack(x); yData.insertBack(y);}

    // Data retrieval methods
    int size(){ return cast(int)xData.length; }
    alias length = size;

    int    curveType(){ return cast(int)type; }
    double x(int index){ return xData[index]; }
    double y(int index){ return yData[index]; }

    void findSegment(double xseg, ref double slope, ref double intercept){
        int n = cast(int)xData.length;
        int segment = n-1;

        if (n == 1)
        {
            intercept = 0.0;
            if (xData[0] == 0.0) slope = 0.0;
            else slope = yData[0] / xData[0];
        }

        else
        {
            for (int i = 1; i < n; i++)
            {
                if (xseg <= xData[i])
                {
                    segment = i;
                    break;
                }
            }
            slope = (yData[segment] - yData[segment-1]) /
                    (xData[segment] - xData[segment-1]);
            intercept = yData[segment] - slope * xData[segment];
        }
    }

    double getYofX(double x){
        if ( x <= xData[0] ) return yData[0];

        for (size_t i = 1; i < xData.length; i++)
        {
            if ( x <= xData[i] )
            {
                double dx = xData[i] - xData[i-1];
                if ( dx == 0.0 ) return yData[i-1];
                return yData[i-1] + (x - xData[i-1]) / dx * (yData[i] - yData[i-1]);
            }
        }
        return yData[xData.length-1];
    }

    // Assumes Y is increasing with X
    double getXofY(double y){
        if ( y <= yData[0] ) return xData[0];

        for (size_t i = 1; i < yData.length; i++)
        {
            if ( y <= yData[i] )
            {
                double dy = yData[i] - yData[i-1];
                if ( dy == 0.0 ) return xData[i-1];
                return xData[i-1] + (y - yData[i-1]) / dy * (xData[i] - xData[i-1]);
            }
        }
        return xData[yData.length-1];
    }

  private:
    CurveType        type;           //!< curve type
    Array!double     xData;          //!< x-values
    Array!double     yData;          //!< y-values
}