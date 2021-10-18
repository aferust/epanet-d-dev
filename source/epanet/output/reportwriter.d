/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Licensed under the terms of the MIT License (see the LICENSE file for details).
 *
 */
module epanet.output.reportwriter;

import core.stdc.math;
import std.exception: assumeUnique;
import std.stdio;
import std.format, std.string;
import std.conv: to;
import std.range;
import std.math: abs;

import epanet.core.network;
import epanet.core.error;
import epanet.core.options;
import epanet.core.units;
import epanet.elements.node;
import epanet.elements.link;
import epanet.output.outputfile;
import epanet.utilities.utilities;

//! \file reportwriter.d
//! \brief Description of the ReportWriter class.

static const string[4] statusTxt = ["CLOSED", "OPEN", "ACTIVE", "CLOSED"];
static const int width = 12;
static const int precis = 3;

class ReportWriter
{
  public:
    this(ref File sout, Network nw){
        this.sout = sout;
        network = nw;
    }

    ~this(){}

    void writeHeading(){
        sout.write("\n  ******************************************************************");
        sout.write("\n  *                           E P A N E T                          *");
        sout.write("\n  *                   Hydraulic and Water Quality                  *");
        sout.write("\n  *                   Analysis for Pipe Networks                   *");
        sout.write("\n  *                         Version 3.0.000                        *");
        sout.write("\n  ******************************************************************\n");
    }

    void writeSummary(string inpFileName){
        if ( network is null ) return;
        network.writeTitle(sout);
        if ( !network.option(Options.REPORT_SUMMARY) ) return;

        sout.write( "\n  Input Data File ............... " ~
            Utilities.getFileName(inpFileName));

        int nJuncs = 0;
        int nResvs = 0;
        int nTanks = 0;
        int nEmitters = 0;
        int nSources = 0;
        foreach (Node node; network.nodes)
        {
            switch (node.type())
            {
            case Node.JUNCTION : nJuncs++; break;
            case Node.RESERVOIR: nResvs++; break;
            case Node.TANK:      nTanks++; break;
            default: break;
            }
            if ( node.hasEmitter() ) nEmitters++;
            if (node.qualSource) nSources++;
        }

        sout.write( "\n  Number of Junctions ........... " ~ format("%d", nJuncs));
        sout.write( "\n  Number of Reservoirs .......... " ~ format("%d", nResvs));
        sout.write( "\n  Number of Tanks ............... " ~ format("%d", nTanks));

        int nPipes = 0;
        int nPumps = 0;
        int nValves = 0;
        foreach (Link link; network.links)
        {
            switch (link.type())
            {
            case Link.PIPE:  nPipes++;  break;
            case Link.PUMP:  nPumps++;  break;
            case Link.VALVE: nValves++; break;
            default: break;
            }
        }

        sout.write( "\n  Number of Pipes ............... " ~ format("%d", nPipes));
        sout.write( "\n  Number of Pumps ............... " ~ format("%d", nPumps));
        sout.write( "\n  Number of Valves .............. " ~ format("%d", nValves));

        sout.write( "\n  Head Loss Model ............... " ~ network.option(Options.HEADLOSS_MODEL).to!string);
        sout.write( "\n  Leakage Model ................. " ~ network.option(Options.LEAKAGE_MODEL).to!string);
        sout.write( "\n  Demand Model .................. " ~ network.option(Options.DEMAND_MODEL).to!string);
        sout.write( "\n  Demand Multiplier ............. " ~ network.option(Options.DEMAND_MULTIPLIER).to!string);
        sout.write( "\n  Number of Emitters ............ " ~ nEmitters.to!string);
        sout.write( "\n  Head Tolerance ................ " ~ network.option(Options.HEAD_TOLERANCE).to!string);
        sout.write( "\n  Flow Tolerance ................ " ~ network.option(Options.FLOW_TOLERANCE).to!string);
        sout.write( "\n  Flow Change Limit ............. " ~ network.option(Options.FLOW_CHANGE_LIMIT).to!string);

        sout.write( "\n  Quality Model ................. " ~ network.option(Options.QUAL_MODEL).to!string);
        if ( network.option(Options.QUAL_TYPE) == Options.TRACE )
            sout.write( " Node " ~ network.option(Options.TRACE_NODE_NAME).to!string);
        if ( network.option(Options.QUAL_TYPE) == Options.CHEM )
            sout.write( "\n  Quality Constituent ........... " ~ network.option(Options.QUAL_NAME).to!string);
        if ( network.option(Options.QUAL_TYPE) != Options.NOQUAL )
            sout.write( "\n  Number of Sources ............. " ~ nSources.to!string);

        sout.write( "\n  Hydraulic Time Step ........... " ~ (network.option(Options.HYD_STEP) / 60).to!string ~ " minutes");
        if ( network.option(Options.QUAL_TYPE) != Options.NOQUAL )
        sout.write( "\n  Quality Time Step ............. " ~ network.option(Options.QUAL_STEP).to!string ~ " seconds");
        sout.write( "\n  Report Time Step .............. " ~ (network.option(Options.REPORT_STEP) / 60).to!string ~ " minutes");
        sout.write( "\n  Total Duration ................ " ~ (network.option(Options.TOTAL_DURATION) / 3600).to!string ~ " hours");
        sout.write( "\n");
    }

    void writeResults(int t){
        if (network is null) return;
        string theTime = Utilities.getTime(t);
        double lcf = network.ucf(Units.LENGTH);
        double pcf = network.ucf(Units.PRESSURE);
        double qcf = network.ucf(Units.FLOW);
        double ccf = network.ucf(Units.CONCEN);
        double outflow;
        if (network.option(Options.REPORT_NODES))
        {
            float[NumNodeVars] nodeResults;
            
            sout.write("\n\n  Node Results at " ~ theTime ~ " hrs\n");
            writeNodeHeader();
            foreach (Node node; network.nodes)
            {
                nodeResults[0] = cast(float)(node.head * lcf);
                nodeResults[1] = cast(float)((node.head - node.elev) * pcf);
                nodeResults[2] = cast(float)(node.actualDemand * qcf);
                nodeResults[3] = cast(float)((node.fullDemand - node.actualDemand) * qcf);
                outflow = node.outflow * qcf;
                if ( node.type() != Node.JUNCTION ) outflow = -outflow;
                nodeResults[4] = cast(float)(outflow);
                nodeResults[5] = cast(float)(node.quality*ccf);
                writeNodeResults(node, nodeResults.ptr);
            }
        }
        if (network.option(Options.REPORT_LINKS))
        {
            float[NumLinkVars] linkResults;
            
            sout.write("\n\n  Link Results at " ~ theTime ~ " hrs\n");
            writeLinkHeader();
            foreach (Link link; network.links)
            {
                linkResults[0] = cast(float)(link.flow * qcf);
                linkResults[1] = cast(float)(link.leakage * qcf);
                linkResults[2] = cast(float)(link.getVelocity() * lcf);
                double uhl = link.getUnitHeadLoss();
                if ( link.type() != Link.PIPE ) uhl *= lcf;
                linkResults[3] = cast(float)uhl;
                linkResults[4] = cast(float)link.status;
                writeLinkResults(link, linkResults.ptr);
            }
        }
    }

    int  writeReport(string inpFileName, OutputFile outFile){
        // ... check if any output results exist
        if ( outFile.timePeriodCount == 0)
        {
            return FileError.NO_RESULTS_SAVED_TO_REPORT;
        }
        if ( !outFile.initReader() ) return FileError.CANNOT_OPEN_OUTPUT_FILE;

        // ... check if a separate report file was named in reporting options
        bool usingRptFile2 = false;
        string rptFileName2 = network.option(Options.RPT_FILE_NAME);
        if ( rptFileName2.length > 0 )
        {
            // ... write report to this file
            sout.open(rptFileName2);
            if (!sout.isOpen()) return FileError.CANNOT_OPEN_REPORT_FILE;
            usingRptFile2 = true;

            // ... write report heading and network summary
            //     (status log is only written to primary report file)
            writeHeading();
            writeSummary(inpFileName);
        }

        // ... otherwise write report to the primary report file
        else
        {
            if ( !sout.isOpen() ) return FileError.CANNOT_WRITE_TO_REPORT_FILE;
            sout.write(network.msgLog.toString());
            network.msgLog.clear();
        }
        writeEnergyResults(outFile);
        writeSavedResults(outFile);

        // ... close the secondary report file if used
        if ( usingRptFile2 ) sout.close();
        return 0;
    }

  private:
    File sout;
    Network network;

    void writeEnergyResults(OutputFile outFile){
        if ( !network.option(Options.REPORT_ENERGY) ) return;
        int nPumps = outFile.pumpCount;
        if ( nPumps == 0 ) return;

        writeEnergyHeader();
        outFile.seekEnergyOffset();

        int pumpIndex;
        float totalCost = 0.0;
        for (int p = 0; p < nPumps; p++)
        {
            outFile.readEnergyResults(&pumpIndex);
            Link link = network.link(pumpIndex);
            writePumpResults(link, outFile.pumpResults.ptr);
            totalCost += outFile.pumpResults[5];
        }

        string line = '-'.repeat(96).array.assumeUnique;
        sout.write("  " ~ line ~ "\n");

        float demandCharge;
        outFile.readEnergyDemandCharge(&demandCharge);
        sout.write(leftJustify("Demand Charge:", 16, ' '));
        sout.write(rightJustify(format("%.2f", demandCharge), 12, ' '));
        
        sout.write(leftJustify("  Total Cost:", 86, ' '));
        
        sout.write(rightJustify(format("%.2f", totalCost + demandCharge), 12, ' '));
    }
    void writeEnergyHeader(){
        string line = '-'.repeat(96).array.assumeUnique;
        
        sout.write("\n\n\n  Energy Usage:\n  " ~ line ~ "\n");

        sout.write(rightJustify(" ", 26, ' '));
        sout.write(rightJustify("% Time", 12, ' '));
        sout.write(rightJustify("Avg. %", 12, ' '));
        sout.write(rightJustify("Kw-hr", 12, ' '));

        sout.write(rightJustify("Avg.", 12, ' '));
        sout.write(rightJustify("Peak", 12, ' '));
        sout.write(rightJustify("Cost\n", 12, ' '));

        sout.write(leftJustify("  Pump", 26, ' '));
        sout.write(rightJustify("Online", 12, ' '));
        sout.write(rightJustify("Effic.", 12, ' '));
        
        string volume;
        if ( network.option(Options.UNIT_SYSTEM) == Options.US ) volume = "Mgal";
        else volume = "m3";

        sout.write(rightJustify(volume, 12, ' '));
        sout.write(rightJustify("Kwatts", 12, ' '));
        sout.write(rightJustify("Kwatts", 12, ' '));
        sout.write(rightJustify("/day\n", 12, ' '));
        
        sout.write("  " ~ line ~ "\n");
    }

    void writePumpResults(Link link, float* x){
        sout.write("  " ~ leftJustify(link.name, 24, ' '));
        
        
        for (int i = 0; i < NumPumpVars; i++) sout.write(rightJustify(format("%.2f", x[i]), 12, ' '));
        sout.write("\n");
    }

    void writeSavedResults(OutputFile outFile){
        int nPeriods = outFile.timePeriodCount;
        int reportStep = outFile.reportStep;
        outFile.seekNetworkOffset();
        int t = outFile.reportStart;
        for (int i = 1; i <= nPeriods; i++)
        {
            string theTime = Utilities.getTime(t);

            if (network.option(Options.REPORT_NODES))
            {
                sout.write("\n\n  Node Results at " ~ theTime ~ " hrs\n");
                writeNodeHeader();
                foreach (Node node; network.nodes)
                {
                    outFile.readNodeResults();
                    writeNodeResults(node, outFile.nodeResults.ptr);
                }
            }
            else outFile.skipNodeResults();

            if (network.option(Options.REPORT_LINKS))
            {
                sout.write("\n\n  Link Results at " ~ theTime ~ " hrs\n");
                writeLinkHeader();
                foreach (Link link; network.links)
                {
                    outFile.readLinkResults();
                    writeLinkResults(link, outFile.linkResults.ptr);
                }
            }
            else outFile.skipLinkResults();

            t += reportStep;
        }
    }
    void writeLinkHeader(){
        string s1 = '-'.repeat(72).array.assumeUnique;
        
        sout.write("  " ~ s1 ~ "\n");
        sout.write(leftJustify(" ", 26, ' '));
        
        sout.write("   Flow Rate     Leakage    Velocity   Head Loss      Status\n");

        sout.write(leftJustify("  Link", 26, ' '));
        
        sout.write(rightJustify( network.getUnits(Units.FLOW), 12, ' '));
        sout.write(rightJustify( network.getUnits(Units.FLOW), 12, ' '));
        sout.write(rightJustify( network.getUnits(Units.VELOCITY), 12, ' '));
        sout.write(rightJustify( network.getUnits(Units.HEADLOSS), 12, ' '));
        sout.write("\n");

        sout.write("  " ~ s1 ~ "\n");
    }

    void writeLinkResults(Link link, float* x){
        sout.write("  ");
        sout.write(leftJustify(link.name, 24, ' '));

        sout.write(rightJustify(format("%.2f", x[0]), 12, ' '));
        sout.write(rightJustify(format("%.2f", x[1]), 12, ' '));
        sout.write(rightJustify(format("%.2f", x[2]), 12, ' '));
        sout.write(rightJustify(format("%.2f", x[3]), 12, ' '));
        sout.write(rightJustify(statusTxt[cast(int)x[4]], 12, ' '));

        if ( link.type() != Link.PIPE )
        {
            sout.write("/" ~ link.typeStr());
        }
        sout.write("\n");
    }

    void writeNodeHeader(){
        bool hasQual = network.option(Options.QUAL_TYPE) != Options.NOQUAL;
        
        string s1 = '-'.repeat(84).array.assumeUnique;
        string s2 = "";
        if ( hasQual ) s2 = "------------";
        sout.write("  " ~ s1 ~ s2 ~ "\n");

        sout.write(leftJustify(" ", 26, ' '));
        sout.write("        Head    Pressure      Demand     Deficit     Outflow");
        if ( hasQual )
        {
            sout.write(rightJustify(network.option(Options.QUAL_NAME), 12, ' '));
        }
        sout.write("\n");

        sout.write(leftJustify("  Node", 26, ' '));
        
        sout.write(rightJustify(network.getUnits(Units.LENGTH), 12, ' '));
        sout.write(rightJustify(network.getUnits(Units.PRESSURE), 12, ' '));
        sout.write(rightJustify(network.getUnits(Units.FLOW), 12, ' '));
        sout.write(rightJustify(network.getUnits(Units.FLOW), 12, ' '));
        sout.write(rightJustify(network.getUnits(Units.FLOW), 12, ' '));
        
        if ( hasQual ) sout.write(rightJustify(network.option(Options.QUAL_UNITS_NAME), 12, ' '));
        sout.write("\n");
        
        sout.write("  " ~ s1 ~ s2 ~ "\n");
    }

    void writeNodeResults(Node node, float* x){
        sout.write("  ");
        sout.write(leftJustify(node.name, 24, ' '));
        
        
        for (int i = 0; i < NumNodeVars-1; i++) sout.write(rightJustify(format("%.2f", x[i]), 12, ' '));
        if ( network.option(Options.QUAL_TYPE) != Options.NOQUAL )
        {
            sout.write(rightJustify(format("%.2f", x[NumNodeVars-1]), 12, ' '));
        }
        sout.write("\n");
    }

    /*
    void writeNumber(float x, int w, int p){

    }
    */
}
