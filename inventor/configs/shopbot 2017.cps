/**
  Copyright (C) 2012-2016 by Autodesk, Inc.
  All rights reserved.

  ShopBot OpenSBP post processor configuration.

  $Revision: 41369 65a1f6cb57e3c7389dc895ea10958fc2f7947b0d $
  $Date: 2017-03-20 14:12:44 $
  
  FORKID {866F31A2-119D-485c-B228-090CC89C9BE8}
*/

description = "ShopBot OpenSBP";
vendor = "ShopBot Tools";
vendorUrl = "http://www.shopbottools.com";
legal = "Copyright (C) 2012-2016 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "Generic post for the Shopbot OpenSBP format with support for both manual and automatic tool changes. By default the post operates in 3-axis mode. For a 5-axis tool set the 'fiveAxis' property to Yes. 5-axis users must set the 'gaugeLength' property in inches before cutting which can be calculated through the tool's calibration macro. For a 4-axis tool set the 'fourAxis' property to YES. For 4-axis mode, the B-axis will turn around the X-axis by default. For the Y-axis configurations set the 'bAxisTurnsAroundX' property to NO. Users running older versions of SB3 - V3.5 or earlier should set the 'SB3v36' property to NO.";

extension = "sbp";
setCodePage("ascii");

capabilities = CAPABILITY_MILLING;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion



var maxZFeed = toPreciseUnit(180, IN); // max Z feed used for VS command
var stockHeight;



// user-defined properties
properties = {
  fiveAxis: false, // 5-axis machine model
  fourAxis: false, // 4-axis machine model
  bAxisTurnsAroundX: true, // choose between B-axis along X or Y - only for 4-axis mode
  SB3v36: true, // specifies that the version of control is SB3 V3.6 or greater
  gaugeLength: 6.3, // in INCHES always - change this for your particular machine and if recalibration is required - use callibration macro to get value
  safeRetractDistance: 2.0 // in INCHES always - safe retract distance above part in Z to position 5-axis head
};

function CustomVariable(specifiers, format) {
  if (!(this instanceof CustomVariable)) {
    throw new Error(localize("CustomVariable constructor called as a function."));
  }
  this.variable = createVariable(specifiers, format);
  this.offset = 0;
}

CustomVariable.prototype.format = function (value) {
  return this.variable.format(value + this.offset);
};

CustomVariable.prototype.format2 = function (value) {
  return this.variable.format(value);
};

CustomVariable.prototype.reset = function () {
  return this.variable.reset();
};

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var abcFormat = createFormat({decimals:3, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 3 : 4), scale:1.0/60.0}); // feed is mm/s or in/s
var secFormat = createFormat({decimals:2}); // seconds
var rpmFormat = createFormat({decimals:0});

var xOutput = new CustomVariable({force:true}, xyzFormat);
var yOutput = new CustomVariable({force:true}, xyzFormat);
var zOutput = new CustomVariable({force:true}, xyzFormat);
var aOutput = createVariable({force:true}, abcFormat);
var bOutput = createVariable({force:true}, abcFormat);
var feedOutput = createVariable({}, feedFormat);
var feedZOutput = createVariable({force:true}, feedFormat);
var sOutput = createVariable({prefix:"TR, ", force:true}, rpmFormat);

/**
  Writes the specified block.
*/
function writeBlock() {
  var result = "";
  for (var i = 0; i < arguments.length; ++i) {
    if (i > 0) {
      result += ", ";
    }
    result += arguments[i];
  }
  writeln(result);
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("' " + text);
}

function onOpen() {
  
  if (properties.fiveAxis && properties.fourAxis) {
    error(localize("You cannot enable both fiveAxis and fourAxis properties at the same time."));
    return;
  }

  if (properties.fiveAxis) {
    var aAxis = createAxis({coordinate:0, table:false, axis:[0, 0, -1], range:[-1440, 1440], cyclic:true, preference:1});
    var bAxis = createAxis({coordinate:1, table:false, axis:[0, -1, 0], range:[-120, 120], preference:0});
    machineConfiguration = new MachineConfiguration(bAxis, aAxis);

    setMachineConfiguration(machineConfiguration);
    optimizeMachineAngles2(0); // TCP mode - we compensate below
  } else if (properties.fourAxis) {
    if (properties.bAxisTurnsAroundX) {
      // yes - still called B even when rotating around X-axis
      var bAxis = createAxis({coordinate:1, table:true, axis:[-1, 0, 0], range:[-10000, 10000], cyclic:true, preference:1});
      machineConfiguration = new MachineConfiguration(bAxis);
      setMachineConfiguration(machineConfiguration);
      optimizeMachineAngles2(1);
    } else {
      var bAxis = createAxis({coordinate:1, table:true, axis:[0, -1, 0], range:[-10000, 10000], cyclic:true, preference:1});
      machineConfiguration = new MachineConfiguration(bAxis);
      setMachineConfiguration(machineConfiguration);
      optimizeMachineAngles2(1);
    }
  }

  if (!machineConfiguration.isMachineCoordinate(0)) {
    aOutput.disable();
  }
  if (!machineConfiguration.isMachineCoordinate(1)) {
    bOutput.disable();
  }
  
  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  writeBlock("SA"); // absolute
  
  if (properties.SB3v36) {
    writeln("CN, 90"); // calls up user variables in controller
  }
  
  switch (unit) {
  case IN:
    writeBlock("IF %(25)=1 THEN GOTO UNIT_ERROR");
    break;
  case MM:
    writeBlock("IF %(25)=0 THEN GOTO UNIT_ERROR");
    break;
  }

  var tools = getToolTable();
  if ((tools.getNumberOfTools() > 1) && !properties.SB3v36) {
    error(localize("Cannot use more than one tool without tool changer."));
    return;
  }

  var workpiece = getWorkpiece();
  var zStock = unit ? (workpiece.upper.z - workpiece.lower.z) : (workpiece.upper.z - workpiece.lower.z);
  stockHeight = workpiece.upper.z;
  writeln("&PWMaterial = " + xyzFormat.format(zStock));
  var partDatum = workpiece.lower.z;
  if (partDatum > 0) {
    writeln("&PWZorigin = Table Surface");
  } else {
    writeln("&PWZorigin = Part Surface");
  }
  machineConfiguration.setRetractPlane(stockHeight + properties.safeRetractDistance);
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of A, B, and C. */
function forceABC() {
  aOutput.reset();
  bOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  forceABC();
  feedOutput.reset();
}

function onParameter(name, value) {
}

var currentWorkPlaneABC = undefined;

function forceWorkPlane() {
  currentWorkPlaneABC = undefined;
}

function setWorkPlane(abc) {
  var retracted = false;
  if (!machineConfiguration.isMultiAxisConfiguration()) {
    return retracted; // ignore
  }

  if (!((currentWorkPlaneABC == undefined) ||
        abcFormat.areDifferent(abc.x, currentWorkPlaneABC.x) ||
        abcFormat.areDifferent(abc.y, currentWorkPlaneABC.y) ||
        abcFormat.areDifferent(abc.z, currentWorkPlaneABC.z))) {
    return retracted; // no change
  }

  // retract to safe plane
  writeBlock(
    "JZ",
    zOutput.format(machineConfiguration.getRetractPlane())
  );

  // move XY to home position
  writeBlock("JH");
  retracted = true;

  writeBlock(
    "J5",
    "", // x
    "", // y
    "", // z
    conditional(machineConfiguration.isMachineCoordinate(0), abcFormat.format(abc.x)),
    conditional(machineConfiguration.isMachineCoordinate(1), abcFormat.format(abc.y))
    // conditional(machineConfiguration.isMachineCoordinate(2), abcFormat.format(abc.z))
  );
  
  currentWorkPlaneABC = abc;
  return true;
}

var closestABC = false; // choose closest machine angles
var currentMachineABC;

function getWorkPlaneMachineABC(workPlane) {
  var W = workPlane; // map to global frame

  var abc = machineConfiguration.getABC(W);
  if (closestABC) {
    if (currentMachineABC) {
      abc = machineConfiguration.remapToABC(abc, currentMachineABC);
    } else {
      abc = machineConfiguration.getPreferredABC(abc);
    }
  } else {
    abc = machineConfiguration.getPreferredABC(abc);
  }
  
  try {
    abc = machineConfiguration.remapABC(abc);
    currentMachineABC = abc;
  } catch (e) {
    error(
      localize("Machine angles not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      // + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
  }
  
  var direction = machineConfiguration.getDirection(abc);
  if (!isSameDirection(direction, W.forward)) {
    error(localize("Orientation not supported."));
  }
  
  if (!machineConfiguration.isABCSupported(abc)) {
    error(
      localize("Work plane is not supported") + ":"
      + conditional(machineConfiguration.isMachineCoordinate(0), " A" + abcFormat.format(abc.x))
      + conditional(machineConfiguration.isMachineCoordinate(1), " B" + abcFormat.format(abc.y))
      // + conditional(machineConfiguration.isMachineCoordinate(2), " C" + abcFormat.format(abc.z))
    );
  }

  var tcp = properties.fiveAxis; // 4-axis adjusts for rotations, 5-axis does not
  if (tcp) {
    setRotation(W); // TCP mode
  } else {
    var O = machineConfiguration.getOrientation(abc);
    var R = machineConfiguration.getRemainingOrientation(abc, W);
    setRotation(R);
  }
  
  return abc;
}

var headOffset = 0;

function onSection() {
  var insertToolCall = isFirstSection() ||
    currentSection.getForceToolChange && currentSection.getForceToolChange() ||
    (tool.number != getPreviousSection().getTool().number);
  
  writeln("");

  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }
  
  if (properties.showNotes && hasParameter("notes")) {
    var notes = getParameter("notes");
    if (notes) {
      var lines = String(notes).split("\n");
      var r1 = new RegExp("^[\\s]+", "g");
      var r2 = new RegExp("[\\s]+$", "g");
      for (line in lines) {
        var comment = lines[line].replace(r1, "").replace(r2, "");
        if (comment) {
          writeComment(comment);
        }
      }
    }
  }
  
  var retracted = false;
  if (machineConfiguration.isMultiAxisConfiguration()) { // use 5-axis indexing for multi-axis mode

    // set working plane after datum shift
    var abc;
    if (currentSection.isMultiAxis()) {
      abc = currentSection.getInitialToolAxisABC();
      cancelTransformation();
    } else {
      abc = getWorkPlaneMachineABC(currentSection.workPlane);
    }
    retracted = setWorkPlane(abc);
  } else { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  feedOutput.reset();

  if (insertToolCall && properties.SB3v36) {
    // forceWorkPlane();
    
    if (tool.number > 99) {
      warning(localize("Tool number exceeds maximum value."));
    }
    if (isFirstSection() ||
        currentSection.getForceToolChange && currentSection.getForceToolChange() ||
        (tool.number != getPreviousSection().getTool().number)) {
/*
      if (hasParameter("operation:clearanceHeight_offset")) {
           var safeZ = getParameter("operation:clearanceHeight_offset");
        writeln("&PWSafeZ = " + safeZ);
      }
*/
      onCommand(COMMAND_STOP_SPINDLE);
      writeln("&Tool = " + tool.number);
      if (!currentSection.isMultiAxis() && !retracted) {
        writeln("C9"); // call macro 9
      }
    }
    if (tool.comment) {
      writeln("&ToolName = " + tool.comment);
    }
  }

/*
  if (!properties.SB3v36) {
    // we only allow a single tool without a tool changer
    writeBlock("PAUSE"); // wait for user
  }
*/

  if (insertToolCall ||
      isFirstSection() ||
      (rpmFormat.areDifferent(tool.spindleRPM, sOutput.getCurrent())) ||
      (tool.clockwise != getPreviousSection().getTool().clockwise)) {
    if (tool.spindleRPM < 5000) {
      warning(localize("Spindle speed is below minimum value."));
    }
    if (tool.spindleRPM > 24000) {
      warning(localize("Spindle speed exceeds maximum value."));
    }

    writeBlock(sOutput.format(tool.spindleRPM));
    onCommand(COMMAND_START_SPINDLE);
  }

  headOffset = 0;
  if (properties.fiveAxis) {
    headOffset = tool.bodyLength + toPreciseUnit(properties.gaugeLength, IN); // control will compensate for tool length
    var displacement = currentSection.getGlobalInitialToolAxis();
    // var displacement = currentSection.workPlane.forward;
    displacement.multiply(headOffset);
    displacement = Vector.diff(displacement, new Vector(0, 0, headOffset));
    // writeComment("DISPLACEMENT: X" + xyzFormat.format(displacement.x) + " Y" + xyzFormat.format(displacement.y) + " Z" + xyzFormat.format(displacement.z));
    // setTranslation(displacement);

    // temporary solution
    xOutput.offset = displacement.x;
    yOutput.offset = displacement.y;
    zOutput.offset = displacement.z;
  } else {
    // temporary solution
    xOutput.offset = 0;
    yOutput.offset = 0;
    zOutput.offset = 0;
  }

  forceAny();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock("J3", zOutput.format(initialPosition.z));
      retracted = true;
    } else {
      retracted = false;
    }
  }

  if (true /*insertToolCall*/) {
    if (!retracted) {
      writeBlock(
        "JZ",
        zOutput.format(initialPosition.z)
      );
    }
    writeBlock(
      "J2",
      xOutput.format(initialPosition.x),
      yOutput.format(initialPosition.y)
    );
  }

  if (currentSection.isMultiAxis()) {
    xOutput.offset = 0;
    yOutput.offset = 0;
    zOutput.offset = 0;
  }
}

function onDwell(seconds) {
  seconds = clamp(0.01, seconds, 99999);
  writeBlock("PAUSE", secFormat.format(seconds));
}

function onSpindleSpeed(spindleSpeed) {
  if (tool.spindleRPM < 5000) {
    warning(localize("Spindle speed out of range."));
    return;
  }
  if (tool.spindleRPM > 24000) {
    warning(localize("Spindle speed exceeds maximum value."));
  }
  writeBlock(sOutput.format(spindleSpeed));
  onCommand(COMMAND_START_SPINDLE);
}

function onRadiusCompensation() {
}

function writeFeed(feed, moveInZ, multiAxis) {
  var fCode = multiAxis ? "VS" : "MS";
  if (properties.SB3v36) {
    var f = feedOutput.format(feed);
    if (f) {
      writeBlock(fCode, f, f);
    }
  } else {
    if (moveInZ) { // limit feed if moving in Z
      feed = Math.min(feed, maxZFeed);
    }
    var f = feedOutput.format(feed);
    if (f) {
      writeBlock(fCode, f, feedZOutput.format(Math.min(feed, maxZFeed)));
    }
  }
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    writeBlock("J3", x, y, z);
  }
}

function onLinear(_x, _y, _z, feed) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  writeFeed(feed, !!z, false);
  if (x || y || z) {
    writeBlock("M3", x, y, z);
  }
}

function adjustPoint(_x, _y, _z, _a, _b, _c) {
  var xyz = new Vector();
  if (properties.fiveAxis) {
    var displacement = machineConfiguration.getDirection(new Vector(_a, _b, _c));
    displacement.multiply(headOffset); // control will compensate for tool length
    displacement = Vector.diff(displacement, new Vector(0, 0, headOffset));
    xyz.setX(_x + displacement.x);
    xyz.setY(_y + displacement.y);
    xyz.setZ(_z + displacement.z);
  } else { // don't adjust points for 4-axis machines
    xyz.setX(_x);
    xyz.setY(_y);
    xyz.setZ(_z);
  }
  return xyz;
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  if (!currentSection.isOptimizedForMachine()) {
    error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    return;
  }

  var xyz = adjustPoint(_x, _y, _z, _a, _b, _c);
  var x = xOutput.format2(xyz.x);
  var y = yOutput.format2(xyz.y);
  var z = zOutput.format2(xyz.z);

  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  writeBlock("J5", x, y, z, a, b);
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  if (!currentSection.isOptimizedForMachine()) {
    error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    return;
  }
  
  var xyz = adjustPoint(_x, _y, _z, _a, _b, _c);
  var x = xOutput.format2(xyz.x);
  var y = yOutput.format2(xyz.y);
  var z = zOutput.format2(xyz.z);

  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  writeFeed(feed, !!z, true);
  if (x || y || z || a || b) {
    writeBlock("M5", x, y, z, a, b);
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  var start = getCurrentPosition();

  if (isHelical()) {
    linearize(tolerance);
    return;
  }

  switch (getCircularPlane()) {
  case PLANE_XY:
    writeFeed(feed, false, false);
    writeBlock("CG", "", xOutput.format(x), yOutput.format(y), xyzFormat.format(cx - start.x), xyzFormat.format(cy - start.y), "", clockwise ? 1 : -1);
    break;
  default:
    linearize(tolerance);
  }
}

function onCommand(command) {
  switch (command) {
  case COMMAND_STOP_SPINDLE:
    if (properties.SB3v36) {
      writeln("C7"); // call macro 7
    } else {
      writeln("SO 1,0");
    }
    break;
  case COMMAND_START_SPINDLE:
    if (properties.SB3v36) {
      writeln("C6"); // call macro 6
    } else {
      writeln("SO 1,1");
    }
    writeln("PAUSE 2"); // wait for 2 seconds for spindle to ramp up
    break;
  }
}

function onSectionEnd() {
  xOutput.offset = 0;
  yOutput.offset = 0;
  zOutput.offset = 0;
  forceAny();
}

function onClose() {
  onCommand(COMMAND_STOP_SPINDLE);

  retracted = setWorkPlane(new Vector(0, 0, 0)); // reset working plane
  if (!retracted) {
    writeBlock(
      "JZ",
      zOutput.format(machineConfiguration.getRetractPlane())
    );
    writeBlock("JH");
  }

  writeBlock("END");
  writeln("");
  writeln("");
  writeBlock("UNIT_ERROR:");
  writeBlock("CN, 91");
  writeBlock("END");
}
