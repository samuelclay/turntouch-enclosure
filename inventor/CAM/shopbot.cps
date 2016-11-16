/**
  Copyright (C) 2012-2016 by Autodesk, Inc.
  All rights reserved.

  ShopBot OpenSBP post processor configuration.

  $Revision: 41223 cb4874c2c8e1f7ab799239cabce15a368fccf144 $
  $Date: 2016-11-04 17:55:22 $
  
  FORKID {866F31A2-119D-485c-B228-090CC89C9BE8}
*/

description = "ShopBot OpenSBP";
vendor = "ShopBot Tools";
vendorUrl = "http://www.shopbottools.com";
legal = "Copyright (C) 2012-2016 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "Generic post for the Shopbot OpenSBP format. Tool changer is not enabled by default. If you have a tool chager you need to turn on the 'useToolChanger' property. Make sure to set the 'gaugeLength' property in inches before cutting. You can use the built-in callibration macro on the CNC to get correct value. By default the post operates in 3-axis mode. If you have a 5-axis model turn on 'fiveAxis'. If you have a 4-axis model turn on 'fourAxis' property. For 4-axis mode the B-axis will turn around the machine X-axis by default. For the Y-axis configurations you need to turn off the 'bAxisTurnsAroundX' property.";

capabilities = CAPABILITY_MILLING;
extension = "sbp";
setCodePage("ascii");

tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion



var maxZFeed = toPreciseUnit(180, IN); // max Z feed used for VS command



// user-defined properties
properties = {
  fiveAxis: false, // 5-axis machine model
  fourAxis: false, // 4-axis machine model
  bAxisTurnsAroundX: true, // choose between B-axis along X or Y - only for 4-axis mode
  useToolChanger: false, // specifies that a tool changer is available
  gaugeLength: 6.3 // in INCHES always - change this for your particular machine and if recalibration is required - use callibration macro to get value
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

var xOutput = new CustomVariable({force:true}, xyzFormat);
var yOutput = new CustomVariable({force:true}, xyzFormat);
var zOutput = new CustomVariable({force:true}, xyzFormat);
var aOutput = createVariable({force:true}, abcFormat);
var bOutput = createVariable({force:true}, abcFormat);
var feedOutput = createVariable({}, feedFormat);
var feedZOutput = createVariable({force:true}, feedFormat);

var rpmFormat = createFormat({decimals:0});

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
      optimizeMachineAngles2(0); // TCP mode - we compensate below
    } else {
      var bAxis = createAxis({coordinate:1, table:true, axis:[0, -1, 0], range:[-10000, 10000], cyclic:true, preference:1});
      machineConfiguration = new MachineConfiguration(bAxis);
      setMachineConfiguration(machineConfiguration);
      optimizeMachineAngles2(0); // TCP mode - we compensate below
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
  
  if (properties.useToolChanger) {
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
  if ((tools.getNumberOfTools() > 1) && !properties.useToolChanger) {
    error(localize("Cannot use more than one tool without tool changer."));
    return;
  }

  var workpiece = getWorkpiece();
  var zStock = unit ? (workpiece.upper.z - workpiece.lower.z) : (workpiece.upper.z - workpiece.lower.z);
  writeln("&PWMaterial = " + xyzFormat.format(zStock));
  var partDatum = workpiece.lower.z;
  if (partDatum > 0) {
    writeln("&PWZorigin = Table Surface");
  } else {
    writeln("&PWZorigin = Part Surface");
  }
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
  if (!machineConfiguration.isMultiAxisConfiguration()) {
    return; // ignore
  }

  if (!((currentWorkPlaneABC == undefined) ||
        abcFormat.areDifferent(abc.x, currentWorkPlaneABC.x) ||
        abcFormat.areDifferent(abc.y, currentWorkPlaneABC.y) ||
        abcFormat.areDifferent(abc.z, currentWorkPlaneABC.z))) {
    return; // no change
  }

  // NOTE: add retract here

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

  var tcp = false;
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
  
  if (machineConfiguration.isMultiAxisConfiguration()) { // use 5-axis indexing for multi-axis mode
    // set working plane after datum shift

    var abc = new Vector(0, 0, 0);
    if (currentSection.isMultiAxis()) {
      cancelTransformation();
    } else {
      abc = getWorkPlaneMachineABC(currentSection.workPlane);
    }
    setWorkPlane(abc);
  } else { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  feedOutput.reset();

  if (insertToolCall && properties.useToolChanger) {
    forceWorkPlane();
    
    retracted = true;

    if (tool.number > 99) {
      warning(localize("Tool number exceeds maximum value."));
    }
    if (isFirstSection() ||
        currentSection.getForceToolChange && currentSection.getForceToolChange() ||
        (tool.number != getPreviousSection().getTool().number)) {
      writeln("C7"); // call macro 7
      writeln("&Tool = " + tool.number);
      writeln("C9"); // call macro 9
    }
    if (tool.comment) {
      writeln("&ToolName = " + tool.comment);
    }
  }

/*
  if (!properties.useToolChanger) {
    // we only allow a single tool without a tool changer
    writeBlock("PAUSE"); // wait for user
  }
*/

  { // always output spindle speed
    if (tool.spindleRPM < 5000) {
      warning(localize("Spindle speed is below minimum value."));
    }
    if (tool.spindleRPM > 24000) {
      warning(localize("Spindle speed exceeds maximum value."));
    }

    writeBlock("TR", rpmFormat.format(tool.spindleRPM));
    writeln("C6");
    writeln("PAUSE 2"); // wait for 2 seconds for spindle to ramp up
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
  var retracted = false;
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock("J3", zOutput.format(initialPosition.z));
    }
  }

  if (false /*insertToolCall*/) {
    writeBlock(
      "J3",
      xOutput.format(initialPosition.x),
      yOutput.format(initialPosition.y),
      zOutput.format(initialPosition.z)
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
    error(localize("Spindle speed out of range."));
    return;
  }
  if (tool.spindleRPM > 24000) {
    warning(localize("Spindle speed exceeds maximum value."));
  }
  writeBlock("TR", rpmFormat.format(spindleSpeed));
  writeln("C6");
  writeln("PAUSE 1"); // wait for 1 seconds for spindle to ramp up
}

function onRadiusCompensation() {
}

function writeFeed(feed, moveInZ) {
  if (moveInZ) { // limit feed if moving in Z
    feed = Math.min(feed, maxZFeed);
  }
  var f = feedOutput.format(feed);
  if (f) {
    writeBlock("MS", f, feedZOutput.format(Math.min(feed, maxZFeed)));
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
  writeFeed(feed, !!z);
  if (x || y || z) {
    writeBlock("M3", x, y, z);
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  if (!currentSection.isOptimizedForMachine()) {
    error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    return;
  }

  var displacement = machineConfiguration.getDirection(new Vector(_a, _b, _c));
  displacement.multiply(headOffset); // control will compensate for tool length
  displacement = Vector.diff(displacement, new Vector(0, 0, headOffset));
  var x = xOutput.format2(_x + displacement.x);
  var y = yOutput.format2(_y + displacement.y);
  var z = zOutput.format2(_z + displacement.z);

  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  writeBlock("J5", x, y, z, a, b);
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  if (!currentSection.isOptimizedForMachine()) {
    error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    return;
  }

  var displacement = machineConfiguration.getDirection(new Vector(_a, _b, _c));
  displacement.multiply(headOffset); // control will compensate for tool length
  displacement = Vector.diff(displacement, new Vector(0, 0, headOffset));
  var x = xOutput.format2(_x + displacement.x);
  var y = yOutput.format2(_y + displacement.y);
  var z = zOutput.format2(_z + displacement.z);

  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  writeFeed(feed, !!z);
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
    writeFeed(feed, false);
    writeBlock("CG", "", xOutput.format(x), yOutput.format(y), xyzFormat.format(cx - start.x), xyzFormat.format(cy - start.y), "", clockwise ? 1 : -1);
    break;
  default:
    linearize(tolerance);
  }
}

function onCommand(command) {
}

function onSectionEnd() {
  xOutput.offset = 0;
  yOutput.offset = 0;
  zOutput.offset = 0;
  forceAny();
}

function onClose() {
  if (properties.useToolChanger) {
    writeln("C7"); // call macro 7
  }
  writeBlock("JH");

  setWorkPlane(new Vector(0, 0, 0)); // reset working plane

  writeBlock("END");
  writeln("");
  writeln("");
  writeBlock("UNIT_ERROR:");
  writeBlock("CN, 91");
  writeBlock("END");
}
