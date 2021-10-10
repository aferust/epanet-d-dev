/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.utilities.graph;

import std.container.array: Array;

import epanet.core.network;
import epanet.elements.element;
import epanet.elements.link;
import epanet.utilities.utilities: get = listGet, set = listSet;

class Graph
{
  public:

    this(){}
    ~this(){}

    void createAdjLists(Network nw){
        try
        {
            int nodeCount = nw.count(Element.NODE);
            int linkCount = nw.count(Element.LINK);

            int[] valsadj; valsadj.length = 2*linkCount; valsadj[] = -1;
            adjLists.insertBack(valsadj);

            int[] valsbeg; valsbeg.length = nodeCount+1; valsbeg[] = 0;
            adjListBeg.insertBack(valsbeg);

            Array!int degree; degree.length = nodeCount;
            foreach(Link link; nw.links)
            {
                degree[link.fromNode.index]++;
                degree[link.toNode.index]++;
            }
            adjListBeg.set(0, 0);
            for (int i = 0; i < nodeCount; i++)
            {
                adjListBeg.set(i+1, adjListBeg.get(i) + degree[i]);
                degree[i] = 0;
            }

            int m;
            for (int k = 0; k < linkCount; k++)
            {
                int i = nw.link(k).fromNode.index;
                m = adjListBeg.get(i) + degree[i];
                adjLists.set(m, k);
                degree[i]++;
                int j = nw.link(k).toNode.index;
                m = adjListBeg.get(j) + degree[j];
                adjLists.set(m, k);
                degree[j]++;
            }
        }
        catch (Exception e)
        {
            throw new Exception("You shall not pass.");
        }
    }

  private:
    Array!int adjLists;        // packed nodal adjacency lists
    Array!int adjListBeg;      // starting index of each node's list
}