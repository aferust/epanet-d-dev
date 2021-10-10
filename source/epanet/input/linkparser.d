/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.input.linkparser;

import std.container.array;

import epanet.elements.link;
import epanet.core.network;
import epanet.core.constants;
import epanet.core.error;
import epanet.elements.element;
import epanet.elements.pipe;
import epanet.elements.pump;
import epanet.elements.valve;
import epanet.elements.curve;
import epanet.elements.pumpcurve;
import epanet.utilities.utilities;

//-----------------------------------------------------------------------------
//  Keywords associated with link properties
//-----------------------------------------------------------------------------
enum w_Head    = "HEAD";
enum w_Speed   = "SPEED";
enum w_Power   = "POWER";
enum w_Price   = "PRICE";
enum w_Pattern = "PATTERN";
enum w_Effic   = "EFFIC";
enum w_OPEN    = "OPEN";
enum w_CLOSED  = "CLOSED";
enum w_CV      = "CV";
string[7] valveTypeWords = ["PRV", "PSV", "FCV", "TCV", "PBV", "GPV", null];

//! \class LinkParser
//! \brief The LinkParser class is used to parse lines of input data
//!        for network links read from a text file.

class LinkParser
{
  public:
    this() {}
    ~this() {}

    void parseLinkData(ref string id, Network nw, ref Array!string tokens){
        // ... read end nodes
        Link link = nw.link(id);
        if ( !link ) throw new InputError(InputError.UNDEFINED_OBJECT, id);
        if ( tokens.length < 4 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        
        parseEndNodes(link, nw, tokens);
        
        // ... read link-specific data

        switch (link.type())
        {
        case Link.PIPE: parsePipeData(cast(Pipe)link, tokens);        break;
        case Link.PUMP: parsePumpData(cast(Pump)link, nw, tokens);    break;
        case Link.VALVE: parseValveData(cast(Valve)link, nw, tokens); break;
        default: throw new InputError(InputError.UNDEFINED_OBJECT, id);
        }
    }
    
    void parseStatus(Link link, ref Array!string tokenList){
        // Contents of tokenList are:
        // 0 - link ID
        // 1 - OPEN/CLOSED keyword or numerical setting

        if ( tokenList.length < 2 ) return;
        string* tokens = &tokenList[0];
        double setting;

        // ... check for OPEN/CLOSED keywords

        if (Utilities.match(tokens[1], "OPEN"))
        {
            link.setInitStatus(Link.LINK_OPEN);
        }
        else if (Utilities.match(tokens[1], "CLOSED"))
        {
            link.setInitStatus(Link.LINK_CLOSED);
        }

        // ... check for numerical setting value

        else if (Utilities.parseNumber(tokens[1], setting))
        {
            link.setInitSetting(setting);
        }
        else throw new InputError(InputError.INVALID_KEYWORD, tokens[1]);
    }

    void parseLeakage(Link link, ref Array!string tokenList){
        // Contents of tokenList are:
        // 0 - link ID
        // 1 - first leakage parameter
        // 2 - second leakage parameter
        // Parameters defined by user's choice of leakage model

        // ... cast link to a pipe (only pipe links have leakage parameters)

        if ( link.type() != Link.PIPE ) return;
        Pipe pipe = cast(Pipe)link;

        // ... parse leakage parameters

        string* tokens = &tokenList[0];
        if ( !Utilities.parseNumber(tokens[1], pipe.leakCoeff1) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[1]);
        }
        if ( !Utilities.parseNumber(tokens[2], pipe.leakCoeff2) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
        }
    }

    void parseEnergy(Link link, Network network, ref Array!string tokenList){
        // Contents of tokenList are:
        // 0 - PUMP keyword
        // 1 - pump ID
        // 2 - PRICE/PATTERN/EFFIC keyword
        // 3 - price value or ID of pattern or efficiency curve

        // ... cast link to a pump

        if ( link.type() != Link.PUMP ) return;
        Pump pump = cast(Pump)link;

        // ... read keyword from input stream

        if ( tokenList.length < 4) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string* tokens = &tokenList[0];
        string keyword = tokens[2];

        // ... read energy cost per Kwh

        if ( Utilities.match(keyword, w_Price) )
        {
            if ( !Utilities.parseNumber(tokens[3], pump.costPerKwh) )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[3]);
            }
        }

        // ... read name of energy cost time pattern

        else if ( Utilities.match(keyword, w_Pattern) )
        {
            pump.costPattern = network.pattern(tokens[3]);
            if ( !pump.costPattern )
            {
                throw new InputError(InputError.UNDEFINED_OBJECT, tokens[3]);
            }
        }

        // ... read name of pump efficiency curve

        else if ( Utilities.match(keyword, w_Effic) )
        {
            pump.efficCurve = network.curve(tokens[3]);
            if ( !pump.efficCurve )
            {
                throw new InputError(InputError.UNDEFINED_OBJECT, tokens[3]);
            }
        }

        else throw new InputError(InputError.INVALID_KEYWORD, keyword);
    }

    void parseReaction(Link link, int type, ref Array!string tokenList){
        // Contents of tokenList are:
        // 0 - BULK/WALL keyword
        // 1 - link ID
        // 2 - reaction coeff. (1/days)

        // ... cast link to a pipe (only pipe links have reactions)

        if ( link.type() != Link.PIPE ) return;
        Pipe pipe = cast(Pipe)link;

        // ... read reaction coeff.

        double x;
        string* tokens = &tokenList[0];
        if ( !Utilities.parseNumber(tokens[2], x) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[1]);
        }

        // ... save reaction coeff.

        if      (type == Link.BULK) pipe.bulkCoeff = x;
        else if (type == Link.WALL) pipe.wallCoeff = x;
    }
}

//-----------------------------------------------------------------------------

void parseEndNodes(Link link, Network nw, ref Array!string tokenList)
{
    // Contents of tokenList are:
    // 0 - link ID
    // 1 - start node ID
    // 2 - end node ID
    // remaining tokens are parsed by other functions

    string* tokens = &tokenList[0];

    // ... read index of link's start node
    
    link.fromNode = nw.node(tokens[1]);
    if ( link.fromNode is null ) throw new InputError(InputError.UNDEFINED_OBJECT, tokens[1]);

    // ... read end node

    link.toNode = nw.node(tokens[2]);
    if ( link.toNode is null ) throw new InputError(InputError.UNDEFINED_OBJECT, tokens[2]);
}

//-----------------------------------------------------------------------------

void parsePipeData(Pipe pipe, ref Array!string tokenList)
{
    // Contents of tokenList are:
    // 0 - pipe ID
    // 1 - start node ID
    // 2 - end node ID
    // 3 - length
    // 4 - diameter
    // 5 - roughness
    // 6 - minor loss coeff. (optional)
    // 7 - initial status (optional)

    int nTokens = cast(int)tokenList.length;
    if ( nTokens < 6 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
    string* tokens = &tokenList[0];

    // ... read length, diameter, and roughness

    double[3] x;
    for (int i = 0; i < 3; i++)
    {
        if ( !Utilities.parseNumber(tokens[3+i], x[i]) || x[i] <= 0.0 )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[3+i]);
        }
    }
    pipe.length    = x[0];
    pipe.diameter  = x[1];
    pipe.roughness = x[2];

    // ... read optional minor loss coeff.

    if ( nTokens > 6 )
    {
        if ( !Utilities.parseNumber(tokens[6], pipe.lossCoeff) ||
             pipe.lossCoeff < 0.0)
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[6]);
        }
    }

    // ... read optional initial status

    if ( nTokens > 7 && tokens[7] != "*" )
    {
        string s = tokens[7];
        if      (Utilities.match(s, w_OPEN))   pipe.initStatus = Link.LINK_OPEN;
        else if (Utilities.match(s, w_CLOSED)) pipe.initStatus = Link.LINK_CLOSED;
        else if (Utilities.match(s, w_CV))     pipe.hasCheckValve = true;
        else throw new InputError(InputError.INVALID_KEYWORD, s);
    }
}

//-----------------------------------------------------------------------------

void parsePumpData(Pump pump, Network nw, ref Array!string tokenList)
{
    // Contents of tokenList are:
    // 0 - pump ID
    // 1 - upstream node ID
    // 2 - downstream node ID
    // remaining tokens are property name/value pairs

    // ... start reading keyword/value pair tokens
    
    auto nTokens = tokenList.length;
    string* tokens = &tokenList[0];
    int index = 3;
    string keyword;

    while ( index < nTokens )
    {
	// ... check that the value token exists

        keyword = tokens[index];
        index++;
        if ( index >= nTokens ) throw new InputError(InputError.TOO_FEW_ITEMS, "");

        // ... horsepower property
        
        if ( Utilities.match(keyword, w_Power) )
        {
            if ( !Utilities.parseNumber(tokens[index], pump.pumpCurve.horsepower) )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[index]);
            }
        }

        // ... head curve property

        else if (Utilities.match(keyword, w_Head))
        {
            Curve pumpCurve = nw.curve(tokens[index]);
            if ( !pumpCurve ) throw new InputError(InputError.UNDEFINED_OBJECT, tokens[index]);
            pump.pumpCurve.curve = pumpCurve;
        }

        // ... speed setting property

        else if (Utilities.match(keyword, w_Speed))
        {
            if ( !Utilities.parseNumber(tokens[index], pump.speed)
                || pump.speed < 0.0 )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[index]);
            }
        }

        // ... speed pattern property

        else if (Utilities.match(keyword, w_Pattern))
        {
            pump.speedPattern = nw.pattern(tokens[index]);
            if ( !pump.speedPattern )
            {
                throw new InputError(InputError.UNDEFINED_OBJECT, tokens[index]);
            }
        }

        else throw new InputError(InputError.INVALID_KEYWORD, keyword);
        index++;
    }
}

//-----------------------------------------------------------------------------

void parseValveData(Valve valve, Network network, ref Array!string tokenList)
{
    // Contents of tokenList are:
    // 0 - valve ID
    // 1 - upstream node ID
    // 2 - downstream node ID
    // 3 - diameter
    // 4 - valve type
    // 5 - valve setting
    // 6 - minor loss coeff. (optional)

    // ... check for enough input tokens

    if ( tokenList.length < 6 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
    string* tokens = &tokenList[0];

    // ... read diameter

    if ( !Utilities.parseNumber(tokens[3], valve.diameter)||
         valve.diameter <= 0.0 )
    {
        throw new InputError(InputError.INVALID_NUMBER, tokens[3]);
    }

    // ... read valve type

    int vType = Utilities.findMatch(tokens[4], valveTypeWords);
    if ( vType < 0 ) throw new InputError(InputError.INVALID_KEYWORD, tokens[4]);
    valve.valveType = cast(Valve.ValveType)vType;

    // ... read index of head loss curve for General Purpose Valve

    if ( valve.valveType == Valve.GPV )
    {
        int c = network.indexOf(Element.CURVE, tokens[5]);
        if ( c < 0 ) throw new InputError(InputError.UNDEFINED_OBJECT, tokens[5]);
        valve.initSetting = c;
    }

    // ... read numerical setting for other types of valves
    else
    {
        if ( !Utilities.parseNumber(tokens[5], valve.initSetting) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[5]);
        }
    }

    // ... read optional minor loss coeff.

    if ( tokenList.length > 6 )
    {
        if ( !Utilities.parseNumber(tokens[6], valve.lossCoeff) ||
             valve.lossCoeff < 0.0 )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[6]);
        }
    }
}