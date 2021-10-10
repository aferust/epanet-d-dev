/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
 
module epanet.input.inputreader;

import std.exception: assumeUnique;
import std.stdio;
import std.typecons: scoped;
import std.string: chomp;
import std.uni : isWhite;
import std.array : split;

import epanet.core.network;
import epanet.core.error;
import epanet.input.inputparser;
import epanet.utilities.utilities;

enum    MAXERRS = 10;             // maximum number of input errors allowed
// enum    WHITESPACE = " \t\n\r";   // whitespace characters

string[32] sections =
[
    "[TITLE",           "[JUNCTION",        "[RESERVOIR",       "[TANK",
    "[PIPES",            "[PUMP",            "[VALVE",           "[PATTERN",
    "[CURVE",           "[CONTROL",         "[RULE",            "[EMITTER",
    "[DEMAND",          "[STATUS",          "[ROUGHNESS",       "[LEAKAGE",
    "[ENERGY",          "[QUALITY",         "[SOURCE",          "[REACTION",
    "[MIXING",          "[OPTION",          "[TIME",            "[REPORT",
    "[COORD",           "[VERTICES",        "[LABEL",           "[MAP",
    "[BACKDROP",        "[TAG",             "[END",             null
];

//! \class InputReader
//! \brief Reads lines of project input data from a text file.
//!
//! The reader makes two passes through the project's input file - once using the
//! ObjectParser to identify and create each element (node, link, pattern, etc.)
//! in the network and then using the PropertyParser to read the properties
//! assigned to each of these elements. This two-pass approach allows the
//! description of the elements to appear in any order in the file.

class InputReader
{
  public:

    enum { // Section
        TITLE,              JUNCTION,           RESERVOIR,          TANK,
        PIPE,               PUMP,               VALVE,              PATTERN,
        CURVE,              CONTROL,            RULE,               EMITTER,
        DEMAND,             STATUS,             ROUGHNESS,          LEAKAGE,
        ENERGY,             QUALITY,            SOURCE,             REACTION,
        MIXING,             OPTION,             TIME,               REPORT,
        COORD,              VERTICES,           LABEL,              MAP,
        BACKDROP,           TAG,                END
    }
    alias Section = int;

    this(){
        errcount = 0;
        section = -1;
    }

    ~this() {}

    void readFile(string inpFile, Network network){
        // ... initialize current input section
        
        section = -1;

        // ... open the input file

        auto fin = File(inpFile, "r");
        
        if (!fin.isOpen()) throw new FileError(FileError.CANNOT_OPEN_INPUT_FILE);
        try
        {
            // ... parse object names from the file
            auto objectParser = scoped!ObjectParser(network);
            parseFile(fin, objectParser);
            
            // ... parse object properties from the file
            auto propertyParser = scoped!PropertyParser(network);
            parseFile(fin, propertyParser); 
            
            fin.close();
        }

        // ... catch and re-throw any exception thrown by the parsing process

        catch (Exception e)
        {
            fin.close();
            throw e;
        }
    }

  protected:

    string sin;                     //!< string stream containing a line of input
    int                errcount;    //!< error count
    int                section;     //!< file section being processed

    void parseFile(ref File fin, InputParser parser){
        import std.array : array; import std.range;

        string token;

        // ... reset input file
        
        fin.seek(0);
        section = -1;

        // ... read each line from input file
        //auto range = fin.byLine(); // returns 
        
        while (!fin.eof)
        {
            char[] _line;
            fin.readln(_line);
            _line = chomp(_line);
            if(!_line.length) continue;

            if ( errcount >= MAXERRS ) break;

            // ... remove any comment from input line
            string line = assumeUnique(_line);
            
            if (isCommentLine(line))
                continue;
            
            try
            {
                // ... see if at start of new input section
                
                if ( !line.empty && line[0]== '[' ){ 
                    
                    findSection(line);
                    
                    // ... otherwise parse input line of data
                }
                else {parser.parseLine(line, section);}
            }
            catch (InputError e)
            {
                errcount++;
                if ( section >= 0 )
                {
                    parser.network.msgLog.writef("%s at following line of %s] section:\n", e.msg, sections[section]);
                }
                else
                {
                    parser.network.msgLog.writef("%s at following line of file:\n", e.msg);
                }
                parser.network.msgLog.writef("%s\n", line);
            }
            catch (Exception e)
            {
                debug writefln("%s : %s - %d", e.msg, e.file, e.line);
                errcount++;
            }
        }

        // ... throw general input file exception if errors were found

        if ( errcount > 0 ) throw new InputError(InputError.ERRORS_IN_INPUT_DATA, "");
    }

    bool isCommentLine(ref string line){
        import std.string: indexOf, strip;

        // ... skip any characters following a ';'
        auto ind = indexOf(line, ';');
        if ( ind == 0) {
            // some comment found
            return true;
        }else if (ind > 0){
            line = line[0..ind];
            line = line.strip;
            return false;
        }else
            return false;
    }

    void findSection(ref string token){
        int newSection = Utilities.findMatch(token, sections);
        if (newSection < 0) throw new InputError(InputError.INVALID_KEYWORD, token);
        section = newSection;
    }
}