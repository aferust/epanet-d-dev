/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.core.qualengine;

import core.stdc.math;
import std.container.array: Array;
import std.algorithm.comparison;

import epanet.core.network;
import epanet.core.error;
import epanet.core.options;
import epanet.solvers.qualsolver;
import epanet.models.qualmodel;
import epanet.elements.qualsource;
import epanet.elements.tank;
import epanet.elements.link;
import epanet.elements.node;
import epanet.elements.element;
import epanet.utilities.utilities;

//class JuncMixer;
//class TankMixer;

//! \class QualEngine
//! \brief Simulates extended period water quality in a network.
//!
//! The QualEngine class carries out an extended period water quality simulation
//! on a pipe network, calling on its QualSolver object to solve the reaction,
//! transport and mixing equations at each time step.

class QualEngine
{
  public:

    // Constructor/Destructor

    this(){
        engineState = QualEngine.CLOSED;
        network = null;
        qualSolver = null;
        nodeCount = 0;
        linkCount = 0;
        qualTime = 0;
        qualStep = 0;
    }

    ~this(){close();}

    // Public Methods

    void open(Network nw){
        // ... close currently open engine

        if (engineState != QualEngine.CLOSED) close();

        // ... assign network to engine

        network = nw;
        nodeCount = network.count(Element.NODE);
        linkCount = network.count(Element.LINK);

        // ... create a water quality reaction model

        network.createQualModel();

        // ... no quality solver if there's no network quality model

        if ( network.qualModel is null )
        {
            qualSolver = null;
            return;
        }

        // ... create a water quality solver

        qualSolver = QualSolver.factory("LTD", network);
        if (!qualSolver) throw new SystemError(SystemError.QUALITY_SOLVER_NOT_OPENED);

        // ... create sorted link & flow direction arrays

        try
        {
            sortedLinks.length = linkCount; sortedLinks[] = 0;
            flowDirection.length = linkCount; flowDirection[] = 0;
            
            engineState = QualEngine.OPENED;
        }
        catch (Exception e)
        {
            throw new SystemError(SystemError.QUALITY_SOLVER_NOT_OPENED);
        }
    }

    void init_(){
        if (engineState != QualEngine.OPENED) return;
        
        // ... initialize node concentrations & tank volumes

        foreach (Node node; network.nodes)
        {
            if ( network.qualModel.type == QualModel.TRACE ) node.quality = 0.0;
            else node.quality = node.initQual;
            if ( node.type() == Node.TANK )
            {
                Tank tank = cast(Tank)node;
                tank.volume = tank.findVolume(tank.initHead);
            }
        }

        // ... initialize reaction model and quality solver
        
        qualSolver.init_();
        network.qualModel.init_(network);
        qualStep = cast(int)network.option(Options.QUAL_STEP);
        if ( qualStep <= 0 ) qualStep = 300;
        qualTime = 0;
        engineState = QualEngine.INITIALIZED;
    }

    void solve(int tstep){
        // ... check that engine has been initialized

        if ( engineState != QualEngine.INITIALIZED ) return;
        if ( tstep == 0 ) return;

    // ... topologically sort the links if flow direction has changed

        if ( qualTime == 0 ) sortLinks();
        else if ( flowDirectionsChanged() ) sortLinks();

        // ... determine external source quality

        setSourceQuality();

        // ... propagate water quality through network over a sequence
        //     of water quality time steps

        qualTime += tstep;

        while ( tstep > 0 )
        {
            int qstep = min(qualStep, tstep);
            qualSolver.solve(&sortedLinks[0], qstep);
            tstep -= qstep;
        }
    }

    void close(){
        qualSolver.destroy();
        qualSolver = null;
        sortedLinks.clear();
        flowDirection.clear();
        engineState = QualEngine.CLOSED;
    }

private:

    // Engine state

    enum {CLOSED, OPENED, INITIALIZED} // EngineState
    alias EngineState = int;

    EngineState engineState;

    // Engine components

    Network    network;            //!< network being analyzed
    QualSolver qualSolver;         //!< single time step water quality solver

    // Engine properties

    int         nodeCount;          //!< number of network nodes
    int         linkCount;          //!< number of network links
    int         qualTime;           //!< current simulation time (sec)
    int         qualStep;           //!< hydraulic time step (sec)
    Array!int   sortedLinks;      //!< topologically sorted links
    Array!byte  flowDirection;    //!< direction (+/-) of link flow

    // Simulation sub-tasks

    bool flowDirectionsChanged(){
        bool result = false;
        for (int i = 0; i < linkCount; i++)
        {
            if ( network.link(i).flow * flowDirection[i] < 0 )
            {
                qualSolver.reverseFlow(i);
                result = true;
            }
        }
        return result;
    }

    void setFlowDirections(){
        for (int i = 0; i < linkCount; i++)
        {
            flowDirection[i] = cast(char)Utilities.sign(network.link(i).flow);
        }
    }

    void sortLinks(){
        // ... default sorted order

        setFlowDirections();
        for (int j = 0; j < linkCount; j++) sortedLinks[j] = j;
    }

    void setSourceQuality(){
        import std.math: abs;
        // ... set source strength for each source node

        int sourceCount = 0;
        foreach (Node node; network.nodes)
        {
            if ( node.qualSource )
            {
                node.qualSource.setStrength(node);
                node.qualSource.outflow = 0.0;
                sourceCount++;
            }
        }
        if ( sourceCount == 0 ) return;

        // ... find flow rate leaving each source node

        Node fromNode;
        foreach (Link link; network.links)
        {
            double q = link.flow;
            if ( q >= 0.0 ) fromNode = link.fromNode;
            else            fromNode = link.toNode;
            if ( fromNode.qualSource ) fromNode.qualSource.outflow += abs(q);
        }
    }
}