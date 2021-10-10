/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.core.hydengine;

import std.outbuffer;
import std.algorithm.comparison;
import std.container.array: Array;

import epanet.core.network;
import epanet.core.error;
import epanet.core.options;
import epanet.solvers.hydsolver;
import epanet.solvers.matrixsolver;
import epanet.elements.element;
import epanet.elements.link;
import epanet.elements.node;
import epanet.elements.tank;
import epanet.elements.pattern;
import epanet.elements.control;
import epanet.utilities.utilities;

//static const string s_Balancing  = " Balancing the network:";
enum s_Unbalanced =
    "  WARNING - network is unbalanced. Flows and pressures may not be correct.";
enum s_UnbalancedHalted =
    "  Network is unbalanced. Simulation halted by user.";
enum s_IllConditioned =
    "  Network is numerically ill-conditioned. Simulation halted.";
enum s_Balanced   = "  Network balanced in ";
enum s_Trials     = " trials.";
enum s_Deficient  = " nodes were pressure deficient.";
enum s_ReSolve1   =
    "\n    Re-solving network with these made fixed grade.";
enum s_Reductions1 =  " nodes require demand reductions.";
enum s_ReSolve2    =
    "\n    Re-solving network with these reductions made.";
enum s_Reductions2 =
    " nodes require further demand reductions to 0.";

//! \class HydEngine
//! \brief Simulates extended period hydraulics.
//!
//! The HydEngine class carries out an extended period hydraulic simulation on
//! a pipe network, calling on its HydSolver object to solve the conservation of
//! mass and energy equations at each time step.

class HydEngine
{
  public:

    // Constructor/Destructor

    this(){
        engineState= HydEngine.CLOSED;
        network = null;
        hydSolver = null;
        matrixSolver = null;
        saveToFile = false;
        halted = false;
        startTime = 0;
        rptTime = 0;
        hydStep = 0;
        currentTime = 0;
        timeOfDay = 0;
        peakKwatts = 0.0;
    }

    ~this(){close();}

    // Public Methods

    void open(Network nw){
        // ... close a currently opened engine

        if (engineState != HydEngine.CLOSED) close();
        network = nw;

        // ... create hydraulic sub-models (can throw exception)

        network.createHeadLossModel();
        network.createDemandModel();
        network.createLeakageModel();
        
        // ... create and initialize a matrix solver

        matrixSolver = MatrixSolver.factory(
            network.option(Options.MATRIX_SOLVER), network.msgLog);
            
        if ( matrixSolver is null )
        {
            throw new SystemError(SystemError.MATRIX_SOLVER_NOT_OPENED);
        }
        initMatrixSolver();
        
        // ... create a hydraulic solver

        hydSolver = HydSolver.factory(
            network.option(Options.HYD_SOLVER), network, matrixSolver);
        if ( hydSolver is null )
        {
            throw new SystemError(SystemError.HYDRAULIC_SOLVER_NOT_OPENED);
        }
        engineState = HydEngine.OPENED;
    }

    void init_(bool initFlows){
        if (engineState == HydEngine.CLOSED) return;

        foreach (Link link; network.links)
        {
            link.initialize(initFlows);        // flows & status
            link.setResistance(network);       // pipe head loss resistance
        }

        foreach (Node node; network.nodes)
        {
            node.initialize(network);          // head, quality, volume, etc.
        }

        int patternStep = cast(int)network.option(Options.PATTERN_STEP);
        int patternStart = cast(int)network.option(Options.PATTERN_START);
        foreach (Pattern pattern; network.patterns)
        {
            pattern.init_(patternStep, patternStart);
        }

        halted = 0;
        currentTime = 0;
        hydStep = 0;
        startTime = cast(int)network.option(Options.START_TIME);
        rptTime = cast(int)network.option(Options.REPORT_START);
        peakKwatts = 0.0;
        engineState = HydEngine.INITIALIZED;
        timeStepReason = "";
    }

    int solve(int* t){
        if ( engineState != HydEngine.INITIALIZED ) return 0;
        
        if ( network.option(Options.REPORT_STATUS) )
        {
            //network.msgLog.writef("\n  Hour %s%s",
            //    Utilities.getTime(cast(long)currentTime), timeStepReason);
        }
        
        *t = currentTime;
        timeOfDay = (currentTime + startTime) % 86_400;
        updateCurrentConditions();
        
        //if ( network.option(Options.REPORT_TRIALS) )  network.msgLog << endl;
        int trials = 0;
        int statusCode = hydSolver.solve(hydStep, trials);

        if ( statusCode == HydSolver.SUCCESSFUL && isPressureDeficient() )
        {
            statusCode = resolvePressureDeficiency(trials);
            
        }
        
        reportDiagnostics(statusCode, trials);
        if ( halted ) throw new SystemError(SystemError.HYDRAULICS_SOLVER_FAILURE);
        
        return statusCode;
    }

    void advance(int* tstep){
        *tstep = 0;
        if ( engineState != HydEngine.INITIALIZED ) return;

        // ... save current results to hydraulics file
        //if ( saveToFile ) errcode = hydWriter.writeResults(hydState, hydTime);

        // ... if time remains, find time (hydStep) until next hydraulic event

        hydStep = 0;
        int timeLeft = cast(int)(network.option(Options.TOTAL_DURATION) - currentTime);
        if ( halted ) timeLeft = 0;
        if ( timeLeft > 0  )
        {
            hydStep = getTimeStep();
            if ( hydStep > timeLeft ) hydStep = timeLeft;
        }
        *tstep = hydStep;

        // ... update energy usage and tank levels over the time step

        updateEnergyUsage();
        updateTanks();

        // ... advance time counters

        currentTime += hydStep;
        if ( currentTime >= rptTime )
        {
            rptTime += network.option(Options.REPORT_STEP);
        }

        // ... advance time patterns

        updatePatterns();
    }

    void close(){
        if ( engineState == HydEngine.CLOSED ) return;
        matrixSolver.destroy();
        matrixSolver = null;
        hydSolver.destroy();
        hydSolver = null;
        engineState = HydEngine.CLOSED;

        //... Other objects created in HydEngine.open() belong to the
        //    network object and are deleted by it.
    }

    int    getElapsedTime() { return currentTime; }
    double getPeakKwatts()  { return peakKwatts;  }

  private:

    // Engine state

    enum {CLOSED, OPENED, INITIALIZED} // EngineState
    alias EngineState = int;

    EngineState engineState;

    // Engine components

    Network       network;            //!< network being analyzed
    HydSolver     hydSolver;          //!< steady state hydraulic solver
    MatrixSolver  matrixSolver;       //!< sparse matrix solver
//    HydFile*       hydFile;            //!< hydraulics file accessor

    // Engine properties

    bool           saveToFile;         //!< true if results saved to file
    bool           halted;             //!< true if simulation has been halted
    int            startTime;          //!< starting time of day (sec)
    int            rptTime;            //!< current reporting time (sec)
    int            hydStep;            //!< hydraulic time step (sec)
    int            currentTime;        //!< current simulation time (sec)
    int            timeOfDay;          //!< current time of day (sec)
    double         peakKwatts;         //!< peak energy usage (kwatts)
    string         timeStepReason;     //!< reason for taking next time step

    // Simulation sub-tasks

    void initMatrixSolver(){
        int nodeCount = network.count(Element.NODE);
        int linkCount = network.count(Element.LINK);
        
        try
        {
            // ... place the start/end node indexes of each network link in arrays

            Array!int node1; node1.length = linkCount;
            Array!int node2; node2.length = linkCount;
            
            for (int k = 0; k < linkCount; k++)
            {
                
                node1[k] = network.link(k).fromNode.index;
                node2[k] = network.link(k).toNode.index;
            }

            // ...  initialize the matrix solver

            matrixSolver.init_(nodeCount, linkCount, &node1[0], &node2[0]);
        }
        catch (Exception e)
        {
            throw new Exception("MatrixSolver exception");
        }
    }

    int getTimeStep(){
        // ... normal time step is user-supplied hydraulic time step

        string reason ;
        int tstep = cast(int)network.option(Options.HYD_STEP);
        int n = currentTime / tstep + 1;
        tstep = n * tstep - currentTime;
        timeStepReason = "";

        // ... adjust for time until next reporting period

        int t = rptTime - currentTime;
        if ( t > 0 && t < tstep )
        {
            tstep = t;
            timeStepReason = "";
        }

        // ... adjust for time until next time pattern change

        tstep = timeToPatternChange(tstep);

        // ... adjust for shortest time to fill or drain a tank

        tstep = timeToCloseTank(tstep);

        // ... adjust for shortest time to activate a simple control

        tstep = timeToActivateControl(tstep);
        return tstep;
    }

    int timeToPatternChange(int tstep){
        Pattern changedPattern = null;
        foreach (Pattern pattern; network.patterns)
        {
            int t = pattern.nextTime(currentTime) - currentTime;
            if ( t > 0 && t < tstep )
            {
                tstep = t;
                changedPattern = pattern;
            }
        }
        if ( changedPattern )
        {
            timeStepReason = "  (change in Pattern " ~ changedPattern.name ~ ")";
        }
        return tstep;
    }

    int timeToActivateControl(int tstep){
        bool activated = false;
        foreach (Control control; network.controls)
        {
            int t = control.timeToActivate(network, currentTime, timeOfDay);
            if ( t > 0 && t < tstep )
            {
                tstep = t;
                activated = true;
            }
        }
        if ( activated ) timeStepReason = "  (control activated)";
        return tstep;
    }
    
    int timeToCloseTank(int tstep){
        Tank closedTank = null;
        foreach (Node node; network.nodes)
        {
            // ... check if node is a tank

            if ( node.type() == Node.TANK )
            {
                // ... find the time to fill (or empty) the tank

                Tank tank = cast(Tank)node;
                int t = tank.timeToVolume(tank.minVolume);
                if ( t <= 0 ) t = tank.timeToVolume(tank.maxVolume);

                // ... compare this time with current time step

                if ( t > 0 && t < tstep )
                {
                    tstep = t;
                    closedTank = tank;
                }
            }
        }
        if ( closedTank )
        {
            timeStepReason = "  (Tank " ~ closedTank.name ~ " closed)";
        }
        return tstep;
    }

    void updateCurrentConditions(){
        // ... identify global demand multiplier and pattern factor

        double multiplier = network.option(Options.DEMAND_MULTIPLIER);
        double patternFactor = 1.0;

    ////  Need to change from a pattern index to a patttern pointer  /////
    ////  or to update DEMAND_PATTERN option if current pattern is deleted.  ////

        int p = network.option(Options.DEMAND_PATTERN);
        if ( p >= 0 ) patternFactor = network.pattern(p).currentFactor();

        // ... update node conditions

        foreach (Node node; network.nodes)
        {
            // ... find node's full target demand for current time period
            node.findFullDemand(multiplier, patternFactor);

            // ... set its fixed grade state (for tanks & reservoirs)
            node.setFixedGrade();
        }

        // ... update link conditions

        foreach (Link link; network.links)
        {
            // ... open a temporarily closed link
            //if ( link.status >= Link.TEMP_CLOSED ) link.status = Link.LINK_OPEN;

            // ... apply pattern-based pump or valve setting
            link.applyControlPattern(network.msgLog);
        }

        // ... apply simple conditional controls

        foreach (Control control; network.controls)
        {
            control.apply(network, currentTime, timeOfDay);
        }
    }

    void updateTanks(){
        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.TANK )
            {
                Tank tank = cast(Tank)node;
                tank.pastHead = tank.head;
                tank.pastVolume = tank.volume;
                tank.pastOutflow = tank.outflow;
                node.fixedGrade = true;
                tank.updateVolume(hydStep);
                tank.updateArea();
            }
        }
    }

    void updatePatterns(){
        foreach (Pattern pattern; network.patterns)
        {
            pattern.advance(currentTime);
        }
    }

    void updateEnergyUsage(){
        // ... use a nominal time step of 1 day if running a single period analysis

        int dt = hydStep;
        if ( network.option(Options.TOTAL_DURATION) == 0 ) dt = 86_400;
        if ( dt == 0 ) return;

        // ... update energy usage for each pump link over the time step

        double totalKwatts = 0.0;
        foreach (Link link; network.links)
        {
            totalKwatts += link.updateEnergyUsage(network, dt);
        }

        // ... update peak energy usage over entire simulation

        peakKwatts = max(peakKwatts, totalKwatts);
    }

    bool isPressureDeficient(){
        int count = 0;
        foreach (Node node; network.nodes)
        {
            // ... This only gets evaluated for the CONSTRAINED demand model
            if ( node.isPressureDeficient(network) ) count++;
        }
        if ( count > 0 && network.option(Options.REPORT_TRIALS) )
        {
            network.msgLog.writef("\n\n    %d%s", count, s_Deficient);
        }
        return (count > 0);
    }

    int resolvePressureDeficiency(ref int trials){
        int trials2 = 0;
        int trials3 = 0;
        int trials4 = 0;
        int count1 = 0;
        int count2 = 0;
        bool reportTrials = cast(bool)network.option(Options.REPORT_TRIALS);

        // ... re-solve network hydraulics with the pressure deficient junctions
        //     set to fixed grade (which occurred in isPressureDeficient())

        if ( reportTrials ) network.msgLog.writef("%s", s_ReSolve1);
        int statusCode = hydSolver.solve(hydStep, trials2);
        if ( statusCode == HydSolver.FAILED_ILL_CONDITIONED ) return statusCode;

        // ... adjust actual demands for the pressure deficient junctions

        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.JUNCTION && node.fixedGrade )
            {
                node.actualDemand = min(node.actualDemand, node.fullDemand);
                node.actualDemand = max(0.0, node.actualDemand);
                if ( node.actualDemand < node.fullDemand ) count1++;
                node.fixedGrade = false;
            }
        }

        // ... re-solve once more with the reduced demands at the affected junctions

        if (reportTrials )
        {
            network.msgLog.writef("\n\n    %d%s", count1, s_Reductions1);
            network.msgLog.writef("%s", s_ReSolve2);
        }
        statusCode = hydSolver.solve(hydStep, trials3);

        // ... check once more for any remaining pressure deficiencies

        foreach (Node node; network.nodes)
        {
            if ( node.isPressureDeficient(network) )
            {
                count2++;

                // ... remove fixed grade status set in isPressureDeficient
                //     and make actual demand 0
                node.fixedGrade = false;
                node.actualDemand = 0.0;
            }
        }

        // ... if there are any, then re-solve once more

        if ( count2 > 0 )
        {
            if ( reportTrials )
            {
                network.msgLog.writef("\n    %d%s", count2, s_Reductions2);
                network.msgLog.writef("%s\n", s_ReSolve2);
            }
            statusCode = hydSolver.solve(hydStep, trials4);
        }

        trials += trials2 + trials3 + trials4;
        return statusCode;
    }

    void reportDiagnostics(int statusCode, int trials){
        if ( statusCode == HydSolver.FAILED_ILL_CONDITIONED ||
       ( statusCode == HydSolver.FAILED_NO_CONVERGENCE  &&
            network.option(Options.IF_UNBALANCED) == Options.STOP ))
            halted = true;
        
        if ( network.option(Options.REPORT_TRIALS) ) network.msgLog.writef("\n");
        if ( network.option(Options.REPORT_STATUS) )
        {
            network.msgLog.writef("\n");
            switch (statusCode)
            {
            case HydSolver.SUCCESSFUL:
                network.msgLog.writef("%s%d%s", s_Balanced, trials, s_Trials);
                break;
            case HydSolver.FAILED_NO_CONVERGENCE:
                if ( halted ) network.msgLog.writef("%s", s_UnbalancedHalted);
                else          network.msgLog.writef("%s", s_Unbalanced);
                break;
            case HydSolver.FAILED_ILL_CONDITIONED:
                network.msgLog.writef("%s", s_IllConditioned);
                break;
            default: break;
            }
            network.msgLog.writef("\n");
        }
        
    }
}