/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.input.curveparser;

import std.container.array;

import epanet.elements.curve;
import epanet.core.error;
import epanet.utilities.utilities;

//! \class CurveParser
//! \brief The CurveParser class is used to parse a line of input data for
//!        curve data (pairs of x,y values).

class CurveParser
{
public:
    this() {}
    ~this() {}

    void parseCurveData(Curve curve, ref Array!string tokenList){
        // Formats are:
        //   curveName curveType
        //   curveName x1 y1 x2 y2 ...

        // ... check for enough tokens

        auto nTokens = tokenList.length;
        if ( nTokens < 2 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string* tokens = &tokenList[0];

        // ... check if second token is curve type keyword

        int curveType = Utilities.findMatch(tokens[1], Curve.CurveTypeWords);
        if (curveType > 0)
        {
            curve.setType(curveType);
            return;
        }

        // ... otherwise read in pairs of x,y values

        double xx;
        double yy;
        int i = 1;
        while ( i < nTokens )
        {
            if ( !Utilities.parseNumber(tokens[i], xx) )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[i]);
            }
            i++;
            if ( i >= nTokens ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
            if ( !Utilities.parseNumber(tokens[i], yy) )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[i]);
            }
            curve.addData(xx, yy);
            i++;
        }
    }
}