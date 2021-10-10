/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.input.controlparser;

import std.uni : isWhite;
import std.array : split;

import epanet.elements.element;
import epanet.elements.node;
import epanet.elements.link;
import epanet.elements.tank;
import epanet.elements.control;
import epanet.core.network;
import epanet.core.error;
import epanet.utilities.utilities;

//-----------------------------------------------------------------------------
//  Control Keywords
//-----------------------------------------------------------------------------
enum w_OPEN      = "OPEN";
enum w_CLOSED    = "CLOSED";
enum w_NODE      = "NODE";
enum w_TIME      = "TIME";
enum w_CLOCKTIME = "CLOCKTIME";
enum w_ABOVE     = "ABOVE";
enum w_BELOW     = "BELOW";
enum w_LINK      = "LINK-";

//! \class ControlParser
//! \brief Parses a control statement from a line of text.
//!
//! The ControlParser class is used to parse a line of a simple control
//! statement read from a text file.

class ControlParser
{
  public:
    this(){
        initializeControlSettings();
    }
    ~this() {}
    void parseControlLine(ref string line, Network network)
    // Formats are:
    //   LINK id OPEN/CLOSED/setting IF NODE id ABOVE/BELOW value
    //   . . .                       AT TIME time
    //   . . .                       AT CLOCKTIME time  (AM/PM)
    // where time is in decimal hours or hrs:min:sec.

    {
        import std.string;
        
        line =line.strip;
        // ... initialize
        initializeControlSettings();

        ltokens = line.split!isWhite;
        
        // ... get settings for link being controlled
        parseLinkSetting(network); 
        
        if (ltokens.length < 6) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string keyword = ltokens[4];
        
        //... get node control level if keyword == NODE
        if ( Utilities.match(keyword, w_NODE) ) parseLevelSetting(network);

        //... get control time if keyword == TIME
        else if ( Utilities.match(keyword, w_TIME) ) parseTimeSetting();

        //... get control time of day if keyword == CLOCKTIME
        else if ( Utilities.match(keyword, w_CLOCKTIME) ) parseTimeOfDaySetting();

        else throw new InputError(InputError.INVALID_KEYWORD, keyword);

        //... create the control
        createControl(network);
    }

  private:
    void initializeControlSettings(){
        //... initialize control parameters
        controlType = -1;
        link = null;
        linkStatus = Control.NO_STATUS;
        linkSetting = 0.0;
        node = null;
        levelType = Control.LOW_LEVEL;
        nodeSetting = 0.0;
        timeSetting = -1;
    }

    void parseLinkSetting(Network network){
        //... read id of link being controlled
        string id = ltokens[1];
        
        link = network.link(id);
        if (link is null) throw new InputError(InputError.UNDEFINED_OBJECT, id);

        //... read control setting/status as a string
        if ( ltokens.length < 6 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string settingStr = ltokens[2];
        
        //... convert string to status or to numerical value
        if ( Utilities.match(settingStr, w_OPEN) )
        {
            linkStatus = Control.OPEN_STATUS;
        }
        else if ( Utilities.match(settingStr, w_CLOSED) )
        {
            linkStatus = Control.CLOSED_STATUS;
        }
        else if ( !Utilities.parseNumber(settingStr, linkSetting) )
        {
            throw new InputError(InputError.INVALID_NUMBER, settingStr);
        }
    }

    void parseLevelSetting(Network network){
        // ... read id of node triggering the control
        string id = ltokens[5];
        node = network.node(id);
        if (node is null) throw new InputError(InputError.UNDEFINED_OBJECT, id);

        // ... get type of trigger level
        if ( ltokens.length < 7 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string keyword = ltokens[6];
        
        if ( Utilities.match(keyword, w_ABOVE) ) levelType = Control.HI_LEVEL;
        else if (Utilities.match(keyword, w_BELOW)) levelType = Control.LOW_LEVEL;
        else throw new InputError(InputError.INVALID_KEYWORD, keyword);

        // ... get trigger level
        if ( ltokens.length < 8 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string settingStr = ltokens[7];
        
        if ( !Utilities.parseNumber(settingStr, nodeSetting) )
        {
            throw new InputError(InputError.INVALID_NUMBER, settingStr);
        }

        // ... get control type
        if ( node.type() == Node.TANK ) controlType = Control.TANK_LEVEL;
        else controlType = Control.PRESSURE_LEVEL;
    }

    void parseTimeSetting(){
        // ... read elapsed time and optional time units
        string strTime = ltokens[5];
        string strUnits = "";
        
        if ( ltokens.length > 6 ) strUnits= ltokens[6];

        // ... convert time string to seconds
        timeSetting = Utilities.getSeconds(strTime, strUnits);
        if ( timeSetting < 0 )
        {
            throw new InputError(InputError.INVALID_TIME, strTime ~ " " ~ strUnits);
        }
        controlType = Control.ELAPSED_TIME;
    }
    
    void parseTimeOfDaySetting(){
        // ... read time of day
        
        string strUnits = "";
        if ( ltokens.length < 6 ) throw new InputError(InputError.TOO_FEW_ITEMS, "");
        string strTime = ltokens[5];
        if ( ltokens.length > 6 ) strUnits = ltokens[6];

        // ... convert time of day to seconds
        timeSetting = Utilities.getSeconds(strTime, strUnits);
        if ( timeSetting < 0 )
        {
            throw new InputError(InputError.INVALID_TIME, strTime ~ " " ~ strUnits);
        }
        controlType = Control.TIME_OF_DAY;
    }

    void createControl(Network network){
        //... add a new control to the network
        string name = w_LINK ~ link.name;
        if ( !network.addElement(Element.CONTROL, controlType, name) )
        {
            throw new InputError(InputError.CANNOT_CREATE_OBJECT, name ~ " control");
        }
        int last = network.count(Element.CONTROL) - 1;
        Control control = network.control(last);

        //... set the control's parameters
        control.setProperties(
            controlType, link, linkStatus, linkSetting, node, nodeSetting, levelType, timeSetting);
    }

    string[]            ltokens;
    int                 controlType;
    Link                link;
    int                 linkStatus;
    double              linkSetting;
    Node                node;
    int                 levelType;
    double              nodeSetting;
    int                 timeSetting;
}