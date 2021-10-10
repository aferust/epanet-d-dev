/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.core.options;

import core.stdc.stdlib: atoi;
import std.algorithm: min;
import std.traits: EnumMembers;
import std.string: toStringz;

import epanet.core.error;
import epanet.output.reportfields;
import epanet.core.constants;
import epanet.utilities.utilities;
import epanet.core.network;
import epanet.core.options;
import epanet.elements.element;

// Keywords for FlowUnits enumeration in options.h
string[11] flowUnitsWords =
    ["CFS", "GPM", "MGD", "IMGD", "AFD", "LPS", "LPM", "MLD", "CMH", "CMD", null];

// Keywords for PressureUnits enumeration in options.h
string[4] pressureUnitsWords = ["PSI", "METERS", "PKA", null];

// Headloss formula keywords
string[4] headlossModelWords = ["H-W", "D-W", "C-M", null];

// Hydraulic Newton solver step size method names
string[4] stepSizingWords = ["FULL", "RELAXATION", "LINESEARCH", null];

string[3] ifUnbalancedWords = ["STOP", "CONTINUE", null];

// Demand model keywords
string[5] demandModelWords =
    ["FIXED", "CONSTRAINED", "POWER", "LOGISTIC", null];

// Leakage model keywords
string[4] leakageModelWords =
    ["NONE", "POWER", "FAVAD", null];

// Quality model keywords
string[5] qualModelWords = ["NONE", "AGE", "TRACE", "CHEMICAL", null];

// Quality units keywords
string[6] qualUnitsWords = ["", "HRS", "PCNT", "MG/L", "UG/L", null];

//! \class Options
//! \brief User-supplied options for analyzing a pipe network.

class Options
{
  public:

    // ... Enumerated values for categorical options

    enum     {US, SI} // UnitSystem
    enum     {CFS, GPM, MGD, IMGD, AFD, LPS, LPM, MLD, CMH, CMD} // FlowUnits
    enum {PSI, METERS, KPA} // PressureUnits
    enum       {SCRATCH, USE, SAVE} // FileMode
    enum   {STOP, CONTINUE} // IfUnbalanced
    enum       {NOQUAL, AGE, TRACE, CHEM} // QualType
    enum      {NOUNITS, HRS, PCNT, MGL, UGL} // QualUnits
    enum  {NONE, ALL, SOME} // ReportedItems

    // ... Options with string values

    enum StringOption {
        HYD_FILE_NAME,         //!< Name of binary file containing hydraulic results
        OUT_FILE_NAME,         //!< Name of binary file containing simulation results
        RPT_FILE_NAME,         //!< Name of text file containing output report
        MAP_FILE_NAME,         //!< Name of text file containing nodal coordinates

        HEADLOSS_MODEL,        //!< Name of head loss model used
        DEMAND_MODEL,          //!< Name of nodal demand model used
        LEAKAGE_MODEL,         //!< Name of pipe leakage model used
        HYD_SOLVER,            //!< Name of hydraulic solver method
        STEP_SIZING,           //!< Name of Newton step size method
        MATRIX_SOLVER,         //!< Name of sparse matrix eqn. solver
        DEMAND_PATTERN_NAME,   //!< Name of global demand pattern

        QUAL_MODEL,            //!< Name of water quality model used
        QUAL_NAME,             //!< Name of water quality constituent
        QUAL_UNITS_NAME,       //!< Name of water quality units
        TRACE_NODE_NAME,       //!< Name of node for source tracing

        MAX_STRING_OPTIONS
    }

    // for accessing enum members like Options.OUT_FILE_NAME instead of Options.StringOption.OUT_FILE_NAME.
    mixin template StrOptAliases()
    {
        static foreach(name; __traits(allMembers, StringOption))
            mixin("alias " ~ name ~ " = " ~ " __traits(getMember, StringOption, name);");
    }
    mixin StrOptAliases;

    // ... Options with integer, categorical or yes/no values

    enum IndexOption {
        UNIT_SYSTEM,           //!< Choice of units system
        FLOW_UNITS,            //!< Choice of flow rate units
        PRESSURE_UNITS,        //!< Choice of pressure units
        MAX_TRIALS,            //!< Maximum hydraulic trials
        IF_UNBALANCED,         //!< Stop or continue if network is unbalanced
        HYD_FILE_MODE,         //!< Binary hydraulics file mode
        DEMAND_PATTERN,        //!< Global demand pattern index
        ENERGY_PRICE_PATTERN,  //!< Global energy price pattern index

        QUAL_TYPE,             //!< Type of water quality analysis
        QUAL_UNITS,            //!< Units of the quality constituent
        TRACE_NODE,            //!< Node index for source tracing

        REPORT_SUMMARY,        //!< report input/output summary
        REPORT_ENERGY,         //!< report energy usage
        REPORT_STATUS,         //!< report system status
        REPORT_TRIALS,         //!< report result of each trial
        REPORT_NODES,          //!< report node results
        REPORT_LINKS,          //!< report link results

        MAX_INDEX_OPTIONS
    }

    mixin template IndOptAliases()
    {
        static foreach(name; __traits(allMembers, IndexOption))
            mixin("alias " ~ name ~ " = " ~ " __traits(getMember, IndexOption, name);");
    }
    mixin IndOptAliases;

    // ... Options with numerical values

    enum ValueOption { // ValueOption

        // Hydraulic properties
        SPEC_GRAVITY,          //!< Specific Gravity
        KIN_VISCOSITY,         //!< Kinematic viscosity (ft2/sec)
        DEMAND_MULTIPLIER,     //!< Global base demand multiplier
        MINIMUM_PRESSURE,      //!< Global minimum pressure to supply demand (ft)
        SERVICE_PRESSURE,      //!< Global pressure to supply full demand (ft)
        PRESSURE_EXPONENT,     //!< Global exponent for power function demands
        EMITTER_EXPONENT,      //!< Global exponent in emitter discharge formula
        LEAKAGE_COEFF1,
        LEAKAGE_COEFF2,

        // Hydraulic tolerances
        RELATIVE_ACCURACY,     //!< sum of all |flow changes| / sum of all |flows|
        HEAD_TOLERANCE,        //!< Convergence tolerance for head loss balance
        FLOW_TOLERANCE,        //!< Convergence tolerance for flow balance
        FLOW_CHANGE_LIMIT,     //!< Max. flow change for convergence
        TIME_WEIGHT,           //!< Time weighting for variable head tanks

        // Water quality options
        MOLEC_DIFFUSIVITY,     //!< Chemical's molecular diffusivity (ft2/sec)
        QUAL_TOLERANCE,        //!< Tolerance for water quality comparisons
        BULK_ORDER,            //!< Order of all bulk flow reactions in pipes
        WALL_ORDER,            //!< Order of all pipe wall reactions
        TANK_ORDER,            //!< Order of all bulk water reactions in tanks
        BULK_COEFF,            //!< Global rate coefficient for bulk reactions
        WALL_COEFF,            //!< Global rate coefficient for wall reactions
        LIMITING_CONCEN,       //!< Maximum concentration for growth reactions
        ROUGHNESS_FACTOR,      //!< Relates wall reaction coeff. to pipe roughness

        // Energy options
        ENERGY_PRICE,          //!< Global energy price (per kwh)
        PEAKING_CHARGE,        //!< Fixed energy charge per peak kw
        PUMP_EFFICIENCY,       //!< Global pump efficiency (fraction)

        MAX_VALUE_OPTIONS
    }

    mixin template ValOptAliases()
    {
        static foreach(name; __traits(allMembers, ValueOption))
            mixin("alias " ~ name ~ " = " ~ " __traits(getMember, ValueOption, name);");
    }
    mixin ValOptAliases;

    // ... Time options (in integer seconds)

    enum TimeOption: long {
        START_TIME,            //!< Starting time of day
        HYD_STEP,              //!< Hydraulic simulation time step
        QUAL_STEP,             //!< Water quality simulation time step
        PATTERN_STEP,          //!< Global time interval for time patterns
        PATTERN_START,         //!< Time of day at which all time patterns start
        REPORT_STEP,           //!< Reporting time step
        REPORT_START,          //!< Simulation time at which reporting begins
        RULE_STEP,             //!< Time step used to evaluate control rules
        TOTAL_DURATION,        //!< Total simulation duration
        REPORT_STATISTIC,      //!< How results are reported (min, max, range)

        MAX_TIME_OPTIONS
    }
    
    mixin template TimeOptAliases()
    {
        static foreach(name; __traits(allMembers, TimeOption))
            mixin("alias " ~ name ~ " = " ~ " __traits(getMember, TimeOption, name);");
    }
    mixin TimeOptAliases;

    //... Constructor / Destructor

    this(){
        
        reportFields = new ReportFields();
        
        setDefaults();
    }

    //~this() {}

    // ... Methods that return an option's value

    int flowUnits(){
        return indexOptions[FLOW_UNITS];
    }

    int pressureUnits(){
        return indexOptions[PRESSURE_UNITS];
    }

    string stringOption(StringOption option){
        return stringOptions[option];
    }

    int indexOption(IndexOption option){
        return indexOptions[option];
    }

    double valueOption(ValueOption option){
        return valueOptions[option]; 
    }

    long timeOption(TimeOption option){
        return timeOptions[option];
    }

    // ... Methods that set an option's value

    void setDefaults(){
        
        stringOptions[HYD_FILE_NAME]           = "";
        stringOptions[OUT_FILE_NAME]           = "";
        stringOptions[RPT_FILE_NAME]           = "";
        stringOptions[MAP_FILE_NAME]           = "";
        stringOptions[HEADLOSS_MODEL]          = "H-W";
        stringOptions[DEMAND_MODEL]            = "FIXED";

        stringOptions[LEAKAGE_MODEL]           = "NONE";
        stringOptions[HYD_SOLVER]              = "GGA";
        stringOptions[STEP_SIZING]             = "FULL";
        stringOptions[MATRIX_SOLVER]           = "SPARSPAK";
        stringOptions[DEMAND_PATTERN_NAME]     = "";
        stringOptions[QUAL_MODEL]              = "NONE";
        stringOptions[QUAL_NAME]               = "Chemical";
        stringOptions[QUAL_UNITS_NAME]         = "MG/L";
        stringOptions[TRACE_NODE_NAME]         = "";

        indexOptions[UNIT_SYSTEM]              = US;
        indexOptions[FLOW_UNITS]               = GPM;
        indexOptions[PRESSURE_UNITS]           = PSI;
        indexOptions[MAX_TRIALS]               = 100;
        indexOptions[IF_UNBALANCED]            = STOP;
        indexOptions[HYD_FILE_MODE]            = SCRATCH;
        indexOptions[DEMAND_PATTERN]           = -1;
        indexOptions[ENERGY_PRICE_PATTERN]     = -1;
        indexOptions[QUAL_TYPE]                = NOQUAL;
        indexOptions[QUAL_UNITS]               = MGL;
        indexOptions[TRACE_NODE]               = -1;

        indexOptions[REPORT_SUMMARY]           = true;
        indexOptions[REPORT_ENERGY]            = false;
        indexOptions[REPORT_STATUS]            = false;
        indexOptions[REPORT_TRIALS]            = false;
        indexOptions[REPORT_NODES]             = NONE;
        indexOptions[REPORT_LINKS]             = NONE;

        valueOptions[MINIMUM_PRESSURE]         = 0.0;
        valueOptions[SERVICE_PRESSURE]         = 0.0;
        valueOptions[PRESSURE_EXPONENT]        = 0.5;
        valueOptions[EMITTER_EXPONENT]         = 0.5;
        valueOptions[DEMAND_MULTIPLIER]        = 1.0;

        valueOptions[RELATIVE_ACCURACY]        = 0.0;
        valueOptions[HEAD_TOLERANCE]           = 0.0;
        valueOptions[FLOW_TOLERANCE]           = 0.0;
        valueOptions[FLOW_CHANGE_LIMIT]        = 0.0;
        valueOptions[TIME_WEIGHT]              = 0.0;

        valueOptions[ENERGY_PRICE]             = 0.0;
        valueOptions[PEAKING_CHARGE]           = 0.0;
        valueOptions[PUMP_EFFICIENCY]          = 0.75;
        valueOptions[SPEC_GRAVITY]             = 1.0;
        valueOptions[KIN_VISCOSITY]            = VISCOSITY;
        valueOptions[MOLEC_DIFFUSIVITY]        = DIFFUSIVITY;
        valueOptions[QUAL_TOLERANCE]           = 0.01;
        valueOptions[BULK_ORDER]               = 1.0;
        valueOptions[WALL_ORDER]               = 1.0;
        valueOptions[TANK_ORDER]               = 1.0;
        valueOptions[BULK_COEFF]               = 0.0;
        valueOptions[WALL_COEFF]               = 0.0;
        valueOptions[LIMITING_CONCEN]          = 0.0;
        valueOptions[ROUGHNESS_FACTOR]         = 0.0;

        valueOptions[LEAKAGE_COEFF1]           = 0.0;
        valueOptions[LEAKAGE_COEFF2]           = 0.0;

        timeOptions[START_TIME]                = 0;
        timeOptions[HYD_STEP]                  = 3600;
        timeOptions[QUAL_STEP]                 = 300;
        timeOptions[PATTERN_STEP]              = 3600;
        timeOptions[PATTERN_START]             = 0;
        timeOptions[REPORT_STEP]               = 3600;
        timeOptions[REPORT_START]              = 0;
        timeOptions[RULE_STEP]                 = 300;
        timeOptions[TOTAL_DURATION]            = 0;
        
        reportFields.setDefaults();
    }

    void adjustOptions(){
        // ... report start time cannot be greater than simulation duration */
        if ( timeOptions[REPORT_START] > timeOptions[TOTAL_DURATION] )
        {
            timeOptions[REPORT_START] = 0;
        }

        // ... no water quality analysis for steady state run
        if ( timeOptions[TOTAL_DURATION] == 0 ) indexOptions[QUAL_TYPE] = NOQUAL;

        // ... quality timestep cannot be greater than hydraulic timestep
        timeOptions[QUAL_STEP] = min(timeOptions[QUAL_STEP], timeOptions[HYD_STEP]);

        // ... rule time step cannot be greater than hydraulic time step
        timeOptions[RULE_STEP] = min(timeOptions[RULE_STEP], timeOptions[HYD_STEP]);

        // ... make REPORT_STATUS true if REPORT_TRIALS is true
        if ( indexOptions[REPORT_TRIALS] == true ) indexOptions[REPORT_STATUS] = true;
    }
    int setOption(S)(StringOption option, auto ref S value){
        int i;
        switch (option)
        {
        case HEADLOSS_MODEL:
            i = Utilities.findFullMatch(value, headlossModelWords[]);
            if (i < 0) return InputError.INVALID_KEYWORD;
            stringOptions[HEADLOSS_MODEL] = headlossModelWords[i];
            break;

        case STEP_SIZING:
            i = Utilities.findFullMatch(value, stepSizingWords);
            if (i < 0) return InputError.INVALID_KEYWORD;
            stringOptions[STEP_SIZING] = stepSizingWords[i];
            break;

        case DEMAND_MODEL:
            i = Utilities.findFullMatch(value, demandModelWords);
            if (i < 0) return InputError.INVALID_KEYWORD;
            stringOptions[DEMAND_MODEL] = demandModelWords[i];
            break;

        case LEAKAGE_MODEL:
            i = Utilities.findFullMatch(value, leakageModelWords);
            if (i < 0) return InputError.INVALID_KEYWORD;
            stringOptions[LEAKAGE_MODEL] = leakageModelWords[i];
            break;

        case QUAL_MODEL:
            i = Utilities.findFullMatch(value, qualModelWords);
            if ( i < 0 )
            {
                stringOptions[QUAL_MODEL] = "CHEMICAL";
                stringOptions[QUAL_NAME]  = value;
                indexOptions[QUAL_TYPE]   = CHEM;
                indexOptions[QUAL_UNITS]  = MGL;
            }
            else
            {
                stringOptions[QUAL_MODEL] = qualModelWords[i];
                indexOptions[QUAL_TYPE]   = i;
                if ( indexOptions[QUAL_TYPE] != CHEM )
                {
                    stringOptions[QUAL_NAME]  = qualModelWords[i];
                    indexOptions[QUAL_UNITS]  = i;
                }
            }
            break;

        case QUAL_NAME:
            stringOptions[QUAL_NAME]  = value;
            break;

        case QUAL_UNITS_NAME:
            i = Utilities.findFullMatch(value, qualUnitsWords[]);
            if (i < 0) return InputError.INVALID_KEYWORD;
            if ( i == MGL || i == UGL ) indexOptions[QUAL_UNITS] = i;
            break;

        case TRACE_NODE_NAME:
            stringOptions[TRACE_NODE_NAME] = value;
            break;

        default: break;
        }
        return 0;
    }

    int setOption(S)(IndexOption option, auto ref S value, Network network){
        int i;
        string ucValue = Utilities.upperCase(value);
        switch (option)
        {
        case FLOW_UNITS:
            i = Utilities.findFullMatch(ucValue, flowUnitsWords);
            if ( i < 0 ) return InputError.INVALID_KEYWORD;
            indexOptions[FLOW_UNITS] = i;
            break;

        case PRESSURE_UNITS:
            i = Utilities.findFullMatch(ucValue, pressureUnitsWords);
            if ( i < 0 ) return InputError.INVALID_KEYWORD;
            indexOptions[PRESSURE_UNITS] = i;
            break;

        case MAX_TRIALS:
            i = atoi(value.toStringz);
            if ( i <= 0 ) return InputError.INVALID_NUMBER;
            indexOptions[MAX_TRIALS] = i;
            break;

        case IF_UNBALANCED:
            i = Utilities.findFullMatch(ucValue, ifUnbalancedWords);
            if ( i < 0 ) return InputError.INVALID_KEYWORD;
            indexOptions[IF_UNBALANCED] = i;
            break;

        case HYD_FILE_MODE: break;

        case DEMAND_PATTERN:
            i = network.indexOf(Element.PATTERN, value);
            if ( i >= 0 )
            {
                indexOptions[DEMAND_PATTERN] = i;
                stringOptions[DEMAND_PATTERN_NAME] = value;
            }
            break;

        case TRACE_NODE:
            i = network.indexOf(Element.NODE, value);
            if (i < 0) return InputError.UNDEFINED_OBJECT;
            indexOptions[TRACE_NODE] = i;
            stringOptions[TRACE_NODE_NAME] = value;
            break;

        default: break;
        }
        return 0;
    }

    void setOption(IndexOption option, int value)
    {
        indexOptions[option] = value;
    }

    void setOption(ValueOption option, double value)
    {
        if ( option == KIN_VISCOSITY && value > 1.0e-3 ) value *= VISCOSITY;
        if ( option == MOLEC_DIFFUSIVITY && value > 1.0e-3 ) value *= DIFFUSIVITY;
        valueOptions[option] = value;
    }

    void setOption(TimeOption option, int value)
    {
        timeOptions[option] = value;
    }

    void setReportFieldOption(int type,
                                int index,
                                int enabled,
                                int precision,
                                double lowerLimit,
                                double upperLimit)
    {
        reportFields.setField(type, index, enabled, precision, lowerLimit, upperLimit);
    }

    // ... Methods that write a collection of options to a string

    string hydOptionsToStr()
    {
        import std.format, std.outbuffer;

        int w = 26;

        OutBuffer b = new OutBuffer();
        b.writef(pairFormat(w, "FLOW_UNITS", flowUnitsWords[indexOptions[FLOW_UNITS]]));
        b.writef(pairFormat(w, "PRESSURE_UNITS", pressureUnitsWords[indexOptions[PRESSURE_UNITS]]));
        b.writef(pairFormat(w, "HEADLOSS_MODEL", stringOptions[HEADLOSS_MODEL]));
        b.writef(pairFormat(w, "SPECIFIC_GRAVITY", format("%.4f", valueOptions[SPEC_GRAVITY])));
        b.writef(pairFormat(w, "SPECIFIC_VISCOSITY", format("%.4f", valueOptions[KIN_VISCOSITY] / VISCOSITY)));
        b.writef(pairFormat(w, "MAXIMUM_TRIALS", format("%d", indexOptions[MAX_TRIALS])));
        b.writef(pairFormat(w, "HEAD_TOLERANCE", format("%.4f", valueOptions[HEAD_TOLERANCE])));
        b.writef(pairFormat(w, "FLOW_TOLERANCE", format("%.4f", valueOptions[FLOW_TOLERANCE])));
        b.writef(pairFormat(w, "FLOW_CHANGE_LIMIT", format("%.4f", valueOptions[FLOW_CHANGE_LIMIT])));


        if ( valueOptions[RELATIVE_ACCURACY] > 0.0 )
        {
            b.writef(pairFormat(w, "RELATIVE_ACCURACY", format("%.4f", valueOptions[RELATIVE_ACCURACY])));
        }

        b.writef(pairFormat(w, "TIME_WEIGHT", format("%.4f", valueOptions[TIME_WEIGHT])));
        b.writef(pairFormat(w, "STEP_SIZING", stringOptions[STEP_SIZING]));
        b.writef(pairFormat(w, "IF_UNBALANCED", ifUnbalancedWords[indexOptions[IF_UNBALANCED]]));

        return b.toString();
    }

    string qualOptionsToStr(){
        import std.format, std.outbuffer;

        int w = 26;

        OutBuffer b = new OutBuffer();
        scope(exit) b.destroy();

        b.writef(pairFormat(w, "QUALITY_MODEL", stringOptions[QUAL_MODEL]));


        int qualType = indexOptions[QUAL_TYPE];

        if ( qualType == CHEM )
        {
            b.writef(pairFormat(w, "QUALITY_NAME", stringOptions[QUAL_NAME]));
            b.writef(pairFormat(w, "QUALITY_UNITS", qualUnitsWords[qualType]));
        }
        else if ( qualType == TRACE )
        {
            b.writef(pairFormat(w, "TRACE_NODE", stringOptions[TRACE_NODE_NAME]));
        }

        b.writef(pairFormat(w, "SPECIFIC_DIFFUSIVITY", format("%.4f", valueOptions[MOLEC_DIFFUSIVITY] / DIFFUSIVITY)));
        b.writef(pairFormat(w, "QUALITY_TOLERANCE", format("%.4f", valueOptions[QUAL_TOLERANCE])));
        
        return b.toString();
    }
    string demandOptionsToStr(){
        import std.format, std.outbuffer;

        OutBuffer b = new OutBuffer();

        int w = 26;

        b.writef(pairFormat(w, "DEMAND_MODEL", stringOptions[DEMAND_MODEL]));
        b.writef(pairFormat(w, "DEMAND_PATTERN", stringOptions[DEMAND_PATTERN_NAME]));
        b.writef(pairFormat(w, "DEMAND_MULTIPLIER", format("%.4f", valueOptions[DEMAND_MULTIPLIER])));
        b.writef(pairFormat(w, "MINIMUM_PRESSURE", format("%.4f", valueOptions[MINIMUM_PRESSURE])));
        b.writef(pairFormat(w, "SERVICE_PRESSURE", format("%.4f", valueOptions[SERVICE_PRESSURE])));
        b.writef(pairFormat(w, "PRESSURE_EXPONENT", format("%.4f", valueOptions[PRESSURE_EXPONENT])));
        b.writef(pairFormat(w, "LEAKAGE_MODEL", stringOptions[LEAKAGE_MODEL]));
        b.writef(pairFormat(w, "LEAKAGE_COEFF1", format("%.4f", valueOptions[LEAKAGE_COEFF1])));
        b.writef(pairFormat(w, "LEAKAGE_COEFF2", format("%.4f", valueOptions[LEAKAGE_COEFF2])));
        b.writef(pairFormat(w, "EMITTER_EXPONENT", format("%.4f", valueOptions[EMITTER_EXPONENT])));

        return b.toString();
    }

    string timeOptionsToStr(){
        import std.format, std.outbuffer;

        OutBuffer b = new OutBuffer();

        int w = 26;

        b.writef(pairFormat(w, "TOTAL DURATION", format("%s", Utilities.getTime(timeOptions[TOTAL_DURATION]))));
        b.writef(pairFormat(w, "HYDRAULIC TIMESTEP", format("%s", Utilities.getTime(timeOptions[HYD_STEP]))));
        b.writef(pairFormat(w, "QUALITY TIMESTEP", format("%s", Utilities.getTime(timeOptions[QUAL_STEP]))));
        b.writef(pairFormat(w, "RULE TIMESTEP", format("%s", Utilities.getTime(timeOptions[RULE_STEP]))));
        b.writef(pairFormat(w, "PATTERN TIMESTEP", format("%s", Utilities.getTime(timeOptions[PATTERN_STEP]))));
        b.writef(pairFormat(w, "PATTERN START", format("%s", Utilities.getTime(timeOptions[PATTERN_START]))));
        b.writef(pairFormat(w, "REPORT TIMESTEP", format("%s", Utilities.getTime(timeOptions[REPORT_STEP]))));
        b.writef(pairFormat(w, "REPORT START", format("%s", Utilities.getTime(timeOptions[REPORT_START]))));
        b.writef(pairFormat(w, "START CLOCKTIME", format("%s", Utilities.getTime(timeOptions[START_TIME]))));

        return b.toString();
    }
    string reactOptionsToStr(){
        import std.format, std.outbuffer;

        OutBuffer b = new OutBuffer();

        int w = 26;

        b.writef(pairFormat(w, "ORDER BULK", format("%.4f", valueOptions[BULK_ORDER])));
        b.writef(pairFormat(w, "ORDER WALL", format("%.4f", valueOptions[WALL_ORDER])));
        b.writef(pairFormat(w, "ORDER TANK", format("%.4f", valueOptions[TANK_ORDER])));
        b.writef(pairFormat(w, "GLOBAL BULK", format("%.4f", valueOptions[BULK_COEFF])));
        b.writef(pairFormat(w, "GLOBAL WALL", format("%.4f", valueOptions[WALL_COEFF])));
        b.writef(pairFormat(w, "LIMITING POTENTIAL", format("%.4f", valueOptions[LIMITING_CONCEN])));
        b.writef(pairFormat(w, "ROUGHNESS CORRELATION", format("%.4f", valueOptions[ROUGHNESS_FACTOR])));

        return b.toString();
    }
    string energyOptionsToStr(Network network){
        import std.format, std.outbuffer;

        OutBuffer b = new OutBuffer();

        int w = 26;

        b.writef(pairFormat(w, "GLOBAL EFFICIENCY ", format("%.4f", valueOptions[PUMP_EFFICIENCY])));
        b.writef(pairFormat(w, "GLOBAL PRICE", format("%.4f", valueOptions[ENERGY_PRICE])));
        

        int p = indexOptions[ENERGY_PRICE_PATTERN];
        if (p >= 0)
        {
            b.writef(pairFormat(w, "GLOBAL PATTERN", network.pattern(p).name));
        }

        b.writef(pairFormat(w, "DEMAND CHARGE", format("%.4f", valueOptions[PEAKING_CHARGE])));
        
        return b.toString();
    }

    string reportOptionsToStr(){
        import std.format, std.outbuffer;

        OutBuffer b = new OutBuffer();

        int w = 26;
        
        if ( indexOptions[REPORT_SUMMARY] )
            b.writef(pairFormat(w, "SUMMARY", "YES"));
        if ( indexOptions[REPORT_ENERGY] )
            b.writef(pairFormat(w, "ENERGY", "YES"));
        if ( indexOptions[REPORT_STATUS] )
            b.writef(pairFormat(w, "STATUS", "YES"));
            
        if ( indexOptions[REPORT_TRIALS] )
            b.writef(pairFormat(w, "TRIALS", "YES"));
        if ( indexOptions[REPORT_NODES] == 1 )
            b.writef(pairFormat(w, "NODES", "ALL"));
        if ( indexOptions[REPORT_LINKS] == 1 )
            b.writef(pairFormat(w, "LINKS", "ALL"));
        if ( stringOptions[RPT_FILE_NAME].length > 0 )
            b.writef(pairFormat(w, "FILE", stringOptions[RPT_FILE_NAME]));

        return b.toString();
    }

  private:

    string[MAX_STRING_OPTIONS]      stringOptions;
    int[MAX_INDEX_OPTIONS]          indexOptions;
    double[MAX_VALUE_OPTIONS]       valueOptions;
    long[MAX_TIME_OPTIONS]           timeOptions;
    ReportFields                    reportFields;
}

string pairFormat(S)(int woffset, auto ref S opname, auto ref S param){
    import std.format;
    return format("%s%*s\n", opname, woffset - opname.length + param.length, param);
}