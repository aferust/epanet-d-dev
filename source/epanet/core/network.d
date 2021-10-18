/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.core.network;

import epanet.core.options;
import epanet.core.error;
import epanet.core.units;
import epanet.core.qualbalance;
import epanet.elements.element;
import epanet.utilities.graph;
import epanet.elements.node;
import epanet.elements.link;
import epanet.elements.pattern;
import epanet.elements.curve;
import epanet.elements.control;
import epanet.utilities.mempool;
import epanet.models.headlossmodel;
import epanet.models.qualmodel;
import epanet.models.demandmodel;
import epanet.models.leakagemodel;

import std.container.array: Array;
import std.outbuffer, std.stdio;


//class MemPool;

//! \class Network
//! \brief Contains the data elements that describe a pipe network.
//!
//! A Network object contains collections of the individual elements
//! belonging to the pipe network being analyzed by a Project.

class Network
{
  public:

    this(){
        msgLog = new OutBuffer();
        options = new Options();
        units = new Units();

        headLossModel = null;
        demandModel = null;
        leakageModel = null;
        qualModel = null;
        
        options.setDefaults();
        memPool = new MemPool();
    }

    ~this(){
        clear();
        memPool.destroy();
        options.destroy();

        memPool = null;
        headLossModel.destroy();
        headLossModel = null;
        demandModel.destroy();
        demandModel = null;
        leakageModel.destroy();
        leakageModel = null;
        qualModel.destroy();
        qualModel = null;
    }

    // Clears all elements from the network
    void clear(){
        // ... destroy all network elements
        
        foreach (Node node; nodes) node.destroy;
        nodes.clear();
        foreach (Link link; links) link.destroy;
        links.clear();
        foreach (Pattern pattern; patterns) pattern.destroy;
        patterns.clear();
        foreach (Curve curve; curves) curve.destroy;
        curves.clear();
        foreach (Control control; controls) control.destroy;
        controls.clear();

        // ... reclaim all memory allocated by the memory pool

        //memPool->reset();

        // ... re-set all options to their default values
        
        // options.setDefaults();
        
        // ... delete the contents of the message log
        //msgLog.str("");
    }

    // Adds an element to the network
    bool addElement(Element.ElementType element, int type, string name){
        // Note: the caller of this function must insure that the network doesn't
        //       already contain an element with the same name.

        try
        {
            if ( element == Element.NODE )
            {
                Node node = Node.factory(type, name/*, memPool*/);
                node.index = cast(int)nodes.length;
                nodeTable[node.name] = node;
                nodes.insertBack(node);
            }

            else if ( element == Element.LINK )
            {
                Link link = Link.factory (type, name/*, memPool*/);
                link.index = cast(int)links.length;
                linkTable[link.name] = link;
                links.insertBack(link);
            }

            else if ( element == Element.PATTERN )
            {
                Pattern pattern = Pattern.factory(type, name/*, memPool*/);
                pattern.index = cast(int)patterns.length;
                patternTable[pattern.name] = pattern;
                patterns.insertBack(pattern);
            }

            else if ( element == Element.CURVE )
            {
                Curve curve = new Curve(name);
                curve.index = cast(int)curves.length;
                curveTable[curve.name] = curve;
                curves.insertBack(curve);
            }

            else if ( element == Element.CONTROL )
            {
                Control control = new Control(type, name);
                control.index = cast(int)controls.length;
                controlTable[control.name] = control;
                controls.insertBack(control);
            }
            return true;
        }
        catch (Exception e)
        {
            return false;
        }
    }

    // Finds element counts by type and index by id name
    int count(Element.ElementType eType){
        switch(eType)
        {
        case Element.NODE:    return cast(int)nodes.length;
        case Element.LINK:    return cast(int)links.length;
        case Element.PATTERN: return cast(int)patterns.length;
        case Element.CURVE:   return cast(int)curves.length;
        case Element.CONTROL: return cast(int)controls.length;
        default: return 0;
        }
    }
    int indexOf(S)(Element.ElementType eType, auto ref S name){
        Element[string]* table;
        
        switch(eType)
        {
        case Element.NODE:
            table = &nodeTable;
            break;
        case Element.LINK:
            table = &linkTable;
            break;
        case Element.PATTERN:
            table = &patternTable;
            break;
        case Element.CURVE:
            table = &curveTable;
            break;
        case Element.CONTROL:
            table = &controlTable;
            break;
        default:
            return -1;
        }
        
        if(auto valptr = name in (*table))
            return (*valptr).index;
    
        return -1;
    }

    // Gets an analysis option by type
    int           option(Options.IndexOption type){ return options.indexOption(type); }
    double        option(Options.ValueOption type){ return options.valueOption(type); }
    long          option(Options.TimeOption type) { return options.timeOption(type); }
    string        option(Options.StringOption type){ return options.stringOption(type); }

    // Gets a network element by id name
    Node node(S)(auto ref S name){
        return cast(Node)nodeTable[name];
    }

    Link link(S)(auto ref S name){
        return cast(Link)linkTable[name];
    }

    Pattern pattern(S)(auto ref S name){
        return cast(Pattern)patternTable[name];
    }

    Curve curve(S)(auto ref S name){
        return cast(Curve)curveTable[name];
    }

    Control control(S)(auto ref S name){
        return cast(Control)controlTable[name];
    }

    // Gets a network element by index
    Node node(const int index){
        return nodes[index];
    }

    Link link(const int index){
        return links[index];
    }

    Pattern pattern(const int index){
        return patterns[index];
    }

    Curve curve(const int index){
        return curves[index];
    }

    Control control(const int index){
        return controls[index];
    }

    // Creates analysis models
    bool createHeadLossModel(){
        if ( headLossModel ) headLossModel.destroy();
        headLossModel = HeadLossModel.factory(
                option(Options.StringOption.HEADLOSS_MODEL), option(Options.ValueOption.KIN_VISCOSITY));
        if ( headLossModel is null )
        {
            throw new SystemError(SystemError.HEADLOSS_MODEL_NOT_OPENED);
        }
        return true;
    }

    bool createDemandModel(){
        if ( demandModel ) demandModel.destroy();
        demandModel = DemandModel.factory(
            option(Options.StringOption.DEMAND_MODEL), option(Options.ValueOption.PRESSURE_EXPONENT));
        if ( demandModel is null )
        {
            throw new SystemError(SystemError.DEMAND_MODEL_NOT_OPENED);
        }
        return true;
    }

    bool createLeakageModel(){
        if ( leakageModel ) leakageModel.destroy;
        if (option(Options.LEAKAGE_MODEL) == "NONE")
        {
            leakageModel = null;
            return true;
        }
        leakageModel = LeakageModel.factory(option(Options.LEAKAGE_MODEL),
                                            ucf(Units.LENGTH),
                                            ucf(Units.FLOW));
        if ( leakageModel is null)
        {
            throw new SystemError(SystemError.LEAKAGE_MODEL_NOT_OPENED);
        }
        return true;
    }

    bool createQualModel(){
        if ( qualModel ) qualModel.destroy();
        if (option(Options.QUAL_MODEL) == "NONE")
        {
            qualModel = null;
            return true;
        }
        qualModel = QualModel.factory(option(Options.QUAL_MODEL));
        if ( qualModel is null )
        {
            throw new SystemError(SystemError.QUALITY_MODEL_NOT_OPENED);
        }
        return true;
    }

    // Network graph theory operations
    Graph         graph;

    // Unit conversions
    double        ucf(Units.Quantity quantity){ return units.factor(quantity); }       //unit conversion factor
    string   getUnits(Units.Quantity quantity){ return units.name(quantity); }  //unit names
    
    void convertUnits(){
        units.setUnits(options);
        
        if(nodes.length ) foreach (node; nodes) node.convertUnits(this);
        if(links.length ) foreach (link; links) link.convertUnits(this);
        if(controls.length ) foreach (control; controls) control.convertUnits(this);
    }

    // Adds/writes network title
    void addTitleLine(string line){ title.insertBack(line); }

    void writeTitle(ref File ob){
        if ( title.length > 0 )
        {
            ob.writef("\n");
            foreach (ref s; title) 
                ob.writef("%s\n", s);
        }
    }

    // Elements of a network
    Array!string        title;         //!< descriptive title for the network
    Array!Node          nodes;         //!< collection of node objects
    Array!Link          links;         //!< collection of link objects
    Array!Curve         curves;        //!< collection of data curve objects
    Array!Pattern       patterns;      //!< collection of time pattern objects
    Array!Control       controls;      //!< collection of control rules
    Units               units;         //!< unit conversion factors
    Options             options;       //!< analysis options
    QualBalance         qualBalance;   //!< water quality mass balance
    OutBuffer           msgLog;        //!< status message log.

    // Computational sub-models
    HeadLossModel           headLossModel; //!< pipe head loss model
    DemandModel             demandModel;   //!< nodal demand model
    LeakageModel            leakageModel;  //!< pipe leakage model
    QualModel               qualModel;     //!< water quality model

package:

    // Hash tables that associate an element's ID name with its storage index.
    Element[string]      nodeTable;     //!< hash table for node ID names.
    Element[string]      linkTable;     //!< hash table for link ID names.
    Element[string]      curveTable;    //!< hash table for curve ID names.
    Element[string]      patternTable;  //!< hash table for pattern ID names.
    Element[string]      controlTable;  //!< hash table for control ID names.
    MemPool              memPool;       //!< memory pool for network objects
}
       
