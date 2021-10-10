/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.utilities.segpool;

import epanet.utilities.mempool;

struct  Segment              //!< Volume segment
{
   double  v;                //!< volume (ft3)
   double  c;                //!< constituent concentration (mass/ft3)
   Segment* next;           //!< next upstream volume segment
}

class SegPool
{
  public:

    this(){
        memPool = new MemPool();
        freeSeg = null;
        segCount = 0;
    }

    ~this(){
        memPool.destroy();
    }

    void init_(){
        segCount = 0;
        memPool.reset();
        freeSeg = null;
    }

    Segment* getSegment(double v, double c){
        // ... if there's a free segment available then use it
        Segment* seg;
        if ( freeSeg )
        {
            seg = freeSeg;
            freeSeg = seg.next;
        }

        // ... otherwise create a new one from the memory pool
        else
        {
            seg = cast(Segment*) memPool.alloc(Segment.sizeof);
            segCount++;
        }

        // ... assign segment's volume and quality
        if ( seg )
        {
            seg.v = v;
            seg.c = c;
            seg.next = null;
        }
        return seg;
    }

    void freeSegment(Segment* seg){
        seg.next = freeSeg;
        freeSeg = seg;
    }

  private:
	int        segCount;     // number of volume segments allocated
	Segment*   freeSeg;      // first unused segment
	MemPool    memPool;      // memory pool for volume segments
}