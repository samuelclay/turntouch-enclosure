/**
  Copyright (C) 2012-2014 by Autodesk, Inc.
  All rights reserved.

  ShopBot OpenSBP post processor configuration.

  $Revision: 38310 $
  $Date: 2014-12-22 10:46:18 +0100 (ma, 22 dec 2014) $
  
  FORKID {866F31A2-119D-485c-B228-090CC89C9BE8}
*/

description = "ShopBot OpenSBP";
vendor = "Autodesk, Inc.";
vendorUrl = "http://www.autodesk.com";
legal = "Copyright (C) 2012-2014 by Autodesk, Inc.";
certificationLevel = 2;
minimumRevision = 24000;

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



// user-defined properties
properties = {
  useToolChanger: true // specifies that a tool changer is available
};

function CustomVariable(specifiers, format) {
  if (!(this instanceof arguments.callee)) {
    throw new Error(localize("CustomVariable constructor called as a function."));
  }
  this.variable = createVariable(specifiers, format);
  this.offset = 0;
}

CustomVariable.prototype.format = function (value) {
  return this.variable.format(value + this.offset);
};

CustomVariable.prototype.reset = function () {
  return this.variable.reset();
};

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var abcFormat = createFormat({decimals:3, scale:DEG});
var feedFormat = createFormat({decimals:(unit == MM ? 0 : 1)});
var secFormat = createFormat({decimals:2}); // seconds

var xOutput = new CustomVariable({force:true}, xyzFormat);
var yOutput = new CustomVariable({force:true}, xyzFormat);
var zOutput = new CustomVariable({force:true}, xyzFormat);
var aOutput = createVariable({force:true}, abcFormat);
var bOutput = createVariable({force:true}, abcFormat);
var feedOutput = createVariable({}, feedFormat);

// the gauge length + the tool length
var pivotDistance = toPreciseUnit(6.0 /*6.0 + 2.5*/, IN); // 2.5in is assumed for the tool length

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

  if (false) { // note: setup your machine here
    var aAxis = createAxis({coordinate:0, table:false, axis:[0, 0, 1], range:[-360,360], cyclic:true, preference:1});
    var bAxis = createAxis({coordinate:1, table:false, axis:[1, 0, 0], range:[-120,120], preference:1});
    machineConfiguration = new MachineConfiguration(bAxis, aAxis);

    setMachineConfiguration(machineConfiguration);
    optimizeMachineAngles2(0); // TCP mode - we compensate below
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

  switch (unit) {
  case IN:
    writeBlock("VD, , , 0");
    break;
  case MM:
    writeBlock("VD, , , 1");
    break;
  };

/*
  if (hasParameter("operation:clearanceHeightOffset")) {
    var safeZ = getParameter("operation:clearanceHeightOffset");
    writeln("&PWSafeZ = " + safeZ);
  }
*/

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

  var tcp = true;
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
      writeln("&Tool = " + tool.number);
      writeln("C9");
      
      if (tool.spindleRPM < 1) {
        error(localize("Spindle speed out of range."));
        return;
      }
      if (tool.spindleRPM > 99999) {
        warning(localize("Spindle speed exceeds maximum value."));
      }

      writeBlock("TR", tool.spindleRPM);
      writeln("C6");
    }
    if (tool.comment) {
      writeln("&ToolName = " + tool.comment);
    }
  }
  
  if (!properties.useToolChanger) {
    writeBlock("PAUSE"); // wait for user
  }

  headOffset = /*tool.bodyLength +*/ pivotDistance; // control will compensate for tool length

  if (true) {
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
  }

  forceAny();

  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  var retracted = false;
  if (!retracted) {
    if (getCurrentPosition().z < initialPosition.z) {
      writeBlock("JZ", zOutput.format(initialPosition.z));
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
  writeBlock("TR", spindleSpeed);
}

function onRadiusCompensation() {
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
  var f = feedOutput.format(feed/60);
  if (f) {
    writeBlock("VS", f, f);
  }
  if (x || y || z) {
    writeBlock("M3", x, y, z);
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  if (!currentSection.isOptimizedForMachine()) {
    error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    return;
  }
  var x;
  var y;
  var z;
  if (true) {
    // TAG: need extra points
    var displacement = machineConfiguration.getDirection(new Vector(_a, _b, _c));
    displacement.multiply(headOffset); // control will compensate for tool length
    displacement = Vector.diff(displacement, new Vector(0, 0, headOffset));
    // writeComment("DISPLACEMENT: X" + xyzFormat.format(displacement.x) + " Y" + xyzFormat.format(displacement.y) + " Z" + xyzFormat.format(displacement.z));
    x = xOutput.format(_x + displacement.x);
    y = yOutput.format(_y + displacement.y);
    z = zOutput.format(_z + displacement.z);
  } else {
    x = xOutput.format(_x);
    y = yOutput.format(_y);
    z = zOutput.format(_z);
  }

  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  writeBlock("J5", x, y, z, a, b);
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  if (!currentSection.isOptimizedForMachine()) {
    error(localize("This post configuration has not been customized for 5-axis simultaneous toolpath."));
    return;
  }
  var x;
  var y;
  var z;
  if (true) {
    // TAG: need extra points
    var displacement = machineConfiguration.getDirection(new Vector(_a, _b, _c));
    displacement.multiply(headOffset); // control will compensate for tool length
    displacement = Vector.diff(displacement, new Vector(0, 0, headOffset));
    // writeComment("DISPLACEMENT: X" + xyzFormat.format(displacement.x) + " Y" + xyzFormat.format(displacement.y) + " Z" + xyzFormat.format(displacement.z));
    x = xOutput.format(_x + displacement.x);
    y = yOutput.format(_y + displacement.y);
    z = zOutput.format(_z + displacement.z);
  } else {
    x = xOutput.format(_x);
    y = yOutput.format(_y);
    z = zOutput.format(_z);
  }

  var a = aOutput.format(_a);
  var b = bOutput.format(_b);
  var f = feedOutput.format(feed/60);
  if (f) {
    writeBlock("VS", f, f);
  }
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

  var f = feedOutput.format(feed/60);
  if (f) {
    writeBlock("VS", f, f);
  }

  switch (getCircularPlane()) {
  case PLANE_XY:
    writeBlock("CG", "", xOutput.format(x), yOutput.format(y), xyzFormat.format(cx - start.x), xyzFormat.format(cy - start.y), "", clockwise ? 1 : -1);
    break;
  default:
    linearize(tolerance);
  }
}

function onCommand(command) {
}

function onSectionEnd() {
  writeln("C7");
  xOutput.offset = 0;
  yOutput.offset = 0;
  zOutput.offset = 0;
  forceAny();
}

function onClose() {
  writeBlock("JH");

  setWorkPlane(new Vector(0, 0, 0)); // reset working plane
}
