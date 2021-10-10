/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.control;

import std.outbuffer;
import std.math;
import std.conv: to;

import epanet.elements.element;
import epanet.elements.node;
import epanet.elements.link;
import epanet.core.network;
import epanet.core.error;
import epanet.core.units;
import epanet.elements.tank;
import epanet.utilities.utilities;

//! \class Control
//! \brief A class that controls pumps and valves based on a single condition.

class Control: Element
{
  public:
    enum {TANK_LEVEL, PRESSURE_LEVEL, ELAPSED_TIME, TIME_OF_DAY,
                      RULE_BASED}
    alias ControlType = int;
    enum {CLOSED_STATUS, OPEN_STATUS, NO_STATUS}
    alias StatusType = int;
    enum {LOW_LEVEL, HI_LEVEL, NO_LEVEL}
    alias LevelType = int;

    // Constructor/Destructor
    this(int type_, string name_){
        super(name_);
        type = type_;
        link = null;
        status = NO_STATUS;
        setting = 0.0;
        node = null;
        head = 0.0;
        volume = 0.0;
        levelType = NO_LEVEL;
        time = 0;
    }
    ~this(){}

    static const string s_TankLevel      = " by level control on tank ";
    static const string s_PressureLevel  = " by pressure control on node ";
    static const string s_ElapsedTime    = " by elapsed time control";
    static const string s_TimeOfDay      = " by time of day control";
    static const string s_StatusChanged  = " status changed to ";
    static const string s_SettingChanged = " setting changed to ";
    static const string[3] statusTxt      = ["closed", "open", ""];

    // Applies all pressure controls to the pipe network,
    // return true if status of any link changes
    static bool applyPressureControls(Network network){
        bool makeChange = true;
        bool changed = false;

        foreach(control; network.controls)
        {
            if ( control.type == PRESSURE_LEVEL )
            {
                if ( (control.levelType == LOW_LEVEL &&
                    control.node.head < control.head)
                ||   (control.levelType == HI_LEVEL &&
                    control.node.head > control.head) )
                {
                    if (control.activate(makeChange, network.msgLog))
                        changed = true;
                }
            }
        }

        return changed;
    }

    // Sets the properties of a control
    void    setProperties(
                int    controlType,
                Link  controlLink,
                int    linkStatus,
                double linkSetting,
                Node  controlNode,
                double nodeSetting,
                int    controlLevelType,
                int    timeSetting){
        type = controlType;
        link = controlLink;
        if ( linkStatus != NO_STATUS ) status = linkStatus;
        else setting = linkSetting;
        node = controlNode;
        head = nodeSetting;
        levelType = cast(LevelType)controlLevelType;
        time = timeSetting;
    }

    // Produces a string representation of the control
    string toStr(Network nw){
        // ... write Link name and its control action

        OutBuffer b = new OutBuffer();
        b.writef("Link %s ", link.name);
        if ( status == CLOSED_STATUS ) b.writef("CLOSED");
        else if ( status == OPEN_STATUS ) b.writef("OPEN");
        else b.writef(" %f ", setting);

        // ... write node condition or time causing the action

        switch (type)
        {
        case TANK_LEVEL:
            b.writef(" IF NODE %s ", node.name);
            if ( levelType == LOW_LEVEL ) b.writef("BELOW");
            else b.writef("ABOVE");
            b.writef(" %d", cast(int)((head - node.elev) * nw.ucf(Units.LENGTH)));
            break;

        case PRESSURE_LEVEL:
            b.writef(" IF NODE %s ", node.name);
            if ( levelType == LOW_LEVEL ) b.writef("BELOW");
            else b.writef("ABOVE");
            b.writef(" %.4f", (head - node.elev) * nw.ucf(Units.PRESSURE));
            break;

        case ELAPSED_TIME:
            b.writef(" AT TIME %s", Utilities.getTime(time));
            break;

        case TIME_OF_DAY:
            b.writef(" AT CLOCKTIME %s", Utilities.getTime(time));
            break;
        default: break;
        }
        
        return b.toString();
    }

    // Converts the control's properties to internal units
    void convertUnits(Network network){
        if ( type == TANK_LEVEL )
        {
            Tank tank = cast(Tank)node;
            head = head / network.ucf(Units.LENGTH) + node.elev;
            volume = tank.findVolume(head);
        }

        else if ( type == PRESSURE_LEVEL )
        {
            head = head / network.ucf(Units.PRESSURE) + node.elev;
        }

        if ( link ) setting = link.convertSetting(network, setting);
    }

    // Returns the control's type (see ControlType enum)
    int getType(){ return type; }

    // Finds the time until the control is next activated
    int timeToActivate(Network network, int t, int tod){
        Tank tank;
        bool makeChange = false; //do not implement any control actions
        int  aTime = -1;
        switch (type)
        {
        case PRESSURE_LEVEL: break;

        case TANK_LEVEL:
            tank = cast(Tank)node;
            aTime = tank.timeToVolume(volume);
            break;

        case ELAPSED_TIME:
            aTime = time - t;
            break;

        case TIME_OF_DAY:
            if (time >= tod) aTime = time - tod;
            else aTime = 86400 - tod + time;
            break;

        default: break;
        }

        if ( aTime > 0 && activate(makeChange, network.msgLog) ) return aTime;
        else return -1;
    }

    // Checks if the control's conditions are met
    void apply(Network network, int t, int tod){
        bool makeChange = true;
        Tank tank;

        switch (type)
        {
        case PRESSURE_LEVEL: break;

        case TANK_LEVEL:
            tank = cast(Tank)node;
            // ... use tolerance of one second's worth of inflow/outflow on action level
            if ( (levelType == LOW_LEVEL && tank.volume <= volume + abs(tank.outflow) )
            ||   (levelType == HI_LEVEL && tank.volume >= volume - abs(tank.outflow)) )
            {
                activate(makeChange, network.msgLog);
            }
            break;

        case ELAPSED_TIME:
            if ( t == time ) activate(makeChange, network.msgLog);
            break;

        case TIME_OF_DAY:
            if ( tod == time ) activate(makeChange, network.msgLog);
            break;
        
        default: break;
        }
    }

  private:
    int         type;                  //!< type of control
    Link        link;                  //!< link being controlled
    int         status;                //!< open/closed setting for link
    double      setting;               //!< speed or valve setting for link
    Node        node;                  //!< node that triggers control action
    double      head;                  //!< head that triggers control action
    double      volume;                //!< volume corresponding to head trigger
    LevelType   levelType;             //!< type of node head trigger
    int         time;                  //!< time (sec) that triggers control

    // Activates the control's action
    bool activate(bool makeChange, OutBuffer msgLog){
        bool   result = false;
        string reason = "";
        string linkStr = link.typeStr() ~ " " ~ link.name;

        switch (type)
        {
        case TANK_LEVEL:
            reason = s_TankLevel ~ node.name;
            break;

        case PRESSURE_LEVEL:
            reason = s_PressureLevel ~ node.name;
            break;

        case ELAPSED_TIME:
            reason = s_ElapsedTime;
            break;

        case TIME_OF_DAY:
            reason = s_TimeOfDay;
            break;
        
        default: break;
        }

        if ( status != NO_STATUS )
        {
            reason =  linkStr ~ s_StatusChanged ~ statusTxt[status] ~ reason;
            result = link.changeStatus(status, makeChange, reason, msgLog);
        }
        else
        {
            reason = linkStr ~ s_SettingChanged ~ setting.to!string ~
                reason;
            result = link.changeSetting(setting, makeChange, reason, msgLog);
        }
        return result;
    }

}