"""Python EpanetToolkit interface"""

# TODO: raise errors

from ctypes import *
import platform

import sys
import os
this_dir = os.path.dirname(os.path.realpath(__file__))
sys.path.append(this_dir)

_plat= platform.system()
if _plat=='Linux':
  _lib = CDLL("libepanet3.so.2")
elif _plat=='Windows':
  try:
    # if epanet2.dll compiled with __cdecl (as in OpenWaterAnalytics)
    _lib = CDLL(os.path.join(this_dir, "epamodule3", "epanet3.dll"))
  except ValueError:
     # if epanet2.dll compiled with __stdcall (as in EPA original DLL)
     try:
       _lib = windll.epanet3
       _lib.ENgetversion(byref(c_int()))
     except ValueError:
       raise Exception("epanet3.dll not suitable")
elif _plat=='Darwin':
    _lib = CDLL(os.path.join(this_dir, "epamodule3", "libepanet3.dylib"))
else:
  Exception('Platform '+ _plat +' unsupported (not yet)')


_max_label_len= 32
_err_max_char= 80


def ENgetVersion():
    j = c_int()
    ierr = _lib.EN_getVersion(byref(j))
    return j.value

def ENrunEpanet(inpFile, rptFile, outFile):
    func = _lib.EN_runEpanet
    func.argtypes = [c_char_p, c_char_p, c_char_p]
    func.restype = c_long
    
    return func(c_char_p(repFileName.encode()),
                c_char_p(repFileName.encode()),
                c_char_p(repFileName.encode()))

def ENcreateProject():
    func = _lib.EN_createProject
    func.restype = c_void_p
    _handle = func()
    return _handle

def ENloadProject(fname, handle):
    func = _lib.EN_loadProject
    func.argtypes = [c_char_p, c_void_p]
    func.restype = c_long
    return func(c_char_p(fname.encode()), handle)

def ENsaveProject(fname, handle):
    func = _lib.EN_saveProject
    func.argtypes = [c_char_p, c_void_p]
    func.restype = c_long
    return func(c_char_p(fname.encode()), handle)

def ENclearProject(handle):
    func = _lib.EN_clearProject
    func.argtypes = [c_void_p]
    func.restype = c_long
    return func(handle)

def ENdeleteProject(handle):
    func = _lib.EN_deleteProject
    func.argtypes = [c_void_p]
    func.restype = c_long
    return func(handle)

def ENcloneProject(pSource):
    func = _lib.EN_cloneProject
    func.argtypes = [c_void_p, c_void_p]
    func.restype = c_long
    pClone = ENcreateProject()
    err = func(pClone, pSource)
    return pClone

def ENinitSolver(initFlows, handle):
    func = _lib.EN_initSolver
    func.argtypes = [c_int, c_void_p]
    func.restype = c_long
    return func(initFlows, handle)

def ENrunSolver(handle):
    func = _lib.EN_runSolver
    func.argtypes = [POINTER(c_int), c_void_p]
    j = c_int()
    err = func(byref(j), handle)
    return j.value

def ENadvanceSolver(handle):
    func = _lib.EN_advanceSolver
    func.argtypes = [POINTER(c_int), c_void_p]
    j = c_int()
    err = func(byref(j), handle)
    return j.value

def ENopenOutputFile(fname, handle):
    func = _lib.EN_openOutputFile
    func.argtypes = [c_char_p, c_void_p]
    func.restype = c_long
    return func(c_char_p(fname.encode()), handle)

def ENsaveOutput(handle):
    func = _lib.EN_saveOutput
    func.argtypes = [c_void_p]
    func.restype = c_long
    return func(handle)

def ENopenReportFile(repFileName, handle):
    func = _lib.EN_openReportFile
    func.argtypes = [c_char_p, c_void_p]
    func.restype = c_long
    return func(c_char_p(repFileName.encode()), handle)

def ENwriteReport(handle):
    func = _lib.EN_writeReport
    func.argtypes = [c_void_p]
    func.restype = c_long
    return func(handle)

def ENwriteSummary(handle):
    func = _lib.EN_writeSummary
    func.argtypes = [c_void_p]
    func.restype = c_long
    return func(handle)

def ENwriteResults(t, handle):
    func = _lib.EN_writeResults
    func.argtypes = [c_int, c_void_p]
    func.restype = c_long
    return func(t, handle)

def ENwriteMsgLog(handle):
    func = _lib.EN_writeMsgLog
    func.argtypes = [c_void_p]
    func.restype = c_long
    return func(handle)

def ENgetCount(element, handle):
    func = _lib.EN_getCount
    func.argtypes = [c_int, POINTER(c_int), c_void_p]
    func.restype = c_long
    _count = c_int()
    func(element, byref(_count), handle)
    return count.value

def ENgetNodeIndex(name, handle):
    func = _lib.EN_getNodeIndex
    func.argtypes = [c_char_p, POINTER(c_int), c_void_p]
    func.restype = c_long
    _index = c_int()
    err = func(c_char_p(name.encode()), byref(_index), handle)
    return _index.value

def ENgetNodeId(index, handle):
    func = _lib.EN_getNodeId
    func.argtypes = [c_int, c_char_p, c_void_p]
    func.restype = c_long
    id = create_string_buffer(_max_label_len)
    err = func(index, byref(id), handle)
    return id

def ENgetNodeType(index, handle):
    func = _lib.EN_getNodeType
    func.argtypes = [c_int, POINTER(c_int), c_void_p]
    func.restype = c_long
    type = c_int()
    err = func(index, byref(type), handle)
    return type.value
    
def ENgetNodeValue(index, param, handle):
    func = _lib.EN_getNodeValue
    func.argtypes = [c_int, c_int, POINTER(c_double), c_void_p]
    func.restype = c_long
    val = c_double()
    err = func(index, param, byref(val), handle)
    return val.value

def ENgetLinkIndex(name, handle):
    func = _lib.EN_getLinkIndex
    func.argtypes = [c_char_p, POINTER(c_int), c_void_p]
    func.restype = c_long
    val = c_int()
    err = func(c_char_p(name.encode()), byref(val), handle)
    return val.value
    
def ENgetLinkId(index, id, handle):
    func = _lib.EN_getLinkId
    func.argtypes = [c_int, c_char_p, c_void_p]
    func.restype = c_long
    label = create_string_buffer(_max_label_len)
    err = func(index, byref(label), handle)
    return label
    
def ENgetLinkType(index, handle):
    func = _lib.EN_getLinkType
    func.argtypes = [c_int, POINTER(c_int), c_void_p]
    func.restype = c_long
    type = c_int()
    err = func(index, byref(type), handle)
    return type.value

def ENgetLinkNodes(index, handle):
    func = _lib.EN_getLinkNodes
    func.argtypes = [c_int, POINTER(c_int), POINTER(c_int), c_void_p]
    func.restype = c_long
    fromNode = c_int()
    toNode = c_int()
    err = func(index, byref(fromNode), byref(toNode), handle)
    return (fromNode.value, toNode.value)

def ENgetLinkValue(index, param, handle):
    func = _lib.EN_getLinkValue
    func.argtypes = [c_int, c_int, POINTER(c_double), c_void_p]
    func.restype = c_long
    val = c_double()
    err = func(index, param, val, handle)
    return val.value

#-----end of functions added from OpenWaterAnalytics ----------------------------------


EN_ELEVATION     = 0      # /* Node parameters */
EN_BASEDEMAND    = 1
EN_PATTERN       = 2
EN_EMITTER       = 3
EN_INITQUAL      = 4
EN_SOURCEQUAL    = 5
EN_SOURCEPAT     = 6
EN_SOURCETYPE    = 7
EN_TANKLEVEL     = 8
EN_DEMAND        = 9
EN_HEAD          = 10
EN_PRESSURE      = 11
EN_QUALITY       = 12
EN_SOURCEMASS    = 13
EN_INITVOLUME    = 14
EN_MIXMODEL      = 15
EN_MIXZONEVOL    = 16

EN_TANKDIAM      = 17
EN_MINVOLUME     = 18
EN_VOLCURVE      = 19
EN_MINLEVEL      = 20
EN_MAXLEVEL      = 21
EN_MIXFRACTION   = 22
EN_TANK_KBULK    = 23

EN_DIAMETER      = 0      # /* Link parameters */
EN_LENGTH        = 1
EN_ROUGHNESS     = 2
EN_MINORLOSS     = 3
EN_INITSTATUS    = 4
EN_INITSETTING   = 5
EN_KBULK         = 6
EN_KWALL         = 7
EN_FLOW          = 8
EN_VELOCITY      = 9
EN_HEADLOSS      = 10
EN_STATUS        = 11
EN_SETTING       = 12
EN_ENERGY        = 13

EN_DURATION      = 0      # /* Time parameters */
EN_HYDSTEP       = 1
EN_QUALSTEP      = 2
EN_PATTERNSTEP   = 3
EN_PATTERNSTART  = 4
EN_REPORTSTEP    = 5
EN_REPORTSTART   = 6
EN_RULESTEP      = 7
EN_STATISTIC     = 8
EN_PERIODS       = 9

EN_NODECOUNT     = 0      # /* Component counts */
EN_TANKCOUNT     = 1
EN_LINKCOUNT     = 2
EN_PATCOUNT      = 3
EN_CURVECOUNT    = 4
EN_CONTROLCOUNT  = 5

EN_JUNCTION      = 0      # /* Node types */
EN_RESERVOIR     = 1
EN_TANK          = 2

EN_CVPIPE        = 0      # /* Link types */
EN_PIPE          = 1
EN_PUMP          = 2
EN_PRV           = 3
EN_PSV           = 4
EN_PBV           = 5
EN_FCV           = 6
EN_TCV           = 7
EN_GPV           = 8

EN_NONE          = 0      # /* Quality analysis types */
EN_CHEM          = 1
EN_AGE           = 2
EN_TRACE         = 3

EN_CONCEN        = 0      # /* Source quality types */
EN_MASS          = 1
EN_SETPOINT      = 2
EN_FLOWPACED     = 3

EN_CFS           = 0      # /* Flow units types */
EN_GPM           = 1
EN_MGD           = 2
EN_IMGD          = 3
EN_AFD           = 4
EN_LPS           = 5
EN_LPM           = 6
EN_MLD           = 7
EN_CMH           = 8
EN_CMD           = 9

EN_TRIALS        = 0      # /* Misc. options */
EN_ACCURACY      = 1
EN_TOLERANCE     = 2
EN_EMITEXPON     = 3
EN_DEMANDMULT    = 4

EN_LOWLEVEL      = 0      # /* Control types */
EN_HILEVEL       = 1
EN_TIMER         = 2
EN_TIMEOFDAY     = 3

EN_AVERAGE       = 1      # /* Time statistic types.    */
EN_MINIMUM       = 2
EN_MAXIMUM       = 3
EN_RANGE         = 4

EN_MIX1          = 0      # /* Tank mixing models */
EN_MIX2          = 1
EN_FIFO          = 2
EN_LIFO          = 3

EN_NOSAVE        = 0      # /* Save-results-to-file flag */
EN_SAVE          = 1
EN_INITFLOW      = 10     # /* Re-initialize flow flag   */



FlowUnits= { EN_CFS :"cfs"   ,
             EN_GPM :"gpm"   ,
             EN_MGD :"a-f/d" ,
             EN_IMGD:"mgd"   ,
             EN_AFD :"Imgd"  ,
             EN_LPS :"L/s"   ,
             EN_LPM :"Lpm"   ,
             EN_MLD :"m3/h"  ,
             EN_CMH :"m3/d"  ,
             EN_CMD :"ML/d"  }
