/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.core.project;

import std.outbuffer;
import std.stdio, std.string, std.typecons;

import epanet.utilities.utilities;
import epanet.elements.element;
import epanet.core.network;
import epanet.core.options;
import epanet.core.error;
import epanet.core.diagnostics;
import epanet.core.hydengine;
import epanet.core.qualengine;
import epanet.output.outputfile;
import epanet.output.projectwriter;
import epanet.input.inputparser;
import epanet.input.inputreader;
import epanet.output.reportwriter;

class Project
{
    public:

    this(){
        inpFileName= "";
        outFileName = "";
        tmpFileName = "";
        rptFileName = "";
        networkEmpty = true;
    	hydEngineOpened = false;
        qualEngineOpened = false;
        outputFileOpened = false;
        solverInitialized = false;
        runQuality = false;

        network = new Network();
        
        qualEngine = new QualEngine();
        hydEngine = new HydEngine();
        outputFile = new OutputFile();
        
        Utilities.getTmpFileName(tmpFileName);
    }

    ~this(){
        closeReport();
        
        outputFile.close();

        hydEngine.destroy();
        qualEngine.destroy();
        outputFile.destroy();

        remove(tmpFileName.toStringz);
    }

    int load(string fname){
        try
        {
            // ... clear any current project
            clear();
            
            // ... check for duplicate file names
            string s = fname;
            if ( s.length == rptFileName.length && Utilities.match(s, rptFileName) )
            {
                throw new FileError(FileError.DUPLICATE_FILE_NAMES);
            }
            if ( s.length == outFileName.length && Utilities.match(s, outFileName) )
            {
                throw new FileError(FileError.DUPLICATE_FILE_NAMES);
            }
            
            // ... save name of input file
            inpFileName = fname;
            
            // ... use an InputReader to read project data from the input file
            auto inputReader = scoped!InputReader(); 
            
            inputReader.readFile(fname, network);
            
            networkEmpty = false;
            runQuality = network.option(Options.QUAL_TYPE) != Options.NOQUAL;
            
            // ... convert all network data to internal units
            network.convertUnits();
            network.options.adjustOptions();

			return 0;
        }
        catch (ENerror e)
        {
	        writeMsg(e.msg);
            return e.code;
    	}
    }

    int save(string fname){
        try
        {
            if ( networkEmpty ) return 0;
            auto projectWriter = scoped!ProjectWriter();
            projectWriter.writeFile(fname, network);
            return 0;
        }
        catch (ENerror e)
        {
            writeMsg(e.msg);
            return e.code;
        }
    }
    void clear(){
        if(hydEngine) hydEngine.close(); 
        hydEngineOpened = false;

        if(qualEngine) qualEngine.close();
        qualEngineOpened = false;

        if(network) network.clear(); 
        networkEmpty = true;

        solverInitialized = false;
        inpFileName = "";
        
    }

    int initSolver(bool initFlows){
        try
        {
            if ( networkEmpty ) return 0;
            solverInitialized = false;
            Diagnostics diagnostics = Diagnostics();
            diagnostics.validateNetwork(network);
            
            // ... open & initialize the hydraulic engine
            if ( !hydEngineOpened )
            {
                initFlows = true;
                hydEngine.open(network);
                hydEngineOpened = true;
            }
            hydEngine.init_(initFlows);

            // ... open and initialize the water quality engine
            if ( runQuality == true )
            {
                if ( !qualEngineOpened )
                {
                    qualEngine.open(network);
                    qualEngineOpened = true;
                }
                qualEngine.init_();
            }

            // ... mark solvers as being initialized
            solverInitialized = true;

            // ... initialize the binary output file
            outputFile.initWriter();
            return 0;
        }
        catch (ENerror e)
        {
            debug writefln("%s : %s - %d", e.msg, e.file, e.line);
            writeMsg(e.msg);
            return e.code;
        }
    }
    
    int runSolver(int* t){
        try
        {
            if ( !solverInitialized ) throw new SystemError(SystemError.SOLVER_NOT_INITIALIZED);
            hydEngine.solve(t);  
            if ( outputFileOpened  && *t % network.option(Options.REPORT_STEP) == 0 )
            {
                outputFile.writeNetworkResults();
            }
            return 0;
        }
        catch (ENerror e)
        {
            writeMsg(e.msg);
            return e.code;
        }
    }

    int advanceSolver(int* dt){
        try
        {
            // ... advance to time when new hydraulics need to be computed
            hydEngine.advance(dt);

            // ... if at end of simulation (dt == 0) then finalize results
            if ( *dt == 0 ) finalizeSolver();

            // ... otherwise update water quality over the time step
            else if ( runQuality ) qualEngine.solve(*dt);
            return 0;
        }
        catch (ENerror e)
        {
            writeMsg(e.msg);
            return e.code;
        }
    }

    int openOutput(string fname){
        //... close an already opened output file
        if ( networkEmpty ) return 0;
        outputFile.close();
        outputFileOpened = false;

        // ... save the name of the output file
        outFileName = fname;
        if ( fname.length == 0 ) outFileName = tmpFileName;

        // ... open the file
        try
        {
            outputFile.open(outFileName, network);
            outputFileOpened = true;
            return 0;
        }
        catch (ENerror e)
        {
            writeMsg(e.msg);
            return e.code;
        }
    }

    int saveOutput(){
        if ( !outputFileOpened ) return 0;
        try
        {
            outputFile.writeNetworkResults();
            return 0;
    	}
        catch (ENerror e)
        {
            writeMsg(e.msg);
            return e.code;
        }
    }

    int openReport(string fname){
        
        try
        {
            //... close an already opened report file
            if ( rptFile.isOpen() ) closeReport();

           // ... check that file name is different from input file name
            string s = fname;
            if ( s.length == inpFileName.length && Utilities.match(s, inpFileName) )
            {
                throw new FileError(FileError.DUPLICATE_FILE_NAMES);
            }
            if ( s.length == outFileName.length && Utilities.match(s, outFileName) )
            {
                throw new FileError(FileError.DUPLICATE_FILE_NAMES);
            }

            // ... open the report file
            rptFile.open(fname, "w");
            if ( !rptFile.isOpen() )
            {
                throw new FileError(FileError.CANNOT_OPEN_REPORT_FILE);
            }
            
            auto rw = new ReportWriter(rptFile, network);
            rw.writeHeading();
            return 0;
        }
        catch (ENerror e)
        {
            writeMsg(e.msg);
            return e.code;
        }
        
    }
    
    void  writeSummary(){
        if (!rptFile.isOpen()) return;
        auto reportWriter = scoped!ReportWriter(rptFile, network);
        reportWriter.writeSummary(inpFileName);
    }

    void  writeResults(int t){
        if ( !rptFile.isOpen() ) return;
        auto reportWriter = scoped!ReportWriter(rptFile, network);
        reportWriter.writeResults(t);
    }

    int writeReport(){
        try
        {
            if ( !outputFileOpened )
            {
                throw new FileError(FileError.NO_RESULTS_SAVED_TO_REPORT);
            }

            auto reportWriter = scoped!ReportWriter(rptFile, network);
            reportWriter.writeReport(inpFileName, outputFile);
            
            return 0;
        }
        catch (ENerror e)
        {
            writeMsg(e.msg);
            return e.code;
        }
    }
    
    void  writeMsg( string msg){
        network.msgLog.write(msg);
    }

    void writeMsgLog(ref string out_){
        out_ = network.msgLog.toString;
        //write(out_); // debug
        network.msgLog.clear;
    }
    
    void  writeMsgLog(){
        
        if ( rptFile.isOpen() )
        {
            rptFile.write(network.msgLog.toString);
            network.msgLog.clear();
        }
    }
    Network getNetwork() { return network; }

    package:

    Network        network;        //!< pipe network to be analyzed.
    HydEngine      hydEngine;      //!< hydraulic simulation engine.
    QualEngine     qualEngine;     //!< water quality simulation engine.
    OutputFile     outputFile;     //!< binary output file for saved results.
    string         inpFileName;    //!< name of project's input file.
    string         outFileName;    //!< name of project's binary output file.
    string         tmpFileName;    //!< name of project's temporary binary output file.
    string         rptFileName;    //!< name of project's report file.
    File           rptFile;        //!< reporting file stream.

    // Project status conditions
    bool           networkEmpty;
    bool           hydEngineOpened;
    bool           qualEngineOpened;
    bool           outputFileOpened;
    bool           solverInitialized;
    bool           runQuality;

    void finalizeSolver(){
        if ( !solverInitialized ) return;

        // Save energy usage results to the binary output file.
        if ( outputFileOpened )
        {
            double totalHrs = hydEngine.getElapsedTime() / 3600.0;
            double peakKwatts = hydEngine.getPeakKwatts();
            outputFile.writeEnergyResults(totalHrs, peakKwatts);
        }

        // Write mass balance results for WQ constituent to message log
        if ( runQuality && network.option(Options.REPORT_STATUS) )
        {
            network.qualBalance.writeBalance(network.msgLog);
        }
    }
    
    void closeReport(){
        if ( rptFile.isOpen() ) rptFile.close();
    }
}
