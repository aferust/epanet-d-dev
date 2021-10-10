/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.pattern;

import epanet.elements.element;

import std.container.array: Array;

//class MemPool;

//! \class Pattern
//! \brief A set of multiplier factors associated with points in time.
//!
//! Time patterns are multipliers used to adjust nodal demands,
//! pump/valve settings, or water quality source inputs over time.
//! Pattern is an abstract class from which the FixedPattern and
//! VariablePattern classes are derived.

class Pattern: Element
{
  public:

    enum {FIXED_PATTERN, VARIABLE_PATTERN} // PatternType

    // Constructor/Destructor
    this(string name_, int type_){
        super(name_);
        type = type_;
        currentIndex = 0;
        interval = 0;
    }

    ~this(){
        factors.clear();
    }

    // Pattern factory
    static  Pattern factory(int type_, string name_/*, MemPool* memPool*/){
        switch ( type_ )
        {
        case FIXED_PATTERN:
            return new FixedPattern(name_);
        case VARIABLE_PATTERN:
            return new VariablePattern(name_);
        default:
            return null;
        }
    }

    // Methods
    void           setTimeInterval(int t) { interval = t; }
    void           addFactor(double f) { factors.insertBack(f); }
    int            timeInterval() { return interval; }
    int            size() { return cast(int)factors.length; }
    double         factor(int i) { return factors[i]; }
    
    double         currentFactor(){
        if ( factors.length == 0 ) return 1.0;
        return factors[currentIndex];
    }

    void   init_(int intrvl, int tstart){}
    int    nextTime(int t){return 0;}
    void   advance(int t){}

    // Properties
    int            type;                //!< type of time pattern

    Array!double        factors;        //!< sequence of multiplier factors
    int                 currentIndex;   //!< index of current pattern interval
    int                 interval;       //!< fixed time interval (sec)
}

//------------------------------------------------------------------------------

//! \class FixedPattern
//! \brief A Pattern where factors change at fixed time intervals.
//! \note A fixed pattern wraps around once time exceeds the period
//!       associated with the last multiplier factor supplied.

class FixedPattern : Pattern
{
  public:

    // Constructor/Destructor
    this(string name_){
        super(name_, FIXED_PATTERN),
        startTime = 0;
    }
    ~this(){}

    // Methods
    override void init_(int intrvl, int tStart){
        startTime = tStart;
        if ( interval == 0 ) interval = intrvl;
        if ( factors.length == 0 ) factors.insertBack(1.0);
        int nPeriods = cast(int)factors.length;
        if ( interval > 0 )
        {
            currentIndex = (startTime/interval) % nPeriods;
        }
    }

    override int nextTime(int t){
        int nPeriods = (startTime + t) / interval;
        return (nPeriods + 1) * interval;
    }

    override void advance(int t){
        int nPeriods = (startTime + t) / interval;
        currentIndex = cast(int)(nPeriods % factors.length);
    }

  private:
    int    startTime;   //!< offset from time 0 when the pattern begins (sec)
}

//------------------------------------------------------------------------------

//! \class VariablePattern
//! \brief A Pattern where factors change at varying time intervals.
//! \note When time exceeds the last time interval of a variable pattern
//!       the multiplier factor remains constant at its last value.

class VariablePattern : Pattern
{
  public:

    // Constructor/Destructor
    this(string name_){
        super(name_, VARIABLE_PATTERN);
    }

    ~this(){
        times.clear();
    }

    // Methods
    void addTime(int t) { times.insertBack(t); }

    int time(int i) { return times[i]; }

    override void init_(int intrvl, int tstart){
        if ( factors.length == 0 )
        {
            factors.insertBack(1.0);
            times.insertBack(0);
        }
        currentIndex = 0;
    }

    override int nextTime(int t){
        if ( currentIndex == cast(int)times.length-1 )
        {
            return int.max;
        }

        return times[currentIndex + 1];
    }

    override void advance(int t){
        for (uint i = currentIndex+1; i < times.length; i++)
        {
            if ( t < times[i] )
            {
                currentIndex = i-1;
                return;
            }
        }
        currentIndex = cast(int)times.length - 1;
    }

  private:
    Array!int   times;  //!< times (sec) at which factors change
    
}