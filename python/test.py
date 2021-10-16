from epamodule3 import *

prjHandle = ENcreateProject()

print(ENgetVersion())

mstr = "out1"
err = ENopenReportFile(mstr, prjHandle)

err = ENloadProject("some.inp", prjHandle)

err = ENopenOutputFile("out2", prjHandle)
err = ENwriteSummary(prjHandle)

err = ENinitSolver(0, prjHandle)

t = 0
tstep = 0

while True:
    t = ENrunSolver(prjHandle)
    err = ENwriteMsgLog(prjHandle)
    tstep = ENadvanceSolver(prjHandle)
    if (tstep == 0 or err == 0): break

err = ENwriteReport(prjHandle)

err = ENsaveProject("some_generated.inp", prjHandle )

index = ENgetNodeIndex("132", prjHandle)
pressure = ENgetNodeValue(index, EN_PRESSURE, prjHandle)
print(pressure)

ENdeleteProject(prjHandle)