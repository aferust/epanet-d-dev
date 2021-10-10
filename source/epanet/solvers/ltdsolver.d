/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.solvers.ltdsolver;

import core.stdc.math, core.stdc.string;
import std.container.array: Array;
import std.algorithm.comparison;

import epanet.utilities.segpool;
import epanet.core.network;
import epanet.core.qualbalance;
import epanet.core.error;
import epanet.core.options;
import epanet.core.units;
import epanet.models.qualmodel;
import epanet.models.tankmixmodel;
import epanet.elements.node;
import epanet.elements.qualsource;
import epanet.elements.element;
import epanet.elements.junction;
import epanet.elements.tank;
import epanet.elements.link;
import epanet.elements.pipe;
import epanet.solvers.qualsolver;

//! \class LTDSolver
//! \brief A water quality solver based on the Lagrangian Time Driven method.

class LTDSolver : QualSolver
{
  public:

    this(Network nw){
        super(nw);
        nodeCount = network.count(Element.NODE);
        linkCount = network.count(Element.LINK);

        firstSegment.length = linkCount;
        firstSegment[] = null;

        lastSegment.length = linkCount;
        lastSegment[] = null;

        volIn.length = nodeCount;
        volIn[] = 0;
        
        massIn.length = nodeCount;
        massIn[] = 0;
        
        cTol = network.option(Options.QUAL_TOLERANCE) /
            network.ucf(Units.CONCEN);
        tstep = 0.0;

        segPool = new SegPool();
    }
    
    ~this(){
        firstSegment.clear();
        lastSegment.clear();
        segPool.destroy();
    }

    override void init_(){
        // ... add one segment with downstream node quality to each pipe
        segPool.init_();
        for (int k = 0; k < linkCount; k++)
        {
            firstSegment[k] = null;
            lastSegment[k] = null;
            Link link = network.link(k);
            double v = link.getVolume();
            addSegment(k, v, link.toNode.quality);
        }

        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.TANK )
            {
                Tank tank = cast(Tank)node;
                tank.mixingModel.init_(tank, segPool, cTol);
            }
        }
        
        // ... initialize mass balance quantities
        updateLinkQuality();
        network.qualBalance.init_(findStoredMass());
    }

    override void reverseFlow(int k){
        Segment* seg = firstSegment[k];
        firstSegment[k] = lastSegment[k];
        lastSegment[k] = seg;
        Segment* seg1 = null;
        Segment* seg2 = null;
        while ( seg != null )
        {
            seg2 = seg.next;
            seg.next = seg1;
            seg1 = seg;
            seg = seg2;
        }
    }

    override int solve(int* sortedLinks, int timeStep){
        int errCode = 0;
        tstep = timeStep;

        // ... initialize node accumulators
        memset(&volIn[0], 0, nodeCount*double.sizeof);
        memset(&massIn[0], 0, nodeCount*double.sizeof);

    // ... release constituent mass flow from upstream node of each link
        for (int i = 0; i < linkCount; i++) release(sortedLinks[i]);

        // ... react contents of each pipe and tank
        if ( network.qualModel.isReactive() ) react();

        // ... add mass & flow volume from each link to its downstream node
        for (int i = 0; i < linkCount; i++) transport(sortedLinks[i]);

        // ... use accumulated inflow mass and volume at each
        //     node to update its constituent concentration
        updateNodeQuality();

        // ... find the average concentraion within each link
        updateLinkQuality();

        // ... update the mass balance with mass outflows and final storage
        updateMassBalance();
        return errCode;
    }

  private:
	int                    nodeCount;        // number of nodes
	int                    linkCount;        // number of links
	double                 cTol;             // quality tolerance (mass/ft3)
	double                 tstep;            // time step (sec)

	Array!double        volIn;            // volume inflow to each node
	Array!double        massIn;           // mass inflow to each node
	Array!(Segment*)    firstSegment;     // ptr. to first segment in each link
	Array!(Segment*)    lastSegment;      // ptr. to last segment in each link
	SegPool             segPool;          // pool of pipe segment objects

	void react(){
        // ... react contents of each pipe
        for (int i = 0; i < linkCount; i++)
        {
            // ... only pipe links have reactions in them
            Link link = network.link(i);
            if ( link.type() != Link.PIPE ) continue;
            Pipe pipe = cast(Pipe)link;

            // ... react contents of each pipe segment
            network.qualModel.findMassTransCoeff(pipe);
            Segment* seg = firstSegment[i];
            while ( seg )
            {
                double c = seg.c;
                seg.c = network.qualModel.pipeReact(pipe, seg.c, tstep);
                network.qualBalance.updateReacted( (c - seg.c) * seg.v );
                seg = seg.next;
            }
        }

        // ... react contents of each tank
        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.TANK )
            {
                Tank tank = cast(Tank)node;
                double massReacted =
                    tank.mixingModel.react(tank, network.qualModel, tstep);
                network.qualBalance.updateReacted(massReacted);
            }
        }
    }

	void release(int k){
        import std.math: abs;
        // ... find flow volume (v) released
        Link link = network.link(k);
        double q = link.flow;
        if ( q == 0.0 ) return;
        double v = abs(q) * tstep;

        // ... find index (n) & quality (c) of release node
        Node node = link.fromNode;
        if ( q < 0.0 ) node = link.toNode;
        double c = node.quality;
        double c1 = c;

        // ... modify node quality c to include any source input
        if ( node.qualSource && network.qualModel.type == QualModel.CHEM )
        {
            c = node.qualSource.getQuality(node);
            network.qualBalance.updateInflow( (c - c1) * v );
        }

        // ... update mass balance with inflow from reservoirs
        if ( node.type() == Node.RESERVOIR )
        {
            if ( node.outflow < 0.0 )
                network.qualBalance.updateInflow(c1 * (-node.outflow) * tstep);
        }

        // ... reconcile mass balance for mass outflow from an empty tank
    /*
        if ( node.type() == Node.TANK )
        {
            Tank* tank = static_cast<Tank *> (node);
            double vNeeded = v - max(0.0, tank.pastVolume - tank.minVolume);
            if ( vNeeded > 0 )
            {
                network.qualBalance.updateInflow(c * vNeeded);
            }
        }
    */
        // ... case where link has a last (most upstream) segment
        Segment* seg = lastSegment[k];
        if ( seg )
        {
            // ... if node quality close to segment quality
            //     then simply increase segment volume
            if ( abs(seg.c - c) < cTol ) seg.v += v;

            // ... otherwise add a new segment at upstream end of link
            else addSegment(k, v, c);
        }

        // ... link has no segments so add one
        else addSegment(k, v, c);
    }

	void transport(int k){
        import std.math: abs;
        // ... get flow rate (q) and flow volume (v)
        Link link = network.link(k);
        double q = link.flow;
        double v = abs(q) * tstep;

        // ... get index of downstream node
        int j = link.toNode.index;
        if ( q < 0.0 ) j = link.fromNode.index;

        // ... transport flow volume from leading segments into downstream
        //     node, removing segments as their volume is consumed
        while ( v > 0.0 )
        {
            Segment* seg = firstSegment[k];
            if ( !seg ) break;

            // ... volume transported from first segment is
            //     minimum of remaining flow volume & segment volume
            double vSeg = seg.v;
            vSeg = min(vSeg, v);

            // ... if current segment is last segment then transport
            //     remaining volume (to maintain conservation of mass)
            if ( seg == lastSegment[k] ) vSeg = v;

            // ... update volume & mass entering downstream node
            volIn[j] += vSeg;
            massIn[j] += vSeg * seg.c;

            // ... reduce remaining flow volume by amount transported
            v -= vSeg;

            // ... if all of segment's volume was transferred
            if ( v >= 0.0 && vSeg >= seg.v)
            {
                // ... replace this leading segment with the one behind it
                firstSegment[k] = seg.next;
                if ( firstSegment[k] == null ) lastSegment[k] = null;
                segPool.freeSegment(seg);
            }

            // ... otherwise just reduce this segment's volume
            else seg.v -= vSeg;
        }
    }

	void updateNodeQuality(){
        int traceNodeIndex = network.option(Options.TRACE_NODE);
        for (int i = 0; i < nodeCount; i++)
        {
            Node node = network.node(i);

            // ... update mass balance for TRACE quality model
            if ( i == traceNodeIndex )
            {
                network.qualBalance.updateInflow(volIn[i] * node.quality);
            }
            else
            {
                if ( node.type() == Node.JUNCTION )
                {
                    // ... account for dilution from any external negative demand
                    if (node.outflow < 0.0 && node.qualSource is null )
                    {
                        volIn[i] -= node.outflow * tstep;
                    }

                    // ... new concen. is mass inflow / volume inflow
                    if ( volIn[i] > 0.0 ) node.quality = massIn[i] / volIn[i];
                }

                else if ( node.type() == Node.TANK )
                {
                    Tank tank = cast(Tank)node;
                    node.quality = tank.mixingModel.findQuality(
                                    tank.outflow * tstep, volIn[i], massIn[i], segPool);
                }

            }
        }
    }
	void updateLinkQuality(){
        for (int i = 0; i < linkCount; i++)
        {
            Link link = network.link(i);
            double volume = 0.0;
            double mass = 0.0;

            // ... add up volume & mass in each link segment
            Segment* seg = firstSegment[i];
            while ( seg )
            {
                volume += seg.v;
                mass += seg.c * seg.v;
                seg = seg.next;
            }

            // ... average quality is link total mass / link total volume
            if ( volume > 0.0 ) link.quality = mass / volume;

            // ... if there are no volume segments use avg. of end node quality
            else
            {
                link.quality = (link.fromNode.quality +
                                link.toNode.quality) / 2.0;
            }
        }
    }

	double findStoredMass(){
        double totalMass = 0.0;
    foreach (Link link; network.links)
    {
        totalMass += link.quality * link.getVolume();
    }
    foreach (Node node; network.nodes)
    {
        // ... only Tanks store WQ mass
        if ( node.type() == Node.TANK )
        {
  	        Tank tank = cast(Tank)node;
            totalMass += max(0.0, tank.mixingModel.storedMass());
        }
    }
    return totalMass;
    }

	void   updateMassBalance(){
        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.JUNCTION &&  node.outflow > 0.0 )
            {
                double vOut = node.outflow * tstep;
                double vIn = volIn[node.index];
                if ( vIn < vOut ) vOut = max(0.0, vIn);
                network.qualBalance.updateOutflow(node.quality * vOut);
            }
        }
        network.qualBalance.updateStored(findStoredMass());
    }

    void addSegment(int k, double v, double c){
        // ... do nothing if there's no volume to add
        if ( v == 0.0 ) return;

        // ... get an unused volume segment from the segment pool
        Segment* seg = segPool.getSegment(v, c);
        if ( seg == null ) throw new SystemError(SystemError.OUT_OF_MEMORY);

        // ... if the pipe has no segments make this its first segment
        if ( firstSegment[k] == null ) firstSegment[k] = seg;

        // ... add the new segment on to the end of the pipe's segment list
        Segment* lastSeg = lastSegment[k];
        if ( lastSeg ) lastSeg.next = seg;
        lastSegment[k] = seg;
    }

}