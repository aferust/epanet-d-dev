/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.output.projectwriter;

import core.stdc.math: pow;
import std.stdio, std.format, std.string;

import epanet.core.error;
import epanet.core.network;
import epanet.core.units;
import epanet.core.options;
import epanet.elements.node;
import epanet.elements.junction;
import epanet.elements.reservoir;
import epanet.elements.tank;
import epanet.elements.pipe;
import epanet.elements.link;
import epanet.elements.pump;
import epanet.elements.pumpcurve;
import epanet.elements.valve;
import epanet.elements.demand;
import epanet.elements.emitter;
import epanet.elements.pattern;
import epanet.elements.curve;
import epanet.elements.control;
import epanet.elements.qualsource;
import epanet.models.tankmixmodel;
import epanet.utilities.utilities;

//! \class ProjectWriter
//! \brief The ProjectWriter class writes a project's data to file.

class ProjectWriter
{
  public:
    this(){
        network = null;
    }

    ~this(){}

    int writeFile(string fname, Network nw){
        if (nw is null) return 0;
        network = nw;

        fout.open(fname, "w");
        if (!fout.isOpen()) return FileError.CANNOT_OPEN_INPUT_FILE;

        writeTitle();
        writeJunctions();
        writeReservoirs();
        writeTanks();
        writePipes();
        writePumps();
        writeValves();
        writeDemands();
        writeEmitters();
        writeStatus();
        writePatterns();
        writeCurves();
        writeControls();
        writeEnergy();
        writeQuality();
        writeSources();
        writeMixing();
        writeReactions();
        writeOptions();
        writeTimes();
        writeReport();
        writeTags();
        writeCoords();
        writeAuxData();
        fout.close();
        return 0;
    }

  private:
    void writeTitle(){
        fout.writeln("[TITLE]");
        network.writeTitle(fout);
    }

    void writeJunctions(){
        fout.write("\n[JUNCTIONS]\n");
        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.JUNCTION )
            {
                auto junc = cast(Junction)node;
                
                string name = leftJustify(node.name, 16, ' ');
                immutable en = leftJustify(format("%.4f", node.elev*network.ucf(Units.LENGTH)), 12, ' ');
                

                string tw = name ~ en;
                
                
                if (network.option(Options.DEMAND_MODEL) != "FIXED" )
                {
                    string blank = "*     *    ";
                    double pUcf = network.ucf(Units.PRESSURE);
                    
                    string tw2 = tw ~ blank ~ leftJustify(format("%.4f", junc.pMin * pUcf), 12, ' ') ~
                            leftJustify(format("%.4f", junc.pFull * pUcf), 12, ' ');
                    
                    fout.writef("%s\n", tw2);
                }else
                    fout.writef("%s\n", tw);
            }
        }
    }

    void writeReservoirs(){
        fout.write("\n[RESERVOIRS]\n");
        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.RESERVOIR )
            {
                Reservoir resv = cast(Reservoir)node;
                string name = leftJustify(node.name, 16, ' ');

                string tmp = name ~ format("%.4f", node.elev*network.ucf(Units.LENGTH)).leftJustify(12, ' ');
                if ( resv.headPattern )
                {
                    tmp ~= resv.headPattern.name;
                }
                fout.writef("%s\n", tmp.strip);
            }
        }
    }

    void writeTanks(){
        fout.write("\n[TANKS]\n");
        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.TANK )
            {
                Tank tank = cast(Tank)node;
                double ucfLength = network.ucf(Units.LENGTH);

                string name = leftJustify(node.name, 16, ' ');

                string tmp = name ~
                    leftJustify(format("%.4f", node.elev * ucfLength), 12, ' ') ~
                    leftJustify(format("%.4f", (tank.initHead - node.elev) * ucfLength), 12, ' ') ~
                    leftJustify(format("%.4f", (tank.minHead - node.elev) * ucfLength), 12, ' ') ~
                    leftJustify(format("%.4f", (tank.maxHead - node.elev) * ucfLength), 12, ' ') ~
                    leftJustify(format("%.4f", tank.diameter * ucfLength), 12, ' ') ~
                    leftJustify(format("%.4f", tank.minVolume * network.ucf(Units.VOLUME)), 12, ' ');
                
                if ( tank.volCurve ) tmp ~= tank.volCurve.name;
                fout.writef("%s\n", tmp.strip);
            }
        }
    }
    
    void writePipes(){
        fout.write("\n[PIPES]\n");
        foreach (Link link; network.links)
        {
            if ( link.type() == Link.PIPE )
            {
                Pipe pipe = cast(Pipe)link;
                string name = leftJustify(link.name, 16, ' ');
                string tmp = name ~
                    leftJustify(link.fromNode.name, 16, ' ') ~
                    leftJustify(link.toNode.name, 16, ' ') ~
                    leftJustify(format("%.4f", pipe.length * network.ucf(Units.LENGTH)), 12, ' ') ~
                    leftJustify(format("%.4f", pipe.diameter * network.ucf(Units.DIAMETER)), 12, ' ');

                double r = pipe.roughness;
                if ( network.option(Options.HEADLOSS_MODEL ) == "D-W")
                {
                    r = r * network.ucf(Units.LENGTH) * 1000.0;
                }
                tmp ~= leftJustify(format("%.4f", r), 12, ' ') ~ leftJustify(format("%.4f", pipe.lossCoeff), 12, ' ');
                if (pipe.hasCheckValve) tmp ~= "CV\n";
                else if ( link.initStatus == Link.LINK_CLOSED ) tmp ~= "CLOSED\n";
                else tmp ~="\n";
                fout.writef("%s", tmp);
            }
        }
    }

    void writePumps(){
        fout.write("\n[PUMPS]\n");
        foreach (Link link; network.links)
        {
            if ( link.type() == Link.PUMP )
            {
                Pump pump = cast(Pump)link;
                string tmp =
                    leftJustify(link.name, 16, ' ') ~
                    leftJustify(link.fromNode.name, 16, ' ') ~
                    leftJustify(link.toNode.name, 16, ' ');

                if ( pump.pumpCurve.horsepower > 0.0 )
                {
                    tmp ~= leftJustify("POWER", 8, ' ') ~
                           leftJustify(format("%.4f", pump.pumpCurve.horsepower * network.ucf(Units.POWER)), 12, ' ');
                }

                if ( pump.pumpCurve.curveType != PumpCurve.NO_CURVE )
                {
                    tmp ~= leftJustify("HEAD", 8, ' ') ~ 
                           leftJustify(pump.pumpCurve.curve.name, 16, ' ');
                }

                if ( pump.speed > 0.0 && pump.speed != 1.0 )
                {
                    tmp ~= leftJustify("SPEED", 8, ' ') ~
                           leftJustify(format("%.4f", pump.speed), 8, ' ');
                }

                if ( pump.speedPattern )
                {
                    tmp ~= leftJustify("PATTERN", 8, ' ') ~
                           leftJustify(pump.speedPattern.name, 16, ' ');
                }
                fout.writef("%s\n", tmp.strip);
            }
        }
    }

    void writeValves(){
        fout.write("\n[VALVES]\n");
        foreach (Link link; network.links)
        {
            if ( link.type() == Link.VALVE )
            {
                Valve valve = cast(Valve)link;
                string tmp =
                    leftJustify(link.name, 16, ' ') ~
                    leftJustify(link.fromNode.name, 16, ' ') ~
                    leftJustify(link.toNode.name, 16, ' ') ~

                    leftJustify(format("%.4f", valve.diameter*network.ucf(Units.DIAMETER)), 12, ' ') ~
                    leftJustify(Valve.ValveTypeWords[cast(size_t)valve.valveType], 8, ' ');

                if (valve.valveType == Valve.GPV)
                {
                    tmp ~= leftJustify(network.curve(cast(int)link.initSetting).name, 16, ' ');
                }
                else
                {
                    double cf = link.initSetting /
                                link.convertSetting(network, link.initSetting);
                    tmp ~= leftJustify(format("%.4f", cf * link.initSetting), 12, ' ');
                }
                fout.writef("%s\n", tmp.strip);
            }
        }
    }

    void writeDemands(){
        fout.write("\n[DEMANDS]\n");
        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.JUNCTION )
            {
                Junction junc = cast(Junction)node;
                
                auto demandRange = junc.demands[];
                foreach (ref demand; demandRange)
                {
                    string tmp =
                        leftJustify(node.name, 16, ' ') ~
                        leftJustify(format("%.4f", demand.baseDemand * network.ucf(Units.FLOW)), 12, ' ');
                    
                    if (demand.timePattern !is null)
                    {
                        tmp ~= leftJustify(demand.timePattern.name, 16, ' ');
                    }
                    fout.writef("%s\n", tmp.strip);
                }
            }
        }
    }

    void writeEmitters(){
        fout.write("\n[EMITTERS]\n");
        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.JUNCTION )
            {
                Junction junc = cast(Junction)node;
                Emitter emitter = junc.emitter;
                if ( emitter )
                {
                    double qUcf = network.ucf(Units.FLOW);
                    double pUcf = network.ucf(Units.PRESSURE);

                    string tmp =
                        leftJustify(node.name, 16, ' ') ~
                        leftJustify(format("%.4f", emitter.flowCoeff * qUcf * pow(pUcf, emitter.expon)), 12, ' ') ~
                        leftJustify(format("%.4f", emitter.expon), 12, ' ');
                    if ( emitter.timePattern !is null )
                        tmp ~= leftJustify(emitter.timePattern.name, 16, ' ');
                    fout.writef("%s\n", tmp.strip);
                }
            }
        }
    }

    void writeLeakages(){
        fout.write("\n[LEAKAGES]\n");
        foreach (Link link; network.links)
        {
            if ( link.type() == Link.PIPE )
            {
                Pipe pipe = cast(Pipe)link;
                if ( pipe.leakCoeff1 > 0.0 )
                {
                    string tmp =
                        leftJustify(link.name, 16, ' ') ~
                        leftJustify(format("%.4f", pipe.leakCoeff1), 12, ' ') ~
                        leftJustify(format("%.4f", pipe.leakCoeff2), 12, ' ');
                    fout.writef("%s\n", tmp.strip);
                }
            }
        }
    }

    void writeStatus(){
        fout.write("\n[STATUS]\n");
        foreach (Link link; network.links)
        {
            if ( link.type() == Link.PUMP )
            {
                if ( link.initSetting == 0 || link.initStatus == Link.LINK_CLOSED )
                {
                    string tmp =
                        leftJustify(link.name, 16, ' ') ~ "  CLOSED\n";
                    fout.write(tmp);
                }
            }
            else if ( link.type() == Link.VALVE )
            {
                if ( link.initStatus == Link.LINK_OPEN || link.initStatus == Link.LINK_CLOSED )
                {
                    string tmp =
                        leftJustify(link.name, 16, ' ') ~ " ";
                        fout.write(tmp);
                    if (link.initStatus == Link.LINK_OPEN) fout.write("OPEN\n");
                    else fout.write("CLOSED\n");
                }
            }
        }
    }

    void writePatterns(){
        fout.write("\n[PATTERNS]\n");
        foreach (Pattern pattern; network.patterns)
        {
            if ( pattern.type == Pattern.FIXED_PATTERN )
            {
                string tmp =
                    leftJustify(pattern.name, 16, ' ') ~ " FIXED ";
                if ( pattern.timeInterval() > 0 ) tmp ~= Utilities.getTime(pattern.timeInterval());
                int k = 0;
                int i = 0;
                int n = pattern.size();
                while ( i < n )
                {
                    if ( k == 0 ) tmp ~= "\n" ~ leftJustify(pattern.name, 16, ' ') ~ "  ";
                    tmp ~= leftJustify(format("%.4f", pattern.factor(i)), 12, ' ');
                    i++;
                    k++;
                    if ( k == 5 ) k = 0;
                }
                fout.write(tmp.strip);
            }
            else if (pattern. type == Pattern.VARIABLE_PATTERN )
            {
                VariablePattern vp = cast(VariablePattern)pattern;
                string tmp =
                        leftJustify(pattern.name, 16, ' ') ~ " VARIABLE ";
                for (int i = 0; i < pattern.size(); i++)
                {
                    tmp ~= "\n" ~ leftJustify(pattern.name, 16, ' ') ~ "  " ~
                        leftJustify(Utilities.getTime(cast(long)vp.time(i)) ~ 
                        format("%.4f", vp.factor(i)), 12, ' ') ~ "\n";
                }
                fout.write(tmp.strip);
            }
            fout.write("\n");
        }
    }

    void writeCurves(){
        fout.write("\n[CURVES]\n");
        foreach (Curve curve; network.curves)
        {
            if (curve.curveType() != Curve.UNKNOWN)
            {
                string tmp =
                    leftJustify(curve.name, 16, ' ') ~ "  " ~
                    Curve.CurveTypeWords[curve.curveType()] ~ "\n";
                fout.write(tmp);
            }
            for (int i = 0; i < curve.size(); i++)
            {
                string tmp =
                    leftJustify(curve.name, 16, ' ') ~ "  " ~
                    leftJustify(format("%.4f", curve.x(i)), 12, ' ') ~
                    leftJustify(format("%.4f", curve.y(i)), 12, ' ') ~ "\n";
                fout.write(tmp);
            }
        }
    }

    void writeControls(){
        fout.write("\n[CONTROLS]\n");
        foreach (Control control; network.controls)
        {
            fout.writef("%s\n", control.toStr(network));
        }
    }

    void writeQuality(){
        fout.write("\n[QUALITY]\n");
        foreach (Node node; network.nodes)
        {
            if (node.initQual > 0.0)
            {
                string tmp =
                    leftJustify(node.name, 16, ' ') ~ " " ~
                    leftJustify(format("%.4f", node.initQual * network.ucf(Units.CONCEN)), 12, ' ');
                fout.writef("%s\n", tmp);
            }
        }
    }

    void writeSources(){
        fout.write("\n[SOURCES]\n");
        foreach (Node node; network.nodes)
        {
            if ( node.qualSource && node.qualSource.base > 0.0)
            {
                string tmp =
                    leftJustify(node.name, 16, ' ') ~ " " ~
                    leftJustify(QualSource.SourceTypeWords[node.qualSource.type], 12, ' ') ~
                    format("%.4f", node.qualSource.base);
                if ( node.qualSource.pattern )
                {
                    tmp ~= node.qualSource.pattern.name;
                }
                fout.writef("%s\n", tmp);
            }
        }
    }

    void writeMixing(){
        fout.write("\n[MIXING]\n");
        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.TANK )
            {
                Tank tank = cast(Tank)node;

                string tmp =
                    leftJustify(node.name, 16, ' ') ~ " " ~
                    leftJustify(TankMixModel.MixingModelWords[tank.mixingModel.type], 12, ' ') ~
                        format("%.4f", tank.mixingModel.fracMixed);
                
                fout.writef("%s\n", tmp);
            }
        }
    }

    void writeReactions(){
        fout.write("\n[REACTIONS]\n");
        fout.write(network.options.reactOptionsToStr());
        double defBulkCoeff = network.option(Options.BULK_COEFF);
        double defWallCoeff = network.option(Options.WALL_COEFF);

        foreach (Link link; network.links)
        {
            if ( link.type() == Link.PIPE )
            {
                Pipe pipe = cast(Pipe)link;
                if ( pipe.bulkCoeff != defBulkCoeff )
                {
                    fout.write("BULK      ");
                    fout.write(leftJustify(link.name, 16, ' ') ~ " ");
                    fout.write(format("%.4f", pipe.bulkCoeff) ~ "\n");
                }
                if ( pipe.wallCoeff != defWallCoeff )
                {
                    fout.write("WALL      ");
                    fout.write(leftJustify(link.name, 16, ' ') ~ " ");
                    fout.write(format("%.4f", pipe.wallCoeff) ~ "\n");
                }
            }
        }

        foreach (Node node; network.nodes)
        {
            if ( node.type() == Node.TANK )
            {
                Tank tank = cast(Tank)node;
                if ( tank.bulkCoeff != defBulkCoeff )
                {
                    fout.write("TANK      ");
                    fout.write(leftJustify(node.name, 16, ' ') ~ " ");
                    fout.write(format("%.4f", tank.bulkCoeff) ~ "\n");
                }
            }
        }
    }

    void writeEnergy(){
        fout.write("\n[ENERGY]\n");
        fout.write(network.options.energyOptionsToStr(network));
        foreach (Link link; network.links)
        {
            if ( link.type() == Link.PUMP )
            {
                Pump pump = cast(Pump)link;
                if ( pump.efficCurve )
                {
                    fout.write("PUMP  " ~ link.name ~ "  " ~ "EFFIC  ");
                    fout.writef("%s\n", pump.efficCurve.name);
                }

                if ( pump.costPerKwh > 0.0 )
                {
                    fout.write("PUMP  " ~ link.name ~ "  " ~ "PRICE  " ~ 
                        format("%.4f", pump.costPerKwh) ~ "\n");
                }

                if ( pump.costPattern )
                {
                    fout.write("PUMP  " ~ link.name ~ "  " ~ "PATTERN  ");
                    fout.writef("%s\n", pump.costPattern.name);
                }
            }
        }
    }

    void writeTimes(){
        fout.write("\n[TIMES]\n");
        fout.write(network.options.timeOptionsToStr());
    }

    void writeOptions(){
        fout.write("\n[OPTIONS]\n");
        fout.write(network.options.hydOptionsToStr());
        fout.write("\n");
        fout.write(network.options.demandOptionsToStr());
        fout.write("\n");
        fout.write(network.options.qualOptionsToStr());
    }

    void writeReport(){
        fout.write("\n[REPORT]\n");
        fout.write(network.options.reportOptionsToStr());
    }
    void writeTags(){}
    void writeCoords(){}
    void writeAuxData(){}

    Network network;
    File fout;
}