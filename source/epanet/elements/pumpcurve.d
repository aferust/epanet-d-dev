/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.elements.pumpcurve;

import core.stdc.math;
import std.algorithm.comparison;

import epanet.core.network;
import epanet.elements.curve;
import epanet.core.network;
import epanet.core.units;
import epanet.core.error;

//-----------------------------------------------------------------------------

enum BIG_NUMBER = 1.0e10;      //!< numerical infinity
enum TINY_NUMBER = 1.0e-6;     //!< numerical zero

//-----------------------------------------------------------------------------

//! \class PumpCurve
//! \brief Describes how head varies with flow for a Pump link.

class PumpCurve
{
  public:

    enum  { //PumpCurveType
        NO_CURVE,              //!< no curve assigned
        CONST_HP,              //!< constant horsepower curve
        POWER_FUNC,            //!< power function curve
        CUSTOM                 //!< user-defined custom curve
    }

    // Constructor/Destructor
    this(){
        curveType = NO_CURVE;
        curve = null;
        horsepower = 0.0;
        qInit = 0.0;
        qMax = 0.0;
        hMax = 0.0;
        h0 = 0.0;
        r = 0.0;
        n = 0.0;
        qUcf = 1.0;
        hUcf = 1.0;
    }
    ~this(){}

    // Methods
    void setCurve(Curve c){
        curve = c;
    }

    int setupCurve(Network network){
        int err = 0;

        // ... assign unit conversion factors

        qUcf = network.ucf(Units.FLOW);
        hUcf = network.ucf(Units.LENGTH);

        // ... constant HP pump

        if (horsepower > 0.0 && curve is null)
        {
            setupConstHpCurve();
        }

        // ... a pump curve was supplied

        else if (curve !is null) {

            // ... power curve supplied
            if (curve.size() == 1 ||
                (curve.size() == 3 && curve.x(0) == 0.0) )
            {
                err = setupPowerFuncCurve();
            }

            // ... custom curve supplied
            else err = setupCustomCurve();
        }

        // ... error - no curve was supplied

        else err = NetworkError.NO_PUMP_CURVE;
        qInit /= qUcf;
        return err;
    }

    void findHeadLoss(
               double speed, double flow, ref double headLoss, ref double gradient){
        
        import std.math: abs;

        double q = abs(flow);
        switch (curveType)
        {
        case CUSTOM:
            customCurveHeadLoss(speed, q, headLoss, gradient); break;

        case CONST_HP:
            constHpHeadLoss(speed, q, headLoss, gradient); break;

        case POWER_FUNC:
            powerFuncHeadLoss(speed, q, headLoss, gradient); break;
        default: break;
        }
    }
    
    bool   isConstHP() {return curveType == CONST_HP;}

    // Properties
    int    curveType;      //!< type of pump curve
    Curve  curve;          //!< curve with head v. flow data
    double horsepower;     //!< pump's horsepower
    double qInit;          //!< initial flow (cfs)
    double qMax;           //!< maximum flow (cfs)
    double hMax;           //!< maximum head (ft)

  private:

    double h0;             //!< shutoff head (ft)
    double r;              //!< flow coefficient for power function curve
    double n;              //!< flow exponent for power function curve
    double qUcf;           //!< flow units conversion factor
    double hUcf;           //!< head units conversion factor

    void setupConstHpCurve(){
        curveType = CONST_HP;

        // ... Pump curve coefficients (head = h0 + r*flow^n)

        h0 = 0.0;
        r  = -8.814 * horsepower;
        n  = -1.0;

        // ... unit conversion factors

        qUcf = 1.0;
        hUcf = 1.0;

        // ... pump curve limits

        hMax  = BIG_NUMBER;         // No head limit
        qMax  = BIG_NUMBER;         // No flow limit
        qInit = 1.0;                // Init. flow = 1 cfs
    }

    int setupPowerFuncCurve(){
        // ... declare control points

        double h1, h2, q1, q2;

        // ... 1-point pump curve - fill in shutoff head & max. flow

        if (curve.size() == 1)
        {
            curveType = POWER_FUNC;
            q1 = curve.x(0);
            h1 = curve.y(0);
            h0 = 1.33334 * h1;
            q2 = 2.0 * q1;
            h2 = 0.0;
        }

        // ... 3-point pump curve with shutoff head

        else if (curve.size() == 3 && curve.x(0) == 0.0)
        {
            curveType = POWER_FUNC;
            h0 = curve.y(0);
            q1 = curve.x(1);
            h1 = curve.y(1);
            q2 = curve.x(2);
            h2 = curve.y(2);
        }

        else return NetworkError.INVALID_PUMP_CURVE;

        // ... check for valid control points

        if (  h0      < TINY_NUMBER ||
            h0 - h1 < TINY_NUMBER ||
            h1 - h2 < TINY_NUMBER ||
            q1      < TINY_NUMBER ||
            q2 - q1 < TINY_NUMBER
            ) return NetworkError.INVALID_PUMP_CURVE;

        // ... find curve coeffs. from control points

        double h4 = h0 - h1;
        double h5 = h0 - h2;
        n = log(h5/h4) / log(q2/q1);
        if (n <= 0.0 || n > 20.0) return NetworkError.INVALID_PUMP_CURVE;
        r = -h4 / pow(q1, n);
        if (r >= 0.0) return NetworkError.INVALID_PUMP_CURVE;

        // ... assign pump curve limits

        hMax = h0;
        qMax = pow(-h0/r, 1.0/n);
        qInit = q1;
        return 0;
    }

    int setupCustomCurve(){
        // ... check that head (y) decreases with increasing flow (x)

        for (int m = 1; m < curve.size(); m++)
        {
            if (curve.y(m-1) - curve.y(m) < TINY_NUMBER || curve.y(m) < 0.0)
            {
                return NetworkError.INVALID_PUMP_CURVE;
            }
        }

        // ... extrapolate to zero flow to find shutoff head

        double slope = (curve.y(0) - curve.y(1)) /
                    (curve.x(1) - curve.x(0));
        hMax = curve.y(0) + slope * curve.x(0);

        // ... extrapolate to zero head to find max. flow

        int k = curve.size() - 1;
        slope = (curve.x(k) - curve.x(k-1)) /
                (curve.y(k-1) - curve.y(k));
        qMax  = curve.x(k) + slope * curve.y(k);

        // ... curve exponent is 1 (curve is piece-wise linear)

        n = 1.0;

        // ... initial flow is curve mid-point

        qInit = (curve.x(0) + curve.x(k)) / 2.0;
        curveType = CUSTOM;
        return 0;
    }

    void constHpHeadLoss(
               double speed, double flow, ref double headLoss, ref double gradient)
    {
        import std.math: abs;

        double w = speed * speed * r;
        double q = max(flow, 1.0e-6);
        headLoss = w / q;
        gradient = abs(headLoss / q);
    }

    void powerFuncHeadLoss(
               double speed, double flow, ref double headLoss, ref double gradient)
    {
        // ... convert flow to pump curve units
        import std.math: abs;

        double q = abs(flow) * qUcf;

        // ... adjust curve coeffs. for pump speed

        double h01 = h0;
        double r1 = r;
        double w = 1.0;
        if (speed != 1.0)
        {
            w = speed * speed;
            h01 *= w;
            w = w / pow(speed, n);
        }

        // ... evaluate head loss (negative of pump head) and its gradient

        r1 = w * r * pow(q, n);
        headLoss = -(h01 + r1);
        gradient = -(n * r1 / q);

        // ... convert results to internal units

        headLoss /= hUcf;
        gradient *= qUcf / hUcf;
    }

    void customCurveHeadLoss(
               double speed, double flow, ref double headLoss, ref double gradient){
        // ... convert flow value to pump curve units
        import std.math: abs;
        
        double q = abs(flow) * qUcf;

        // ... find slope and intercept of curve segment

        curve.findSegment(q / speed, r, h0);

        // ... adjust slope and intercept for pump speed

        h0 = h0 * speed * speed;
        r = r * speed;

        // ... evaluate head loss (negative of pump head) and its gradient

        headLoss = -(h0 + r*q);
        gradient = -r;

        // ... convert results to internal units

        headLoss /= hUcf;
        gradient *= qUcf / hUcf;
    }
}