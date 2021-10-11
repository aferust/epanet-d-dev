module app;

import epanet.core.project;
import epanet.core.datamanager;
import epanet.epanet3;

import std.stdio;

void main() {
    //EN_runEpanet("Net2.inp", "out1", "out2");
    
    int err;
    Project p = new Project();
    err = p.openReport("out1");
    err = p.load("Net2.inp");
    
    err = p.openOutput("out2");
    p.writeSummary();
    
    err = p.initSolver(false);

    int t = 0;
    int tstep = 0;
    do
    {

        // ... run solver to compute hydraulics
        err = p.runSolver(&t);
        p.writeMsgLog();

        // ... advance solver to next period in time while solving for water quality
        if ( !err ) err = p.advanceSolver(&tstep);
    } while (tstep > 0 && !err );
    err = p.writeReport();

    p.save("Net2_gen.inp");

}