/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.input.nodeparser;

import std.container.array;

import epanet.core.error;
import epanet.core.network;
import epanet.core.options;
import epanet.utilities.utilities;
import epanet.elements.node;
import epanet.elements.junction;
import epanet.elements.reservoir;
import epanet.elements.tank;
import epanet.elements.demand;
import epanet.elements.pattern;
import epanet.elements.emitter;
import epanet.elements.qualsource;
import epanet.models.tankmixmodel;

//! \class NodeParser
//! \brief The NodeParser class is used to parse lines of input data
//!        for network nodes read from a text file.

class NodeParser
{
  public:
    this() {}
    ~this() {}

    void parseNodeData(S)(auto ref S id, Network nw, ref Array!string tokens){ 
        Node node = nw.node(id);
        if (node is null) throw new InputError(InputError.UNDEFINED_OBJECT, id);
        switch (node.type())
        {
        case Node.JUNCTION:  parseJuncData(cast(Junction)(node), nw, tokens);  break;
        case Node.RESERVOIR: parseResvData(cast(Reservoir)(node), nw, tokens); break;
        case Node.TANK:      parseTankData(cast(Tank)(node), nw, tokens);      break;
        default:              throw new InputError(InputError.UNDEFINED_OBJECT, id);
        }
    }

    void parseDemand(Node node, Network nw, ref Array!string tokens){
        // ... cast Node to Junction
        if ( tokens.length < 2 ) return;
        if ( node.type() != Node.JUNCTION ) return;
        Junction junc = cast(Junction)node;

        // ... declare a demand object and read its parameters
        Demand d = new Demand();
        parseDemandData(d, nw, tokens);

        // ... add demand to junction
        //     (demand d passed by value so a copy is being added to demands list)
        junc.demands.insertBack(d);
    }
    void parseEmitter(Node node, Network nw, ref Array!string tokens){
        // ... cast Node to Junction
        if ( tokens.length < 2 ) return;
        if ( node.type() != Node.JUNCTION ) return;
        Junction junc = cast(Junction)node;

        // ... read emitter's parameters
        double coeff = 0.0;
        double expon = nw.option(Options.EMITTER_EXPONENT);
        Pattern pattern;
        parseEmitterData(nw, tokens, coeff, expon, pattern);

        // ... add an emitter to the junction
        if ( !Emitter.addEmitter(junc, coeff, expon, pattern) )
        {
            throw new InputError(InputError.CANNOT_CREATE_OBJECT, "Node Emitter");
        }
    }

    void parseCoords(Node node, ref Array!string tokenList){
        // Contents of tokenList are:
        // 0 - node ID
        // 1 - x coordinate
        // 2 - y coordinate

        if ( tokenList.length < 3 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string* tokens = &tokenList[0];

        if ( !Utilities.parseNumber(tokens[1], node.xCoord) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[1]);
        }
        if ( !Utilities.parseNumber(tokens[2], node.yCoord) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
        }
    }

    void parseInitQual(Node node, ref Array!string tokenList){
        // Contents of tokenList are:
        // 0 - node ID
        // 1 - initial quality concentration

        if ( tokenList.length < 2 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string* tokens = &tokenList[0];

        double x;
        if ( !Utilities.parseNumber(tokens[1], x) || x < 0.0)
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[1]);
        }
        node.initQual = x;
    }

    void parseQualSource(Node node, Network nw, ref Array!string tokenList){
        // Contents of tokenList are:
        // 0 - node ID
        // 1 - source type keyword
        // 2 - baseline source strength
        // 3 - time pattern ID (optional)

        if ( tokenList.length < 3 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string* tokens = &tokenList[0];

        // ... read source type

        int t = Utilities.findMatch(tokens[1], QualSource.SourceTypeWords);
        if (t < 0) throw new InputError(InputError.INVALID_KEYWORD, tokens[1]);

        // ... read baseline source strength

        double b;
        if ( !Utilities.parseNumber(tokens[2], b) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
        }

        // ... read optional pattern name

        Pattern p;
        if ( tokenList.length > 3 && tokens[3] != "*")
        {
            p = nw.pattern(tokens[3]);
            if (p is null) throw new InputError(InputError.UNDEFINED_OBJECT, tokens[3]);
        }

        // ... add a water quality source to the node

        if ( !QualSource.addSource(node, t, b, p) )
        {
            throw new InputError(InputError.CANNOT_CREATE_OBJECT, "Node Source");
        }
    }

    void parseTankMixing(Node node, ref Array!string tokenList){
        // Contents of tokenList are:
        // 0 - tank ID
        // 1 - name of mixing model option
        // 2 - mixing fraction (for MIX2 model only)

        if ( tokenList.length < 2 ) return;
        string* tokens = &tokenList[0];

        // ... cast Node to Tank

        if ( node.type() != Node.TANK ) return;
        Tank tank = cast(Tank)node;

        // ... read mixing model type

        int i = Utilities.findMatch(tokens[1], TankMixModel.MixingModelWords);
        if ( i < 0 ) throw new InputError(InputError.INVALID_KEYWORD, tokens[1]);
        tank.mixingModel.type = i;

        // ... read mixing fraction for 2-compartment model

        if ( tank.mixingModel.type == TankMixModel.MIX2 )
        {
            if ( tokenList.length < 3 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
            double f;
            if ( !Utilities.parseNumber(tokens[2], f) || f < 0.0 || f > 1.0 )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
            }
            else tank.mixingModel.fracMixed = f;
        }
    }

    void parseTankReact(Node node, ref Array!string tokenList){
        // Contents of tokenList are:
        // 0 - TANK keyword
        // 1 - tank ID
        // 2 - reaction coeff. (1/days)

        if ( tokenList.length < 2 ) return;
        string* tokens = &tokenList[0];

        // ... cast Node to Tank

        if ( node.type() != Node.TANK ) return;
        Tank tank = cast(Tank)node;

        // ... read reaction coefficient in 1/days

        if ( !Utilities.parseNumber(tokens[2], tank.bulkCoeff) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
        }
    }
}

void parseJuncData(Junction junc, Network nw, ref Array!string tokenList)
{
    // Contents of tokenList are:
    // 0 - junction ID
    // 1 - elevation
    // 2 - primary base demand (optional)
    // 3 - ID of primary demand pattern (optional)

    // ... check for enough tokens

    int nTokens = cast(int)tokenList.length;
    if (nTokens < 2) throw new InputError(InputError.TOO_FEW_ITEMS, "");
    string* tokens = &tokenList[0];

    // ... read elevation

    if (!Utilities.parseNumber(tokens[1], junc.elev))
    {
	    throw new InputError(InputError.INVALID_NUMBER, tokens[1]);
    }

    // ... read optional base demand

    if (nTokens > 2)
	if (!Utilities.parseNumber(tokens[2], junc.primaryDemand.baseDemand))
	{
        throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
	}

    // ... read optional demand pattern

    if (nTokens > 3 && tokens[3] != "*")
    {
        junc.primaryDemand.timePattern = nw.pattern(tokens[3]);
        if ( !junc.primaryDemand.timePattern )
        {
            throw new InputError(InputError.UNDEFINED_OBJECT, tokens[3]);
        }
    }
}

void parseResvData(Reservoir resv, Network nw, ref Array!string tokenList)
{
    // Contents of tokenList are:
    // 0 - reservoir ID
    // 1 - water surface elevation
    // 2 - water surface elevation pattern (optional)

    // ... check for enough tokens

    int nTokens = cast(int)tokenList.length;
    if (nTokens < 2) throw new InputError(InputError.TOO_FEW_ITEMS, "");
    string* tokens = &tokenList[0];

    // ... read elevation

    if (!Utilities.parseNumber(tokens[1], resv.elev))
    {
	    throw new InputError(InputError.INVALID_NUMBER, tokens[1]);
    }

    // read optional elevation pattern

    if ( nTokens > 2 && tokens[2] != "*")
    {
        resv.headPattern = nw.pattern(tokens[2]);
        if ( !resv.headPattern )
        {
            throw new InputError(InputError.UNDEFINED_OBJECT, tokens[2]);
        }
    }
}

void parseTankData(Tank tank, Network nw, ref Array!string tokenList)
{
    // Contents of tokenList are:
    // 0 - tank ID
    // 1 - elevation of bottom of tank bowl
    // 2 - initial water depth
    // 3 - minimum water depth
    // 4 - maximum water depth
    // 5 - nominal diameter
    // 6 - volume at minimum water depth
    // 7 - ID of volume v. depth curve (optional)

    // ... check for enough tokens

    int nTokens = cast(int)tokenList.length;
    if (nTokens < 7) throw new InputError(InputError.TOO_FEW_ITEMS, "");
    string* tokens = &tokenList[0];

    // .... read 6 numbers from input stream into buffer x

    double[6] x;
    for (int i = 0; i < 6; i++)
    {
        if (!Utilities.parseNumber(tokens[i+1], x[i]))
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[i+1]);
        }
    }

    // ... extract tank properties from buffer

    tank.elev      = x[0];
    tank.initHead  = tank.elev + x[1];    // convert input water depths to heads
    tank.minHead   = tank.elev + x[2];
    tank.maxHead   = tank.elev + x[3];
    tank.diameter  = x[4];
    tank.minVolume = x[5];

    // ... read optional volume curve

    if (nTokens > 7 && tokens[7] != "*")
    {
        tank.volCurve = nw.curve(tokens[7]);
        if ( !tank.volCurve )
        {
            throw new InputError(InputError.UNDEFINED_OBJECT, tokens[7]);
        }
    }
}

void parseEmitterData(
        Network nw,
        ref Array!string tokenList,
        ref double coeff,
        ref double expon,
        Pattern pattern)
{
    // Contents of tokenList are:
    // 0 - junction ID
    // 1 - flow coefficient
    // 2 - flow exponent (optional)
    // 3 - ID of flow coeff. time pattern (optional)

    int nTokens = cast(int)tokenList.length;
    string* tokens = &tokenList[0];

    // ... read flow coefficient

    if ( !Utilities.parseNumber(tokens[1], coeff) )
    {
        throw new InputError(InputError.INVALID_NUMBER, tokens[1]);
    }

    // ... read pressure exponent if present

    if ( nTokens > 2 )
    {
        if ( !Utilities.parseNumber(tokens[2], expon) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
        }
    }

    // ... read optional time pattern

    if ( nTokens > 3 && tokens[3] != "*" )
    {
        pattern = nw.pattern(tokens[3]);
        if ( !pattern )
        {
            throw new InputError(InputError.UNDEFINED_OBJECT, tokens[3]);
        }
    }
}


void parseDemandData(Demand demand, Network nw, ref Array!string tokenList)
{
    // Contents of tokenList are:
    // 0 - junction ID
    // 1 - base demand
    // 2 - ID of demand pattern (optional)

    int nTokens = cast(int)tokenList.length;
    if ( nTokens < 2 ) return;
    string* tokens = &tokenList[0];

    // ... read base demand

    if ( !Utilities.parseNumber(tokens[1], demand.baseDemand) )
    {
        throw new InputError(InputError.INVALID_NUMBER, tokens[1]);
    }

    // ... read optional demand pattern

    if ( nTokens > 2 && tokens[2] != "*" )
    {
        demand.timePattern = nw.pattern(tokens[2]);
        if ( !demand.timePattern )
        {
            throw new InputError(InputError.UNDEFINED_OBJECT, tokens[2]);
        }
    }
}