/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.output.reportfields;

import epanet.elements.element;

struct Field
{
    string name;
    string units;
    bool        enabled;
    int         precision;
    double      lowerLimit;
    double      upperLimit;
}


class ReportFields
{
  public:
    enum {ELEVATION, HEAD, PRESSURE, DEMAND, DEFICIT, OUTFLOW,
                        NODE_QUALITY, NUM_NODE_FIELDS} // NodeFieldType
    enum {LENGTH, DIAMETER, FLOW, LEAKAGE, VELOCITY, HEADLOSS, STATUS,
                        SETTING, LINK_QUALITY, NUM_LINK_FIELDS} // LinkFieldType

    static string[8] NodeFieldNames = ["Elevation", "Head", "Pressure", "Demand",
        "Deficit", "Outflow", "Quality", null];
    static string[10] LinkFieldNames = ["Length", "Diameter", "Flow Rate", "Leakage",
        "Velocity", "Head Loss", "Status", "Setting", "Quality", null];

    this(){
        setDefaults();
    }
    void setDefaults(){
        for (int i = 0; i < NUM_NODE_FIELDS; i++)
        {
            nodeFields[i].name = NodeFieldNames[i];
            nodeFields[i].precision = 3;
            nodeFields[i].lowerLimit = double.min_normal;
            nodeFields[i].upperLimit = double.max;
        }
        for (int i = 0; i < NUM_LINK_FIELDS; i++)
        {
            linkFields[i].name = LinkFieldNames[i];
            linkFields[i].precision = 3;
            linkFields[i].lowerLimit = double.min_normal;
            linkFields[i].upperLimit = double.max;
        }
    }
    void setField(int    type,
                            int    index,
                            int    enabled,
                            int    precision,
                            double lowerLimit,
                            double upperLimit)
    {
        Field* field;
        if ( type == Element.NODE )
        {
            if ( index < 0 || index >= NUM_NODE_FIELDS ) return;
            field = &nodeFields[index];
        }
        else if ( type == Element.LINK )
        {
            if ( index < 0 || index >= NUM_LINK_FIELDS ) return;
            field = &linkFields[index];
        }
        else return;
        if ( enabled >= 0 ) field.enabled = cast(bool)enabled;
        if ( precision >= 0 ) field.precision = precision;
        if ( lowerLimit >= 0.0 ) field.lowerLimit = lowerLimit;
        if ( upperLimit >= 0.0 ) field.upperLimit = upperLimit;
    }
    ref Field nodeField(int index) { return nodeFields[index]; }
    ref Field linkField(int index) { return linkFields[index]; }

  private:
    Field[NUM_NODE_FIELDS] nodeFields;
    Field[NUM_LINK_FIELDS] linkFields;
}
