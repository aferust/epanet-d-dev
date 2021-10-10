/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.models.demandmodel;

import core.stdc.math;
import std.algorithm.comparison;

import epanet.elements.junction;

//! \class DemandModel
//! \brief The interface for a pressure-dependent demand model.
//!
//! DemandModel is an abstract class from which a concrete demand
//! model is derived. Four such models are currently available -
//! Fixed, Constrained, Power, and Logistic.

class DemandModel
{
  public:
    this(){
        expon = 0.0;
    }

    this(double expon_){
        expon = expon_;
    }
    
    ~this(){}

    static  DemandModel factory(const string model, double expon_){
        if      ( model == "FIXED" )       return new FixedDemandModel();
        else if ( model == "CONSTRAINED" ) return new ConstrainedDemandModel();
        else if ( model == "POWER" )       return new PowerDemandModel(expon_);
        else if ( model == "LOGISTIC" )    return new LogisticDemandModel(expon_);
        else return null;
    }

    /// Finds demand flow and its derivative as a function of head.
    double findDemand(Junction junc, double h, ref double dqdh){
        dqdh = 0.0;
        return junc.fullDemand;
    }

    /// Changes fixed grade status depending on pressure deficit.
    bool isPressureDeficient(Junction junc) { return false; }

  protected:
    double expon;
}


//-----------------------------------------------------------------------------
//! \class  FixedDemandModel
//! \brief A demand model where demands are fixed independent of pressure.
//-----------------------------------------------------------------------------

class FixedDemandModel : DemandModel
{
  public:
    this(){
        super();
    }
}


//-----------------------------------------------------------------------------
//! \class  ConstrainedDemandModel
//! \brief A demand model where demands are reduced based on available pressure.
//-----------------------------------------------------------------------------

class ConstrainedDemandModel : DemandModel
{
  public:
    this(){
        super();
    }

    override bool isPressureDeficient(Junction junc){
        //if ( junc.fixedGrade ||
        // ... return false if normal full demand is non-positive
        if (junc.fullDemand <= 0.0 ) return false;
        double hMin = junc.elev + junc.pMin;
        if ( junc.head < hMin )
        {
            junc.fixedGrade = true;
            junc.head = hMin;
            return true;
        }
        return false;
    }

    override double findDemand(Junction junc, double p, ref double dqdh){
        dqdh = 0.0;
        return junc.actualDemand;
    }
}


//-----------------------------------------------------------------------------
//! \class  PowerDemandModel
//! \brief A demand model where demand varies as a power function of pressure.
//-----------------------------------------------------------------------------

class PowerDemandModel : DemandModel
{
  public:
    this(double expon_){
        super(expon_);
    }

    override double findDemand(Junction junc, double p, ref double dqdh){
        // ... initialize demand and demand derivative

        double qFull = junc.fullDemand;
        double q = qFull;
        dqdh = 0.0;

        // ... check for positive demand and pressure range

        double pRange = junc.pFull - junc.pMin;
        if ( qFull > 0.0 && pRange > 0.0)
        {
            // ... find fraction of full pressure met (f)

            double factor = 0.0;
            double f = (p - junc.pMin) / pRange;

            // ... apply power function

            if (f <= 0.0) factor = 0.0;
            else if (f >= 1.0) factor = 1.0;
            else
            {
                factor = pow(f, expon);
                dqdh = expon / pRange * factor / f;
            }

            // ... update total demand and its derivative

            q = qFull * factor;
            dqdh = qFull * dqdh;
        }
        return q;
    }
}


//-----------------------------------------------------------------------------
//! \class  LogisticDemandModel
//! \brief A demand model where demand is a logistic function of pressure.
//-----------------------------------------------------------------------------

class LogisticDemandModel : DemandModel
{
  public:
    this(double expon_){
        super(expon_);
        a = 0.0;
        b = 0.0;
    }

    override double findDemand(Junction junc, double p, ref double dqdh){
        double f = 1.0;              // fraction of full demand
        double q = junc.fullDemand; // demand flow (cfs)
        double arg;                  // argument of exponential term
        double dfdh;                 // gradient of f w.r.t. pressure head

        // ... initialize derivative

        dqdh = 0.0;

        // ... check for positive demand and pressure range

        if ( junc.fullDemand > 0.0 && junc.pFull > junc.pMin )
        {
            // ... find logistic function coeffs. a & b

            setCoeffs(junc.pMin, junc.pFull);

            // ... prevent against numerical over/underflow

            arg = a + b*p;
            if (arg < -100.) arg = -100.0;
            else if (arg > 100.0) arg = 100.0;

            // ... find fraction of full demand (f) and its derivative (dfdh)

            f = exp(arg);
            f = f / (1.0 + f);
            f = max(0.0, min(1.0, f));
            dfdh = b * f * (1.0 - f);

            // ... evaluate demand and its derivative

            q = junc.fullDemand * f;
            dqdh = junc.fullDemand * dfdh;
        }
        return q;
    }

  private:
    double a, b;  // logistic function coefficients
    
    void  setCoeffs(double pMin, double pFull){
        // ... computes logistic function coefficients
        //     assuming 99.9% of full demand at full pressure
        //     and 1% of full demand at minimum pressure.

        double pRange = pFull - pMin;
        a = (-4.595 * pFull - 6.907 * pMin) / pRange;
        b = 11.502 / pRange;
    }
}