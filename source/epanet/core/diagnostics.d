/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.core.diagnostics;

import std.container.array: Array;

import epanet.core.network;
import epanet.elements.element;
import epanet.elements.link;
import epanet.elements.node;
import epanet.elements.valve;
import epanet.core.error;

struct Diagnostics
{
    void validateNetwork(Network nw){
        bool result = true;
        if ( nw.count(Element.NODE) < 2 )
        {
            throw new NetworkError(NetworkError.TOO_FEW_NODES, "");
        }
        
        if ( !hasFixedGradeNodes(nw) )
        {
            throw new NetworkError(NetworkError.NO_FIXED_GRADE_NODES, "");
        }
        
        if ( !hasValidNodes(nw) )      result = false;
        if ( !hasValidLinks(nw) )      result = false;
        if ( !hasValidValves(nw) )     result = false;
        if ( !hasValidCurves(nw) )     result = false;
        if ( !hasConnectedNodes(nw) )  result = false;
        
        if ( result == false )
        {
            throw new InputError(InputError.ERRORS_IN_INPUT_DATA, "");
        }
    }
}

//-----------------------------------------------------------------------------

bool hasFixedGradeNodes(Network nw)
{
    foreach (Node node; nw.nodes )
    {
        if ( node.fixedGrade ) return true;
    }
    return false;
}

//-----------------------------------------------------------------------------

bool hasValidNodes(Network nw)
{
    bool result = true;
    foreach (Node node; nw.nodes )
    {
        try
        {
            node.validate(nw);
        }
        catch (ENerror e)
        {
            nw.msgLog.writef("%s", e.msg);
            result = false;
        }
    }
    return result;
}

//-----------------------------------------------------------------------------

bool hasValidLinks(Network nw)
{
    bool result = true;
    foreach (Link link; nw.links)
    {
        try
        {
            link.validate(nw);
        }
        catch (ENerror e)
        {
            nw.msgLog.writef("%s", e.msg);
            result = false;
        }
    }
    return result;
}

//-----------------------------------------------------------------------------

bool hasValidValves(Network nw)
{
    bool result = true;
    foreach (Link link; nw.links)
    {
        if ( link.type() != Link.VALVE ) continue;
        try
        {
            Valve valve = cast(Valve)link;
            if ( (link.toNode.fixedGrade && valve.valveType == Valve.PRV) ||
                 (link.fromNode.fixedGrade && valve.valveType == Valve.PSV) )
            {
                throw new NetworkError(NetworkError.ILLEGAL_VALVE_CONNECTION,
                                   valve.name);
            }
        }
        catch (ENerror e)
        {
            nw.msgLog.writef("%s", e.msg);
            result = false;
        }

//////////  TO DO: Add checks for valves in series, etc.  ////////////////

    }
    return result;

}

//-----------------------------------------------------------------------------

bool hasValidCurves(Network nw)
{
////////  TO BE ADDED  ////////
    return true;
}

//-----------------------------------------------------------------------------

bool hasConnectedNodes(Network nw)
{
    int nodeCount = nw.count(Element.NODE);

    Array!int marked; marked.length = nodeCount; marked[] = 0;
    
    foreach (Link link; nw.links)
    {
        marked[link.fromNode.index]++;
        marked[link.toNode.index]++;
    }

    int unmarkedCount = 0;
    for (int i = 0; i < nodeCount; i++)
    {
        try
        {
            if ( !marked[i] )
            {
                unmarkedCount++;
                if ( unmarkedCount <= 10 )
                    throw new NetworkError(
                        NetworkError.UNCONNECTED_NODE, nw.node(i).name);
            }
        }
        catch (ENerror e)
        {
            nw.msgLog.writef("%s", e.msg);
        }
    }
    if ( unmarkedCount > 10 )
    {
        nw.msgLog.writef("\n\n NETWORK ERROR 233: no links connected to another %d nodes ",
                   (unmarkedCount - 10));
    }
    return (unmarkedCount == 0);
}