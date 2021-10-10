/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.element;

class Element
{
    //@disable this();
    
public:

    enum {NODE, LINK, PATTERN, CURVE, CONTROL}; // ElementType
    alias ElementType = int;

    this(string name_){
        name = name_;
        index = -1;
    }

    ~this(){}
    //virtual ~Element() = 0;

    string name;       //!< element's ID name
    int index;      //!< index in array of elements
}