/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */

module epanet.cli.main;

//! \file main.cpp
//! \brief The main function used to run EPANET from the command line.

import std.stdio;
import std.string: toStringz;

import epanet.epanet3;

int main(string[] args)
{
    //... check number of command line arguments
    if (args.length < 3)
    {
        write("\nCorrect syntax is: epanet3 inpFile rptFile (outFile)\n");
        return 0;
    }

    //... retrieve file names from command line
    string f1 = args[1];
    string f2 = args[2];
    string f3 = "";
    if (args.length > 3) f3 = args[3];

    // ... run a full EPANET analysis
    EN_runEpanet(f1.toStringz, f2.toStringz, f3.toStringz);
    //system("PAUSE");
    return 0;
}