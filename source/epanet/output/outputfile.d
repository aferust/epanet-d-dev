/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.output.outputfile;

import std.stdio, std.exception, std.file;

import epanet.core.network;
import epanet.core.units;
import epanet.core.constants;
import epanet.core.error;
import epanet.core.options;
import epanet.elements.node;
import epanet.elements.element;
import epanet.elements.link;
import epanet.elements.pipe;
import epanet.elements.pump;
import epanet.elements.valve;
import epanet.elements.qualsource;


enum   IntSize = int.sizeof;
enum   FloatSize = float.sizeof;
enum   NumSysVars = 21;
enum   NumNodeVars = 6;
enum   NumLinkVars = 7;
enum   NumPumpVars = 6;

//! \class OutputFile
//! \brief Manages the writing and reading of analysis results to a binary file.

class OutputFile
{
  public:
     this(){
        fname = "";
        network = null;
        nodeCount = 0;
        linkCount = 0;
        pumpCount = 0;
        timePeriodCount = 0;
        reportStart = 0;
        energyResultsOffset = 0;
        networkResultsOffset = 0;
     }

     ~this(){close();}

    int open(const string fileName, Network nw){
        close();
        try{
            fwriter.open(fileName, "wb");
        } catch (ErrnoException e){
            return FileError.CANNOT_OPEN_OUTPUT_FILE;
        }

        fname = fileName;
        network = nw;
        return 0;
    }

    void close(){
        if(fwriter.isOpen) fwriter.close();
        if(freader.isOpen) freader.close();
        network = null;
    }

    int initWriter(){
        // ... return if output file not previously opened
        if ( !fwriter.isOpen() || !network ) return 0;

        // ... re-open the output file
        fwriter.close();
        freader.close();
        try{
            fwriter.open(fname, "wb");
        } catch (ErrnoException e){
            return FileError.CANNOT_OPEN_OUTPUT_FILE;
        }

        // ... retrieve element counts
        nodeCount = network.count(Element.NODE);
        linkCount = network.count(Element.LINK);
        pumpCount = findPumpCount(network);

        // ... retrieve reporting time steps
        timePeriodCount = 0;
        reportStart = cast(int)network.option(Options.REPORT_START);
        reportStep = cast(int)network.option(Options.REPORT_STEP);

        // ... compute byte offsets for where energy results and network results begin
        energyResultsOffset = NumSysVars * IntSize;
        networkResultsOffset = cast(int)(energyResultsOffset + pumpCount *
                            (IntSize + NumPumpVars * FloatSize) + FloatSize);

        // ... write system info to the output file
        int[NumSysVars] sysBuf;
        sysBuf[0] = MAGICNUMBER;
        sysBuf[1] = VERSION;
        sysBuf[2] = 0;                     // reserved for error code
        sysBuf[3] = 0;                     // reserved for warning flag
        sysBuf[4] = energyResultsOffset;
        sysBuf[5] = networkResultsOffset;
        sysBuf[6] = nodeCount;
        sysBuf[7] = linkCount;
        sysBuf[8] = pumpCount;
        sysBuf[9] = network.option(Options.QUAL_TYPE);
        sysBuf[10] = network.option(Options.TRACE_NODE);
        sysBuf[11] = network.option(Options.UNIT_SYSTEM);
        sysBuf[12] = network.option(Options.FLOW_UNITS);
        sysBuf[13] = network.option(Options.PRESSURE_UNITS);
        sysBuf[14] = network.option(Options.QUAL_UNITS);
        sysBuf[15] = cast(int)network.option(Options.REPORT_STATISTIC);
        sysBuf[16] = reportStart;
        sysBuf[17] = reportStep;
        sysBuf[18] = NumNodeVars;
        sysBuf[19] = NumLinkVars;
        sysBuf[20] = NumPumpVars;
        
        try{
            fwriter.rawWrite(sysBuf[]);
        } catch (ErrnoException e){
            return FileError.CANNOT_WRITE_TO_OUTPUT_FILE;
        }

        // ... position the file to where network results begins
        fwriter.seek(cast(long)networkResultsOffset);
        return 0;
    }

    int writeEnergyResults(double totalHrs, double peakKwatts){
        // ... position output file to start of energy results
        if ( !fwriter.isOpen() || !network ) return 0;
        fwriter.seek(energyResultsOffset);

        // ... adjust total hrs online for single period analysis
        if ( totalHrs == 0.0 ) totalHrs = 24.0;

        // ... scan network links for pumps
        int index = -1;
        foreach (Link link; network.links)
        {
            // ... skip non-pump links
            index++;
            if ( link.type() != Link.PUMP ) continue;
            Pump p = cast(Pump)link;

            // ... percent of time online
            double t = p.pumpEnergy.hrsOnLine;
            pumpResults[0] = cast(float)(t / totalHrs * 100.0);

            // ... avg. percent efficiency
            pumpResults[1] = cast(float)(p.pumpEnergy.efficiency);

            // ... avg. kw-hr per mil. gal (or per cubic meter)
            double cf;
            if ( network.option(Options.UNIT_SYSTEM) == Options.SI )
            {
                cf = 1000.0/LPSperCFS/3600.0;
            }
            else cf = 1.0e6/GPMperCFS/60.0;
            pumpResults[2] = cast(float)(p.pumpEnergy.kwHrsPerCFS * cf);

            // ... avg. kwatts
            pumpResults[3] = cast(float)(p.pumpEnergy.kwHrs);

            // ... peak kwatts
            pumpResults[4] = cast(float)(p.pumpEnergy.maxKwatts);

            // ... total cost per day
            pumpResults[5] = cast(float)(p.pumpEnergy.totalCost * 24.0 / totalHrs);

            // ... write link index and energy results to file
            fwriter.rawWrite((cast(byte*)&index)[0..IntSize]);
            fwriter.rawWrite(pumpResults[]);
        }

        // ... save demand (peaking factor) charge
        float demandCharge = cast(float)(peakKwatts * network.option(Options.PEAKING_CHARGE));
        fwriter.rawWrite((cast(byte*)&demandCharge)[0..FloatSize]);

        // ... save number of periods simulated
        fwriter.seek(2 * IntSize);

        try{
            fwriter.rawWrite((cast(byte*)&timePeriodCount)[0..IntSize]);
        } catch (ErrnoException e){
            return FileError.CANNOT_WRITE_TO_OUTPUT_FILE;
        }

        return 0;
    }

    int writeNetworkResults(){
        if ( !fwriter.isOpen() || !network ) return 0;
        timePeriodCount++;
        try{
            writeNodeResults();
            writeLinkResults();
        } catch (ErrnoException e){
            return FileError.CANNOT_WRITE_TO_OUTPUT_FILE;
        }
        return 0;
    }

    int initReader(){
        fwriter.close();
        freader.close();
        freader.open(fname, "rb+");
        if ( !freader.isOpen() ) return 0;
        return 1;
    }

    void seekEnergyOffset(){
         freader.seek(energyResultsOffset);
    }

    void readEnergyResults(int* pumpIndex){
        byte[IntSize + NumPumpVars * float.sizeof] bytes;
        freader.rawRead(bytes[]);
        *pumpIndex = *cast(int*)bytes[0..IntSize].ptr;
        pumpResults[0..NumPumpVars] = cast(float[])bytes[IntSize .. IntSize + (3 * FloatSize)];
    }

    void readEnergyDemandCharge(float* demandCharge){
        ubyte[FloatSize] bytes;
        freader.rawRead(bytes[]);
        *demandCharge = *cast(float*)bytes.ptr;
    }

    void seekNetworkOffset(){
        freader.seek(networkResultsOffset);
    }

    void readNodeResults(){
        ubyte[NumNodeVars * float.sizeof] bytes;
        freader.rawRead(bytes[]);
        nodeResults[0..NumNodeVars] = cast(float[])bytes[0 .. NumNodeVars * float.sizeof];
    }

    void readLinkResults(){
        ubyte[NumLinkVars * float.sizeof] bytes;
        freader.rawRead(bytes[]);
        linkResults[0..NumLinkVars] = cast(float[])bytes[0 .. NumLinkVars * float.sizeof];
    }

    void skipNodeResults(){

        freader.seek(nodeCount*nodeResults.sizeof, SEEK_CUR);
    }

    void skipLinkResults(){
        freader.seek(linkCount*linkResults.sizeof, SEEK_CUR);
    }

    //friend ReportWriter;
    float[NumPumpVars]         pumpResults; //!< array of pump results
    int           timePeriodCount;          //!< number of time periods written
    int           pumpCount;                //!< number of pump links
    float[NumNodeVars]         nodeResults; //!< array of node results
    float[NumLinkVars]         linkResults; //!< array of link results
    int           reportStep;               //!< time between reporting periods (sec)
    int           reportStart;              //!< time when reporting starts (sec)
    
  private:
    string        fname;                    //!< name of binary output file
    File          fwriter;                  //!< output file stream.
    File          freader;                  //!< file input stream
    Network      network;                  //!< associated network
    int           nodeCount;                //!< number of network nodes
    int           linkCount;                //!< number of network links
    
    int           energyResultsOffset;      //!< offset for pump energy results
    int           networkResultsOffset;     //!< offset for extended period results
    
    
    void writeNodeResults(){
        //if ( fwriter.fail() ) return;

        // ... units conversion factors
        double lcf = network.ucf(Units.LENGTH);
        double pcf = network.ucf(Units.PRESSURE);
        double qcf = network.ucf(Units.FLOW);
        double ccf = network.ucf(Units.CONCEN);
        double outflow;
        double quality;

        // ... results for each node
        foreach (Node node; network.nodes)
        {
            // ... head, pressure, & actual demand
            nodeResults[0] = cast(float)(node.head*lcf);
            nodeResults[1] = cast(float)((node.head - node.elev)*pcf);
            nodeResults[2] = cast(float)(node.actualDemand*qcf);

            // ... demand deficit
            nodeResults[3] =
                cast(float)((node.fullDemand - node.actualDemand)*qcf);

            // ... total external outflow (reverse sign for tanks & reservoirs)
            outflow = node.outflow;
            if ( node.type() != Node.JUNCTION ) outflow = -outflow;
            nodeResults[4] = cast(float)(outflow*qcf);

            // ... use source-ammended quality for WQ source nodes
            if ( node.qualSource ) quality = node.qualSource.quality;
            else                    quality = node.quality;
            nodeResults[5] = cast(float)(quality*ccf);

            fwriter.rawWrite(nodeResults[]);
        }
    }

    void writeLinkResults(){
        //if ( fwriter.fail() ) return;

        // ... units conversion factors
        double lcf = network.ucf(Units.LENGTH);
        double qcf = network.ucf(Units.FLOW);
        double hloss;

        // ... results for each link
        foreach (Link link; network.links)
        {
            linkResults[0] = cast(float)(link.flow*qcf);                    //flow
            linkResults[1] = cast(float)(link.leakage*qcf);                 //leakage
            linkResults[2] = cast(float)(link.getVelocity()*lcf);           //velocity
            hloss = link.getUnitHeadLoss();
            if (link.type() != Link.PIPE ) hloss *= lcf;
            linkResults[3] = cast(float)(hloss);                             //head loss
            linkResults[4] = cast(float)link.status;                        //status
            linkResults[5] = cast(float)link.getSetting(network);           //setting
            linkResults[6] = cast(float)(link.quality*FT3perL);             //quality

            fwriter.rawWrite(linkResults[]);
        }
    }
}

int findPumpCount(Network nw)
{
    int count = 0;
    foreach (Link link; nw.links)
    {
        if ( link.type() == Link.PUMP ) count++;
    }
    return count;
}