/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.input.optionparser;

import std.container.array: Array;

import epanet.core.network;
import epanet.core.error;
import epanet.core.options;
import epanet.utilities.utilities;
import epanet.elements.element;
import epanet.elements.node;
import epanet.elements.link;
import epanet.output.reportfields;

//! \class OptionParser
//! \brief Parses lines of project option data from a text file.

class OptionParser
{
  public:
    this(){}
    void parseOption(Network network, ref Array!string tokenList){
        // ... check for enough tokens
        if ( tokenList.length < 2 ) return;
        string* tokens = &tokenList[0];
        
        // ... parse option keywords
        string s1, s2, keyword;
        string value = "";
        s1 = Utilities.upperCase(tokens[0]);
        s2 = tokens[1];
        if ( tokenList.length > 2 )
        {
            value = tokens[2];
        }
        else value = s2;

        // ... check for deprecated keywords
        if ( Utilities.findFullMatch(s1, deprecatedKeywords[]) >= 0 ) return;

        // ... check for EPANET2 "QUALITY" keyword which requires special processing
        if ( s1 == w_QUALITY)
        {
            if ( tokenList.length == 2 ) value = "";
            parseQualOption(s2, value, network);
            return;
        }

        // ... get the equivalent EPANET3 keyword
        keyword = getEpanet3Keyword(s1, s2, value);

        // ... set the appropriate option to the parsed value
        if ( !value.length == 0 ) setOption(keyword, value, network);
    }

    void  parseTimeOption(Network network, ref Array!string tokenList){
        // ... check for enough tokens

        int nTokens = cast(int)tokenList.length;
        if ( nTokens < 2 ) return;
        string* tokens = &tokenList[0];
        
        // ... parse option keywords

        string s1, s2, keyword;
        s1 = Utilities.upperCase(tokens[0]);
        int i = 1;

        // ... check for single keyword option (for EPANET 2 compatibility)

        if (s1 == w_DURATION) keyword = timeOptionKeywords[Options.TOTAL_DURATION];
        else if (s1 == w_STATISTIC) keyword = timeOptionKeywords[Options.REPORT_STATISTIC];

        // ... otherwise form option keyword

        else
        {
            s2 = Utilities.upperCase(tokens[1]);
            keyword = s1 ~ "_" ~ s2;
            i = 2;
        }
        if ( i >= nTokens ) return;


        // ... find which time option we have

        int option = Utilities.findFullMatch(keyword, timeOptionKeywords);
        if ( option < 0 ) throw new InputError(InputError.INVALID_KEYWORD, keyword);

        // ... skip STATISTIC option

        if (option == Options.REPORT_STATISTIC) return;

        // ... create strings to hold a time value and its units

        string timeStr = tokens[i];
        string timeUnits = "";
        if ( nTokens > ++i ) timeUnits = tokens[i];

        // ... convert time value string to seconds

        int seconds = Utilities.getSeconds(timeStr, timeUnits);
        
        if (seconds < 0)
        {
            throw new InputError(InputError.INVALID_TIME, timeStr ~ " " ~ timeUnits);
        }
        network.options.setOption(cast(Options.TimeOption)option, seconds);
    }

    void  parseEnergyOption(Network network, ref Array!string tokenList){
        // ... check for enough tokens

        if ( tokenList.length < 3 ) return;
        string* tokens = &tokenList[0];
        double value;

        // ... check for global energy options

        if (Utilities.match(tokens[0], w_GLOBAL))
        {
            // ... global price per kwh

            if (Utilities.match(tokens[1], w_PRICE))
            {
                if ( !Utilities.parseNumber(tokens[2], value) )
                {
                    throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
                }
                network.options.setOption(Options.ENERGY_PRICE, value);
            }

            // ... global time of day price pattern

            else if (Utilities.match(tokens[1], w_PATTERN))
            {
                int j = network.indexOf(Element.PATTERN, tokens[2]);
                if (j < 0) throw new InputError(InputError.UNDEFINED_OBJECT, tokens[2]);
                network.options.setOption(Options.ENERGY_PRICE_PATTERN, j);
            }

            // ... global pump efficiency

            else if (Utilities.match(tokens[1], w_EFFIC))
            {
                if ( !Utilities.parseNumber(tokens[2], value) )
                {
                    throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
                }
                network.options.setOption(Options.PUMP_EFFICIENCY, value);
            }
            else throw new InputError(InputError.INVALID_KEYWORD, tokens[1]);
        }

        // ... peak demand charge

        else if (Utilities.match(tokens[0], w_DEMAND))
        {
            if ( !Utilities.parseNumber(tokens[2], value) )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
            }
            network.options.setOption(Options.PEAKING_CHARGE, value);
        }
        else throw new InputError(InputError.INVALID_KEYWORD, tokens[0]);
    }

    void  parseReactOption(Network network, ref Array!string tokenList){
        // ... check for enough tokens

        if ( tokenList.length < 3 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string* tokens = &tokenList[0];

        // ... read reaction value (3rd token)

        double value;
        if ( !Utilities.parseNumber(tokens[2], value) )
        {
            throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
        }

        // ... reaction order options

        if (Utilities.match(tokens[0], w_ORDER))
        {
            if (Utilities.match(tokens[1], w_BULK))
            {
                network.options.setOption(Options.BULK_ORDER, value);
            }
            else if (Utilities.match(tokens[1], w_WALL))
            {
                network.options.setOption(Options.WALL_ORDER, value);
            }
            else if (Utilities.match(tokens[1], w_TANK))
            {
                network.options.setOption(Options.TANK_ORDER, value);
            }
            else throw new InputError(InputError.INVALID_KEYWORD, tokens[1]);
        }

        // ... global reaction rate coeffs.

        else if (Utilities.match(tokens[0], w_GLOBAL))
        {
            if (Utilities.match(tokens[1], w_BULK))
            {
                network.options.setOption(Options.BULK_COEFF, value);
            }
            else if (Utilities.match(tokens[1], w_WALL))
            {
                network.options.setOption(Options.WALL_COEFF, value);
            }
            else throw new InputError(InputError.INVALID_KEYWORD, tokens[1]);
        }

        // ... limiting concentration option

        else if (Utilities.match(tokens[0], w_LIMITING))
        {
            network.options.setOption(Options.LIMITING_CONCEN, value);
        }

        // ... wall demand roughness correlation option

        else if (Utilities.match(tokens[0], w_ROUGHNESS))
        {
            network.options.setOption(Options.ROUGHNESS_FACTOR, value);
        }

        else throw new InputError(InputError.INVALID_KEYWORD, tokens[0]);
    }

    void  parseReportOption(Network network, ref Array!string tokenList){
        // ... check for no data
        int nTokens = cast(int)tokenList.length;
        if ( nTokens < 2 ) return;
        string* tokens = &tokenList[0];
        string keyword = Utilities.upperCase(tokens[0]);

        // ... PAGESIZE is deprecated
        //if ( Utilities.match(keyword, "PAGESIZE") ) return;
        if ( keyword == "PAGESIZE" || keyword == "PAGE") return;

        // ... check if option is name of report file
        if ( Utilities.match(keyword, "FILE") )
        {
            network.options.setOption(Options.RPT_FILE_NAME, tokens[1]);
            return;
        }

        // ... check for report types options
        int value;
        int option = Utilities.findFullMatch(keyword, reportOptionKeywords);
        if ( option >= 0 )
        {
            option = Options.REPORT_SUMMARY + option;

            // ... convert EPANET 2 "STATUS FULL" option to "TRIALS  YES" option
            if ( option == Options.REPORT_STATUS && Utilities.match(tokens[1], "FULL") )
            {
                network.options.setOption(Options.REPORT_TRIALS, true);
                network.options.setOption(Options.REPORT_STATUS, true);
                return;
            }

            if ( Utilities.match(tokens[1], "YES") ) value = true;
            else if ( Utilities.match(tokens[1], "NO") ) value = false;
            else throw new InputError(InputError.INVALID_KEYWORD, tokens[1]);
            network.options.setOption(cast(Options.IndexOption)option, value);
            return;
        }

        // ... parse which nodes & links are reported on
        if ( Utilities.match(keyword, "NODES") )
        {
            parseReportItems(Element.NODE, network, nTokens, tokens);
        }
        else if ( Utilities.match(keyword, "LINKS") )
        {
            parseReportItems(Element.LINK, network, nTokens, tokens);
        }

        // ... parse report field options
        else parseReportField(network, nTokens, tokens);
    }

  //private:
    string getEpanet3Keyword(S)(auto ref S s1,
                                  auto ref S s2,
                                        auto ref S value)
    {
        // ... check if first string matches an EPANET2 single keyword

        int i = Utilities.findFullMatch(s1, epanet2Keywords);
        if ( i < 0 ) return s1;

        // ... return the corresponding EPANET3 keyword
        //     ("i" is the index of the matching entry in epanet2Keywords)
        //

        switch(i)
        {
        case 0: return indexOptionKeywords[Options.FLOW_UNITS];
        case 1: return indexOptionKeywords[Options.PRESSURE_UNITS];
        case 2: return stringOptionKeywords[Options.HEADLOSS_MODEL];
        case 3: return stringOptionKeywords[Options.HYD_FILE_NAME];
        case 4: break;  //QUALITY keyword handled separately
        case 5: return valueOptionKeywords[Options.KIN_VISCOSITY];
        case 6: return valueOptionKeywords[Options.MOLEC_DIFFUSIVITY];
        case 7: return valueOptionKeywords[Options.SPEC_GRAVITY];
        case 8: return indexOptionKeywords[Options.MAX_TRIALS];
        case 9: return valueOptionKeywords[Options.RELATIVE_ACCURACY];
        case 10: value = s2; //make the 2nd token the option's value
                return indexOptionKeywords[Options.IF_UNBALANCED];
        case 11: return indexOptionKeywords[Options.DEMAND_PATTERN];
        case 12: return valueOptionKeywords[Options.DEMAND_MULTIPLIER];
        case 13: return valueOptionKeywords[Options.EMITTER_EXPONENT];
        case 14: return valueOptionKeywords[Options.QUAL_TOLERANCE];
        case 15: return stringOptionKeywords[Options.MAP_FILE_NAME];
        default: break;
        }
        return s1;
    }
    void setOption(S)(auto ref S keyword,
                          auto ref S value,
                          Network network)
    {
        // ... try to assign value to a string option

        int option = Utilities.findFullMatch(keyword, stringOptionKeywords);
        if ( option >=  0 )
        {
            int err = network.options.setOption(
                        cast(Options.StringOption)option, value);
            if ( err ) throw new InputError(err, value);
            return;
        }

        // ... try to assign value to a category option

        option = Utilities.findFullMatch(keyword, indexOptionKeywords);
        if ( option >= 0 )
        {
            int err = network.options.setOption(
                        cast(Options.IndexOption)option, value, network);
            if ( err ) throw new InputError(err, value);
            return;
        }

        // ... try to assign value to a value option

        option = Utilities.findFullMatch(keyword, valueOptionKeywords);
        if ( option < 0 ) throw new InputError(InputError.INVALID_KEYWORD, keyword);
        double x;
        if (!Utilities.parseNumber(value, x))
        {
            throw new InputError(InputError.INVALID_NUMBER, value);
        }
        network.options.setOption(cast(Options.ValueOption)option, x);
    }

    void parseQualOption(S)(auto ref S s2,
                                auto ref S s3,
                                Network network)
    {
        string s2U = Utilities.upperCase(s2);
        int i = Utilities.findFullMatch(s2U, epanetQualKeywords[]);
        if ( i >= 0 )
        {
            network.options.setOption(Options.QUAL_MODEL, s2U);
            network.options.setOption(Options.QUAL_NAME, s2U);
            network.options.setOption(Options.QUAL_TYPE, i);
            network.options.setOption(Options.QUAL_UNITS, i);
        }
        else
        {
            network.options.setOption(Options.QUAL_MODEL, w_CHEMICAL);
            network.options.setOption(Options.QUAL_NAME, s2);
            network.options.setOption(Options.QUAL_TYPE, Options.CHEM);
            network.options.setOption(Options.QUAL_UNITS, Options.MGL);
        }

        if ( !s3.length == 0 )
        {
            if ( network.option(Options.QUAL_TYPE) == Options.TRACE )
            {
                int nodeIndex = network.indexOf(Element.NODE, s3);
                if (i < 0) throw new InputError(InputError.UNDEFINED_OBJECT, s3);
                network.options.setOption(Options.TRACE_NODE, nodeIndex);
                network.options.setOption(Options.TRACE_NODE_NAME, s3);
            }
            if ( network.option(Options.QUAL_TYPE) == Options.CHEM )
            {
                string s3U = Utilities.upperCase(s3);
                if ( s3U == "MG/L" )
                    network.options.setOption(Options.QUAL_UNITS, Options.MGL);
                else if ( s3U == "UG/L" )
                    network.options.setOption(Options.QUAL_UNITS, Options.UGL);
                else throw new InputError(InputError.INVALID_KEYWORD, s3);
            }
        }
    }

    void parseReportItems(int nodeOrLink,
                                 Network network,
                                 int nTokens,
                                 string* tokens){
        // ... process NODES ALL/NONE & LINKS ALL/NONE options
        int value = Options.SOME;
        Options.IndexOption option = Options.REPORT_NODES;
        if ( nodeOrLink == Element.LINK ) option = Options.REPORT_LINKS;
        if ( Utilities.match(tokens[1], "NONE") ) value = Options.NONE;
        if ( Utilities.match(tokens[1], "ALL") )  value = Options.ALL;
        if ( value != Options.SOME )
        {
            network.options.setOption(option, value);
            return;
        }

        // ... process NODES  n1  n2  etc. option
        if ( nodeOrLink == Element.NODE )
        {
            for (int i = 1; i < nTokens; i++)
            {
                Node node = network.node(tokens[i]);
                if ( node is null )
                {
                    throw new InputError(InputError.UNDEFINED_OBJECT, tokens[i]);
                }
                node.rptFlag = true;
            }
        }

        // ... process LINKS l1  l2  etc. option
        else
        {
            for (int i = 1; i < nTokens; i++)
            {
                Link link = network.link(tokens[i]);
                if ( link is null )
                {
                    throw new InputError(InputError.UNDEFINED_OBJECT, tokens[i]);
                }
                link.rptFlag = true;
            }
        }
    }

    void parseReportField(Network network,
                                 int nTokens,
                                 string* tokens)
    {
        int    type = Element.NODE;
        int    index = -1;
        int    enabled = -1;
        int    precision = -1;
        double lowerLimit = -1;
        double upperLimit = -1;

        // ... parse FieldName  YES/NO
        index = Utilities.findMatch(tokens[0], ReportFields.NodeFieldNames);
        if ( index < 0 )
        {
            type = Element.LINK;
            index = Utilities.findMatch(tokens[0], ReportFields.LinkFieldNames);
            if ( index < 0 ) throw new InputError(InputError.INVALID_KEYWORD, tokens[0]);
        }

        if ( Utilities.match(tokens[1], "YES") ) enabled = 1;
        else if ( Utilities.match(tokens[1], "NO") ) enabled = 0;
        else if ( nTokens < 3 ) return;

        // ... parse FieldName  PRECISION  number
        else if ( Utilities.match(tokens[1], "PRECISION") )
        {
            if ( !Utilities.parseNumber(tokens[2], precision) )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
            }
        }

        // ... parse FieldName  ABOVE/BELOW  number
        else if ( Utilities.match(tokens[1], "BELOW") )
        {
            if ( !Utilities.parseNumber(tokens[2], lowerLimit) )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
            }
        }
        else if ( Utilities.match(tokens[1], "ABOVE") )
        {
            if ( !Utilities.parseNumber(tokens[2], upperLimit) )
            {
                throw new InputError(InputError.INVALID_NUMBER, tokens[2]);
            }
        }
        else throw new InputError(InputError.INVALID_KEYWORD, tokens[1]);

        network.options.setReportFieldOption(
                type, index, enabled, precision, lowerLimit, upperLimit);
    }

}

// ... Keywords for StringOption enumeration in options.h
string[15] stringOptionKeywords =
    ["HYDRAULICS_FILE",
     "", "", // placeholders for file names
     "MAP_FILE", "HEADLOSS_MODEL", "DEMAND_MODEL", "LEAKAGE_MODEL",
     "HYDRAULIC_SOLVER", "STEP_SIZING", "MATRIX_SOLVER", "",
     "QUALITY_MODEL", "QUALITY_NAME", "QUALITY_UNITS", null];

// ... Keywords for IndexOption enumeration in options.h
string[12] indexOptionKeywords =
    ["",  // placeholder for UNIT_SYSTEM
     "FLOW_UNITS", "PRESSURE_UNITS", "MAXIMUM_TRIALS", "IF_UNBALANCED",
     "",  // reserved for hydraulics file mode
     "DEMAND_PATTERN",
     "",  // placeholder for ENERGY_PRICE_PATTERN
     "",  // placeholder for QUAL_TYPE
     "",  // placeholder for QUAL_UNITS
     "TRACE_NODE", null];

// ... Keywords for reporting options portion of IndexOption enumeration
string[5] reportOptionKeywords =
    ["SUMMARY", "ENERGY", "STATUS", "TRIALS", null];

// ... Keywords for ValueOption enumeration in options.h
string[17] valueOptionKeywords =
    ["SPECIFIC_GRAVITY", "SPECIFIC_VISCOSITY", "DEMAND_MULTIPLIER",
     "MINIMUM_PRESSURE", "SERVICE_PRESSURE", "PRESSURE_EXPONENT",
	 "EMITTER_EXPONENT", "LEAKAGE_COEFF1", "LEAKAGE_COEFF2",
	 "RELATIVE_ACCURACY", "HEAD_TOLERANCE", "FLOW_TOLERANCE",
	 "FLOW_CHANGE_LIMIT", "TIME_WEIGHT", "SPECIFIC_DIFFUSIVITY",
	 "QUALITY_TOLERANCE", null];

// ... Keywords for TimeOption enumeration in options.h
string[11] timeOptionKeywords =
    ["START_CLOCKTIME","HYDRAULIC_TIMESTEP", "QUALITY_TIMESTEP",
     "PATTERN_TIMESTEP", "PATTERN_START", "REPORT_TIMESTEP", "REPORT_START",
     "RULE_TIMESTEP", "TOTAL_DURATION", "REPORT_STATISTIC", null];

// ... Deprecated keywords
string[9] deprecatedKeywords =
    ["SEGMENTS", "VERIFY", "CHECKFREQ", "MAXCHECK", "DAMPLIMIT",
     "HTOL", "QTOL", "RQTOL", null];

// ... Single keywords (for EPANET2 compatibility)
string[17] epanet2Keywords =
    ["UNITS", "PRESSURE", "HEADLOSS", "HYDRAULICS", "QUALITY", "VISCOSITY",
     "DIFFUSIVITY", "SPECIFIC", "TRIALS",  "ACCURACY", "UNBALANCED",
     "PATTERN", "DEMAND", "EMITTER","TOLERANCE", "MAP", null];

string[5] epanetQualKeywords =
    ["NONE", "AGE", "TRACE", "CHEMICAL", null];

string w_QUALITY = "QUALITY";
string w_CHEMICAL = "CHEMICAL";
//string w_TRACE = "TRACE";
string w_DURATION = "DURATION";
string w_STATISTIC = "STATISTIC";
string w_GLOBAL = "GLOBAL";
string w_PRICE = "PRICE";
string w_PATTERN = "PATTERN";
string w_EFFIC = "EFFIC";
string w_DEMAND = "DEMAND";
string w_ORDER = "ORDER";
string w_BULK = "BULK";
string w_WALL = "WALL";
string w_TANK = "TANK";
string w_LIMITING = "LIMITING";
string w_ROUGHNESS = "ROUGHNESS";
//string w_NONE = "NONE";