/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.utilities.utilities;

import std.algorithm.comparison: equal;

enum s_Day     = "DAY";
enum s_Hour    = "HOUR";
enum  s_Minute = "MIN";
enum  s_Second = "SEC";
enum  s_AM     = "AM";
enum  s_PM     = "PM";

class Utilities
{

    static bool getTmpFileName(ref string fname)
    {
        version(Windows){
            import core.sys.windows.windows : GetTempFileNameW, MAX_PATH;
            import core.stdc.wchar_ : wcslen;
            import std.windows.syserror : wenforce;
            import std.file: tempDir;
            import std.path: dirSeparator;
            import std.conv : text, wtext;

            wchar[] path = new wchar[MAX_PATH+1];
            string dir = tempDir();
            int rtnValue = GetTempFileNameW(dir.wtext.ptr, ("EN"w).ptr, 0, path.ptr);
            if ( rtnValue > 0 ) fname = path[0 .. wcslen(path.ptr)].text;
            else return false;
        } else {
            import std.conv: to;
            import core.sys.posix.stdlib: mkstemp;

            char[] tmpName = "/tmp/epanetXXXXXX\0".dup;
            const fd = mkstemp(tmpName.ptr);
            if ( fd == -1 ) return false;
            fname = tmpName.to!string;
        }

        return true;
    }

    static int findFullMatch(S)(auto ref S s, S[] slist)
    {
        foreach (i, ref item; slist)
        {
            if (s == item) return cast(int)i;
        }
        return -1;
    }

    static string upperCase(S)(auto ref S s)
    {
        import std.ascii: toUpper;

        string s1;
        foreach(ref c; s)
            s1 ~= toUpper(c);
        return s1;
    }

    static string getTime(long seconds){
        import std.format;
        
        int t = cast(int)seconds;
        int hours = t / 3600;
        t = t - 3600*hours;
        int minutes = t / 60;
        seconds = t - 60*minutes;
        
        return format("%d:%02d:%02d", hours, minutes, seconds);
    }

    static int sign(double x)
    { return (x < 0 ? -1 : 1); }

    //-----------------------------------------------------------------------------
    //  Sees if string s1 matches the first part of s2 - case insensitive
    //-----------------------------------------------------------------------------
    static bool match(S)(auto ref S s1, auto ref S s2)
    {
        import std.uni: toUpper;
        
        foreach (i, ref e2; s2 )
        {
            // compare upper-case characters
            auto e1 = s1[i];
            if ( toUpper(e1) != toUpper(e2)) return false;
        }
        return true;
    }

    static bool parseNumber(S, T)(auto ref S str, ref T x){
        import std.conv;

        try{
            x = str.to!T;
        }catch (ConvOverflowException e){
            return false;
        }

        return true;
    }

    static int findMatch(S)(auto ref S s, S[] slist)
    {
        int i = 0;
        while (slist[i])
        {
            if ( match(s, slist[i]) ) return i;
            i++;
        }
        return -1;
    }

    static int getSeconds(S)(auto ref S strTime, auto ref S strUnits)
    {
        import std.string: indexOf, toStringz;
        import core.stdc.stdio;
        // see if time is in military hr:min:sec format

        if ( indexOf(strTime, ':') != -1)
        {
            int h = 0, m = 0, s = 0;
            if (sscanf(strTime.toStringz, "%d:%d:%d", &h, &m, &s) == 0) return -1;

            if (strUnits.length > 0)
            {
                if (match(strUnits, s_AM))
                {
                    if (h >= 13) return -1;
                    if (h == 12) h -= 12;
                }
                else if (match(strUnits, s_PM))
                {
                    if (h >= 13) return -1;
                    if (h < 12)  h += 12;
                }
                else
                {
                    return -1;
                }
            }

            return 3600*h + 60*m + s;
        }

        // retrieve time as a decimal number

        double t;
        if (!parseNumber(strTime, t)) return -1;

        // if no units supplied then convert time in hours to seconds

        if (strUnits.length == 0) return cast(int) (3600. * t);

        // determine time units and convert time accordingly

        if (match(strUnits, s_Day))    return cast(int) (3600. * 24. * t);
        if (match(strUnits, s_Hour))   return cast(int) (3600. * t);
        if (match(strUnits, s_Minute)) return cast(int) (60. * t);
        if (match(strUnits, s_Second)) return cast(int) t;

        // if AM/PM supplied, time is in hours and adjust it accordingly

        if (match(strUnits, s_AM))
        {
            if (t >= 13.0) return -1;
            if (t >= 12.0) t -= 12.0;
        }
        else if (match(strUnits, s_PM))
        {
        if (t >= 13.0) return -1;
        if (t < 12.0)  t += 12.0;
        }
        else return -1;

        // convert time from hours to seconds

        return cast(int) (3600 * t);
    }

    static void split(Arr, S)(ref Arr tokens, auto ref S str)
    {
        string token;
        for (int i = 0; i < str.length; i++)
        {
            if (str[i] == ' ' || str[i] == '\t')
            {
                if (!token.length == 0)
                {
                    tokens.insertBack(token);
                    token = "";
                }
                continue;
            }
            else {
                token ~= str[i];
            }
        }

        if (!token.length == 0)
        {
            tokens.insertBack(token);
            token = "";
        }
    }

    static string getFileName(S)(auto ref S s){
        import std.path: baseName;

        return baseName(s);
    }
}

void listSet(L, V)(L list, size_t index, V value){
    int i;
    foreach(ref item; list[]){
        if(i == index){
            item = value;
            return;
        }
    	i++;
    }
}

template listGet(L){
    import std.traits : TemplateArgsOf;
    alias ASeq = TemplateArgsOf!L;
    alias V = ASeq[0];
    auto listGet(L list, size_t index){
        int i;
        foreach(ref item; list[]){
            if(i == index)
                return item;
            i++;
        }
        // assert ?
        return V.init;
    }
}
