/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.core.epanet3;

import std.exception;
import std.typecons;
import std.stdio;
import std.string, std.format, std.conv: to;
import core.stdc.time;

import epanet.core.project;
import epanet.core.datamanager;
import epanet.core.constants;
import epanet.core.error;
import epanet.utilities.utilities;



alias EN_Project = void*;

DataManager dm;

private {
    import core.runtime;
    import core.atomic;

    shared size_t initCount;

    void initRT(){
        version(Executable){}
        else {
            if(!atomicLoad!(MemoryOrder.acq)(initCount)){
                Runtime.initialize();
                atomicOp!"+="(initCount, 1);
            }
        }
    }

    void termRT(){
        version(Executable){}
        else {
            if(atomicLoad!(MemoryOrder.acq)(initCount) > 0){
                Runtime.terminate();
                atomicOp!"-="(initCount, 1);
            }
        }
    }
}

extern (C):

int EN_getVersion(int* enversion)
{
    *enversion = VERSION;
    return 0;
}

//-----------------------------------------------------------------------------

int EN_runEpanet(const(char)* inpFile, const(char)* rptFile, const(char)* outFile)
{
    initRT();
    scope(exit) termRT();

    "\n... EPANET Version 3.0\n".write;

    // ... declare a Project variable and an error indicator
    Project p = new Project();
    int err = 0;
    
    // ... initialize execution time clock
    clock_t start_t = clock();

    for (;;)
    {
        // ... open the command line files and load network data
        err = p.openReport(rptFile.to!string);
        if ( err != 0 ) break;
        "\n    Reading input file ...".write;
        err = p.load(inpFile.to!string);
        if ( err != 0 ) break;
        err = p.openOutput(outFile.to!string);
        if ( err != 0 ) break;
        p.writeSummary();

        // ... initialize the solver
        "\n    Initializing solver ...".write;
        err = p.initSolver(false);
        if ( err != 0 ) break;
        "\n    ".write;

        // ... step through each time period
        int t = 0;
        int tstep = 0;
        do
        {
            ("\r    Solving network at " ~
                   Utilities.getTime(t+tstep) ~ " hrs ...        ").write;

            // ... run solver to compute hydraulics
            err = p.runSolver(&t);
            p.writeMsgLog();

            // ... advance solver to next period in time while solving for water quality
            if ( !err ) err = p.advanceSolver(&tstep);
        } while (tstep > 0 && !err );
        break;
    }
    
    // ... simulation was successful
    if ( !err )
    {
        // ... report execution time
        clock_t end_t = clock();
        double cpu_t = (cast(double) (end_t - start_t)) / CLOCKS_PER_SEC;
        string ss = "\n  Simulation completed in ";
        p.writeMsg(ss); 
        ss = "";
        if ( cpu_t < 0.001 ) ss = "< 0.001 sec.";
        else ss = format("%.3f sec.", cpu_t);
        p.writeMsg(ss);

        // ... report simulation results
        "\n    Writing report ...                           ".write;
        err = p.writeReport();
        "\n    Simulation completed.                         \n".write;
        ("\n... EPANET completed in " ~ ss ~ "\n").write;
    }

    if ( err )
    {
        p.writeMsgLog();
         "\n\n    There were errors. See report file for details.\n".write;
        return err;
    }

    p.destroy();

    return 0;
}

//-----------------------------------------------------------------------------

EN_Project EN_createProject()
{
    initRT();
    Project p = new Project();
    return cast(EN_Project *)p;
}

//-----------------------------------------------------------------------------

int EN_deleteProject(EN_Project p)
{   
    scope(exit) termRT();
    (cast(Project)p).destroy();
    return 0;
}

//-----------------------------------------------------------------------------

int EN_loadProject(const char* fname, EN_Project p)
{
    return (cast(Project)p).load(fname.to!string);
}

//-----------------------------------------------------------------------------

int EN_saveProject(const char* fname, EN_Project p)
{
    return (cast(Project)p).save(fname.to!string);
}

//-----------------------------------------------------------------------------

int EN_clearProject(EN_Project p)
{
    (cast(Project)p).clear();
    return 0;
}

//-----------------------------------------------------------------------------

////////////////////////////////////////////////////////////////
//  NOT SURE IF THIS METHOD WORKS CORRECTLY -- NEEDS TESTING  //
////////////////////////////////////////////////////////////////
int EN_cloneProject(EN_Project pClone, EN_Project pSource)
{
    if ( pSource is null || pClone is null ) return 102;
    int err = 0;
    string tmpFile;
    if ( Utilities.getTmpFileName(tmpFile) )
    {
        try
        {
            EN_saveProject(tmpFile.toStringz, pSource);
            EN_loadProject(tmpFile.toStringz, pClone);
        }
        catch (ENerror e)
        {
	        (cast(Project)pSource).writeMsg(e.msg);
            err = e.code;
  	    }
        catch (Exception e)
        {
            err = 208; //Unspecified error
        }
        if ( err > 0 )
        {
            EN_clearProject(pClone);
        }
        remove(tmpFile.toStringz);
        return err;
    }
    return 208;
}

//-----------------------------------------------------------------------------

int EN_runProject(EN_Project p)    // <<=============  TO BE COMPLETED
{
    return 0;
}

//-----------------------------------------------------------------------------

int EN_initSolver(int initFlows, EN_Project p)
{
    return (cast(Project)p).initSolver(cast(bool)initFlows);
}

//-----------------------------------------------------------------------------

int EN_runSolver(int* t, EN_Project p)
{
    return (cast(Project)p).runSolver(t);
}

//-----------------------------------------------------------------------------

int EN_advanceSolver(int *dt, EN_Project p)
{
    return (cast(Project)p).advanceSolver(dt);
}

//-----------------------------------------------------------------------------

int EN_openOutputFile(const char* fname, EN_Project p)
{
    return (cast(Project)p).openOutput(fname.to!string);
}

//-----------------------------------------------------------------------------

int EN_saveOutput(EN_Project p)
{
    return (cast(Project)p).saveOutput();
}

//-----------------------------------------------------------------------------

int EN_openReportFile(const char* fname, EN_Project p)
{
    return (cast(Project)p).openReport(fname.to!string);
}

//-----------------------------------------------------------------------------

int EN_writeReport(EN_Project p)
{
    return (cast(Project)p).writeReport();
}

//-----------------------------------------------------------------------------

int EN_writeSummary(EN_Project p)
{
    (cast(Project)p).writeSummary();
    return 0;
}

//-----------------------------------------------------------------------------

int EN_writeResults(int t, EN_Project p)
{
    (cast(Project)p).writeResults(t);
    return 0;
}

//-----------------------------------------------------------------------------

int EN_writeMsgLog(EN_Project p)
{
    (cast(Project)p).writeMsgLog();
    return 0;
}

//-----------------------------------------------------------------------------

int EN_getCount(int element, int* result, EN_Project p)
{
    return dm.getCount(element, result, (cast(Project)p).getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getNodeIndex(char* name, int* index, EN_Project p)
{
    return dm.getNodeIndex(name.to!string, index, (cast(Project)p).getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getNodeId(int index, char* id, EN_Project p)
{
    return dm.getNodeId(index, id.to!string, (cast(Project)p).getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getNodeType(int index, int* type, EN_Project p)
{
    return dm.getNodeType(index, type, (cast(Project)p).getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getNodeValue(int index, int param, double* value, EN_Project p)
{
    return dm.getNodeValue(index, param, value, (cast(Project)p).getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkIndex(char* name, int* index, EN_Project p)
{
    return dm.getLinkIndex(name.to!string, index, (cast(Project)p).getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkId(int index, char* id, EN_Project p)
{
    return dm.getLinkId(index, id.to!string, (cast(Project)p).getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkType(int index, int* type, EN_Project p)
{
    return dm.getLinkType(index, type, (cast(Project)p).getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkNodes(int index, int* fromNode, int* toNode, EN_Project p)
{
    return dm.getLinkNodes(index, fromNode, toNode,
                                     (cast(Project)p).getNetwork());
}

//-----------------------------------------------------------------------------

int EN_getLinkValue(int index, int param, double* value, EN_Project p)
{
   return dm.getLinkValue(index, param, value, (cast(Project)p).getNetwork());
}

version (Windows){
    version (DynamicLibrary){
        import core.sys.windows.dll;
        
        mixin SimpleDllMain;
    }
}

/*
    with the below mixin, the export definitions are created for the dynamic library
    in compile time.
*/
version (DynamicLibrary){
    enum FunNames = [
        "EN_getVersion",
        "EN_runEpanet",
        "EN_createProject",
        "EN_deleteProject",
        "EN_loadProject",
        "EN_saveProject",
        "EN_clearProject",
        "EN_cloneProject",
        "EN_runProject",
        "EN_initSolver",
        "EN_runSolver",
        "EN_advanceSolver",
        "EN_openOutputFile",
        "EN_saveOutput",
        "EN_openReportFile",
        "EN_writeReport",
        "EN_writeSummary",
        "EN_writeResults",
        "EN_writeMsgLog",
        "EN_getCount",
        "EN_getNodeIndex",
        "EN_getNodeId",
        "EN_getNodeType",
        "EN_getNodeValue",
        "EN_getLinkIndex",
        "EN_getLinkId",
        "EN_getLinkType",
        "EN_getLinkNodes",
        "EN_getLinkValue"
    ];

    mixin template ExportDyLib()
    {
        import std.algorithm.searching;
        static foreach(funName; __traits(allMembers, epanet.core.epanet3)){
            static if(countUntil(FunNames, funName) != -1){
                mixin(
                "export typeof(&" ~ funName ~ ") " ~ "EN" ~ funName.split('_')[1] ~ " = &" ~ funName ~ ";"
            );
            //pragma(msg, "export typeof(&" ~ funName ~ ") " ~ "EN" ~ funName.split('_')[1] ~ " = &" ~ funName ~ ";");
            }
        }
    }
    
    extern (C):
    mixin ExportDyLib;

}