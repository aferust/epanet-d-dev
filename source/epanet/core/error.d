/* EPANET 3
 *
 * Copyright (c) 2016 Open Water Analytics
 * Distributed under the MIT License (see the LICENSE file for details).
 *
 */
module epanet.core.error;

//-----------------------------------------------------------------------------
//  Base exception class
//-----------------------------------------------------------------------------

class ENerror: Exception {
    int code;

    this(){
        code = 0;
        this(msg, __FILE__, __LINE__);
    }

    this(string msg, string file = __FILE__, size_t line = __LINE__){
        code = 0;
        super(msg, file, line);
    }
}

//-----------------------------------------------------------------------------
//  System error exception class
//-----------------------------------------------------------------------------
class SystemError : ENerror
{
  public:
    enum  { // SystemErrors
        OUT_OF_MEMORY,                 //101
        NO_NETWORK_DATA,               //102

        HEADLOSS_MODEL_NOT_OPENED,     //103
        DEMAND_MODEL_NOT_OPENED,       //104
        LEAKAGE_MODEL_NOT_OPENED,      //105
        QUALITY_MODEL_NOT_OPENED,      //106
        MATRIX_SOLVER_NOT_OPENED,      //107

        HYDRAULIC_SOLVER_NOT_OPENED,   //108
        QUALITY_SOLVER_NOT_OPENED,     //109
        HYDRAULICS_SOLVER_FAILURE,     //110
        QUALITY_SOLVER_FAILURE,        //111
        SOLVER_NOT_INITIALIZED,        //112
        SYSTEM_ERROR_LIMIT
    }

    this(int type, string file = __FILE__, size_t line = __LINE__){

        if ( type >= 0 && type < SYSTEM_ERROR_LIMIT ){
            code = SystemErrorCodes[type];
            msg =  SystemErrorMsgs[type];
            
        }
        super(msg, file, line);
    }
}

static const int[12] SystemErrorCodes =
[
    101, //OUT_OF_MEMORY,
    102, //NO_NETWORK_DATA,

    103, //HEADLOSS_MODEL_NOT_OPENED,
    104, //DEMAND_MODEL_NOT_OPENED,
    105, //LEAKAGE_MODEL_NOT_OPENED
    106, //QUALITY_MODEL_NOT_OPENED
    107, //MATRIX_SOLVER_NOT_OPENED,

    108, //HYDRAULIC_SOLVER_NOT_OPENED,
    109, //QUALITY_SOLVER_NOT_OPENED,
    110, //HYDRAULICS_SOLVER_FAILURE,
    111, //QUALITY_SOLVER_FAILURE

    112  //SOLVER_NOT_INITIALIZED,
];

static string[12] SystemErrorMsgs =
[
    "\n\n*** SYSTEM ERROR 101: OUT OF MEMORY",
    "\n\n*** SYSTEM ERROR 102: NO NETWORK DATA TO ANALYZE",
    "\n\n*** SYSTEM ERROR 103: COULD NOT CREATE A HEAD LOSS MODEL",
    "\n\n*** SYSTEM ERROR 104: COULD NOT CREATE A DEMAND MODEL",
    "\n\n*** SYSTEM ERROR 105: COULD NOT CREATE A LEAKAGE MODEL",
    "\n\n*** SYSTEM ERROR 106: COULD NOT CREATE A QUALITY MODEL",
    "\n\n*** SYSTEM ERROR 107: COULD NOT CREATE A MATRIX SOLVER",
    "\n\n*** SYSTEM ERROR 108: HYDRAULIC SOLVER NOT OPENED",
    "\n\n*** SYSTEM ERROR 109: QUALITY SOLVER NOT OPENED",
    "\n\n*** SYSTEM ERROR 110: HYDRAULIC SOLVER FAILURE",
    "\n\n*** SYSTEM ERROR 111: QUALITY SOLVER FAILURE",
    "\n\n*** SYSTEM ERROR 112: SOLVER NOT INITIALIZED"
];

static const int[9] InputErrorCodes =
[
    200, //ERRORS_IN_INPUT_DATA
    201, //CANNOT_CREATE_OBJECT
    202, //TOO_FEW_ITEMS
    203, //INVALID_KEYWORD
    204, //DUPLICATE_ID_NAME
    205, //UNDEFINED_OBJECT
    206, //INVALID_NUMBER
    207, //INVALID_TIME
    208  //UNSPECIFIED
];

static immutable string[9] InputErrorMsgs =
[
    "\n\n*** INPUT ERROR 200: one or more errors in network input data.",
    "\n\n*** INPUT ERROR 201: cannot create object ",
    "\n\n*** INPUT ERROR 202: too few items ",
    "\n\n*** INPUT ERROR 203: invalid keyword ",
    "\n\n*** INPUT ERROR 204: duplicate ID name ",
    "\n\n*** INPUT ERROR 205: undefined object ",
    "\n\n*** INPUT ERROR 206: invalid number ",
    "\n\n*** INPUT ERROR 207: invalid time ",
    "\n\n*** UNSPECIFIED INPUT ERROR "
];

static const int[9] NetworkErrorCodes =
[
    220, //ILLEGAL_VALVE_CONNECTION
    223, //TOO_FEW_NODES
    224, //NO_FIXED_GRADE_NODES
    225, //INVALID_TANK_LEVELS
    226, //NO_PUMP_CURVE
    227, //INVALID_PUMP_CURVE
    230, //INVALID_CURVE_DATA
    231, //INVALID_VOLUME_CURVE
    233  //UNCONNECTED_NODE
];

static immutable string[9] NetworkErrorMsgs =
[
    "\n\n NETWORK ERROR 220: illegal connection for valve ",
    "\n\n NETWORK ERROR 223: too few nodes in network.",
    "\n\n NETWORK ERROR 224: no fixed grade nodes in network.",
    "\n\n NETWORK ERROR 225: invalid depth limits for tank ",
    "\n\n NETWORK ERROR 226: no pump curve supplied for pump ",
    "\n\n NETWORK ERROR 227: invalid pump curve for pump ",
    "\n\n NETWORK ERROR 230: invalid data for curve ",
    "\n\n NETWORK ERROR 231: invalid volume curve for tank ",
    "\n\n NETWORK ERROR 233: no links connected to node "
];


static const int[10] FileErrorCodes =
[
    301, // DUPLICATE_FILE_NAMES
    302, // CANNOT_OPEN_INPUT_FILE
    303, // CANNOT_OPEN_REPORT_FILE
    304, // CANNOT_OPEN_OUTPUT_FILE
    305, // CANNOT_OPEN_HYDRAULICS_FILE
    306, // INCOMPATIBLE_HYDRAULICS_FILE
    307, // CANNOT_READ_HYDRAULICS_FILE
    308, // CANNOT_WRITE_TO_OUTPUT_FILE
    309, // CANNOT_WRITE_TO_REPORT_FILE
    310  // NO_RESULTS_SAVED_TO_REPORT
];

static immutable string[10] FileErrorMsgs =
[
    "\n\n*** FILE ERROR 301: DUPLICATE FILE NAMES",
    "\n\n*** FILE ERROR 302: CANNOT OPEN INPUT FILE",
    "\n\n*** FILE ERROR 303: CANNOT OPEN REPORT FILE",
    "\n\n*** FILE ERROR 304: CANNOT OPEN OUTPUT FILE",
    "\n\n*** FILE ERROR 305: CANNOT OPEN HYDRAULICS FILE",
    "\n\n*** FILE ERROR 306: INCOMPATIBLE HYDRAULICS FILE",
    "\n\n*** FILE ERROR 307: CANNOT READ HYDRAULICS FILE",
    "\n\n*** FILE ERROR 308: CANNOT WRITE TO OUTPUT FILE",
    "\n\n*** FILE ERROR 309: CANNOT WRITE TO REPORT FILE",
    "\n\n*** FILE ERROR 310: NO RESULTS SAVED TO REPORT"
];


//-----------------------------------------------------------------------------
//  Input error exception class
//-----------------------------------------------------------------------------
class InputError : ENerror
{
  public:
    enum { //InputErrors
        ERRORS_IN_INPUT_DATA,          //200
        CANNOT_CREATE_OBJECT,          //201
        TOO_FEW_ITEMS,                 //202
        INVALID_KEYWORD,               //203
        DUPLICATE_ID,                  //204
        UNDEFINED_OBJECT,              //205
        INVALID_NUMBER,                //206
        INVALID_TIME,                  //207
        UNSPECIFIED,                   //208
        INPUT_ERROR_LIMIT
    }

    this(int type, string token, string file = __FILE__, size_t line = __LINE__){
        if (type < 0 || type >= UNSPECIFIED) type = UNSPECIFIED;
        code = InputErrorCodes[type];
        msg = InputErrorMsgs[type] ~ token;
        super(msg, file, line);
    }
}

//-----------------------------------------------------------------------------
//  Network error class
//-----------------------------------------------------------------------------
class NetworkError : ENerror
{
  public:
    enum { // NetworkErrors
        ILLEGAL_VALVE_CONNECTION,      //220
        TOO_FEW_NODES,                 //223
        NO_FIXED_GRADE_NODES,          //224
        INVALID_TANK_LEVELS,           //225
        NO_PUMP_CURVE,                 //226
        INVALID_PUMP_CURVE,            //227
        INVALID_CURVE_DATA,            //230
        INVALID_VOLUME_CURVE,          //231
        UNCONNECTED_NODE,              //233
        NETWORK_ERROR_LIMIT
    }

    this(int type, string id, string file = __FILE__, size_t line = __LINE__){
        if (type >= 0 && type < NETWORK_ERROR_LIMIT)
        {
            code = NetworkErrorCodes[type];
            msg = NetworkErrorMsgs[type] ~ id;
        }
        super(msg, file, line);
    }
}

//-----------------------------------------------------------------------------
//  File error exception class
//-----------------------------------------------------------------------------
class FileError : ENerror
{
  public:
    enum { // FileErrors
        DUPLICATE_FILE_NAMES,          //301
        CANNOT_OPEN_INPUT_FILE,        //302
        CANNOT_OPEN_REPORT_FILE,       //303
        CANNOT_OPEN_OUTPUT_FILE,       //304
        CANNOT_OPEN_HYDRAULICS_FILE,   //305
        INCOMPATIBLE_HYDRAULICS_FILE,  //306
        CANNOT_READ_HYDRAULICS_FILE,   //307
        CANNOT_WRITE_TO_OUTPUT_FILE,   //308
        CANNOT_WRITE_TO_REPORT_FILE,   //309
        NO_RESULTS_SAVED_TO_REPORT,    //310
        FILE_ERROR_LIMIT
    }

    this(int type, string file = __FILE__, size_t line = __LINE__){
        if ( type >= 0 && type < FILE_ERROR_LIMIT )
        {
            code = FileErrorCodes[type];
            msg =  FileErrorMsgs[type];
        }
        super(msg, file, line);
    }
}