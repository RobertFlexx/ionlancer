IMPLEMENTATION MODULE Input;

IMPORT SDL2;

CONST
  SC_A = 4; SC_D = 7; SC_F = 9; SC_M = 16; SC_P = 19; SC_S = 22; SC_W = 26;
  SC_X = 27; SC_Z = 29; SC_RETURN = 40; SC_ESCAPE = 41; SC_SPACE = 44;
  SC_BACKSPACE = 42; SC_PERIOD = 55;
  SC_KP_1 = 89; SC_KP_0 = 98; SC_KP_PERIOD = 99;
  SC_F11 = 68; SC_RIGHT = 79; SC_LEFT = 80; SC_DOWN = 81; SC_UP = 82;
  SC_LCTRL = 224; SC_LSHIFT = 225; SC_LGUI = 227;
  SC_RCTRL = 228; SC_RGUI = 231;
  PAD_AXIS_LEFTX = 0; PAD_AXIS_LEFTY = 1;
  PAD_AXIS_RIGHTX = 2; PAD_AXIS_RIGHTY = 3;
  PAD_AXIS_TRIGGERLEFT = 4; PAD_AXIS_TRIGGERRIGHT = 5;
  PAD_BUTTON_A = 0; PAD_BUTTON_B = 1; PAD_BUTTON_X = 2; PAD_BUTTON_Y = 3;
  PAD_BUTTON_BACK = 4; PAD_BUTTON_START = 6;
  PAD_BUTTON_RIGHTSTICK = 8;
  PAD_BUTTON_LEFTSHOULDER = 9; PAD_BUTTON_RIGHTSHOULDER = 10;
  PAD_BUTTON_DPAD_UP = 11; PAD_BUTTON_DPAD_DOWN = 12;
  PAD_BUTTON_DPAD_LEFT = 13; PAD_BUTTON_DPAD_RIGHT = 14;
  PAD_DEADZONE = 10000; PAD_TRIGGER_DEADZONE = 12000;
  RepeatDelayMs = 300; RepeatIntervalMs = 110;
  MaxPads = 8;

VAR
  current, previous, pressedLatch : ARRAY Action OF BOOLEAN;
  keyState, oldKeyState, padState : ARRAY Action OF BOOLEAN;
  slotState, oldSlotState : ARRAY [0..MaxPads-1] OF ARRAY Action OF BOOLEAN;
  menuPulse : ARRAY Action OF BOOLEAN;
  navStart, navLast : ARRAY Action OF CARDINAL;
  controllers : ARRAY [0..MaxPads-1] OF SDL2.SDL_GameController;
  instanceID : ARRAY [0..MaxPads-1] OF INTEGER;
  families : ARRAY [0..MaxPads-1] OF PadFamily;
  activeSlot : INTEGER;
  controllerActive : BOOLEAN;
  initAction : Action;
  typedNumber : INTEGER;
  typedPoint, typedErase, oldPoint, oldErase : BOOLEAN;
  oldDigits, oldKeypad : ARRAY [0..9] OF BOOLEAN;

PROCEDURE KeyDown(code : CARDINAL) : BOOLEAN;
VAR n : INTEGER; keys : SDL2.SDL_KeyStatePtr;
BEGIN
  keys := SDL2.SDL_GetKeyboardState(n);
  IF keys = NIL THEN RETURN FALSE END;
  IF (code > 511) OR (n <= 0) OR (VAL(INTEGER, code) >= n) THEN RETURN FALSE END;
  RETURN keys^[code] # 0
END KeyDown;

PROCEDURE FindControllers;
VAR i, count, kind, id, slot, freeSlot, j : INTEGER; found : BOOLEAN; a : Action;
BEGIN
  FOR slot := 0 TO MaxPads-1 DO
    IF controllers[slot] # NIL THEN
      IF SDL2.SDL_GameControllerGetAttached(controllers[slot]) = 0 THEN
        SDL2.SDL_GameControllerClose(controllers[slot]);
        controllers[slot] := NIL;
        IF activeSlot = slot THEN activeSlot := -1; controllerActive := FALSE END;
        FOR a := Left TO FastEdit DO
          slotState[slot][a] := FALSE; oldSlotState[slot][a] := FALSE
        END
      END
    END
  END;
  count := SDL2.SDL_NumJoysticks();
  i := 0;
  WHILE i < count DO
    IF SDL2.SDL_IsGameController(i) # 0 THEN
      id := SDL2.SDL_JoystickGetDeviceInstanceID(i);
      found := FALSE; freeSlot := -1;
      FOR j := 0 TO MaxPads-1 DO
        IF (controllers[j] # NIL) AND (instanceID[j] = id) THEN found := TRUE END;
        IF (controllers[j] = NIL) AND (freeSlot < 0) THEN freeSlot := j END
      END;
      IF NOT found AND (freeSlot >= 0) THEN
        controllers[freeSlot] := SDL2.SDL_GameControllerOpen(i);
        IF controllers[freeSlot] # NIL THEN
          instanceID[freeSlot] := id;
          kind := SDL2.SDL_GameControllerGetType(controllers[freeSlot]);
          CASE kind OF
            1, 2, 8, 9, 10 : families[freeSlot] := XboxPad
          | 3, 4, 7 : families[freeSlot] := PlayStationPad
          | 5, 11, 12, 13 : families[freeSlot] := NintendoPad
          ELSE families[freeSlot] := GenericPad
          END;
          FOR a := Left TO FastEdit DO
            slotState[freeSlot][a] := FALSE;
            oldSlotState[freeSlot][a] := FALSE
          END
        END
      END
    END;
    INC(i)
  END
END FindControllers;

PROCEDURE Init;
VAR a : Action; slot, digit : INTEGER;
BEGIN
  controllerActive := FALSE; activeSlot := -1;
  typedNumber := -1; typedPoint := FALSE; typedErase := FALSE;
  oldPoint := FALSE; oldErase := FALSE;
  FOR digit := 0 TO 9 DO oldDigits[digit] := FALSE; oldKeypad[digit] := FALSE END;
  FOR a := Left TO FastEdit DO
    current[a] := FALSE; previous[a] := FALSE; pressedLatch[a] := FALSE;
    keyState[a] := FALSE; oldKeyState[a] := FALSE;
    padState[a] := FALSE;
    menuPulse[a] := FALSE; navStart[a] := 0; navLast[a] := 0
  END;
  FOR slot := 0 TO MaxPads-1 DO
    controllers[slot] := NIL; instanceID[slot] := -1;
    families[slot] := GenericPad;
    FOR a := Left TO FastEdit DO
      slotState[slot][a] := FALSE; oldSlotState[slot][a] := FALSE
    END
  END;
  FindControllers
END Init;

PROCEDURE Shutdown;
VAR slot : INTEGER;
BEGIN
  FOR slot := 0 TO MaxPads-1 DO
    IF controllers[slot] # NIL THEN
      SDL2.SDL_GameControllerClose(controllers[slot]); controllers[slot] := NIL
    END
  END;
  activeSlot := -1; controllerActive := FALSE
END Shutdown;

PROCEDURE PadButton(slot, button : INTEGER) : BOOLEAN;
BEGIN
  IF controllers[slot] = NIL THEN RETURN FALSE END;
  RETURN SDL2.SDL_GameControllerGetButton(controllers[slot], button) # 0
END PadButton;

PROCEDURE PadAxis(slot, axis : INTEGER) : INTEGER;
BEGIN
  IF controllers[slot] = NIL THEN RETURN 0 END;
  RETURN VAL(INTEGER, SDL2.SDL_GameControllerGetAxis(controllers[slot], axis))
END PadAxis;

PROCEDURE IsMac() : BOOLEAN;
VAR platform : SDL2.SDL_CString;
BEGIN
  platform := SDL2.SDL_GetPlatform();
  IF platform = NIL THEN RETURN FALSE END;
  RETURN (platform^[0] = 'M') AND (platform^[1] = 'a') AND
         (platform^[2] = 'c')
END IsMac;

PROCEDURE Poll;
VAR a : Action; slot, digit : INTEGER; now : CARDINAL;
    keyActivity, padActivity, macShortcut, commandDown : BOOLEAN;
    down, keypadDown, pointDown, eraseDown : BOOLEAN;
BEGIN
  SDL2.SDL_PumpEvents;
  FindControllers;
  now := VAL(CARDINAL, SDL2.SDL_GetTicks());
  FOR a := Left TO FastEdit DO
    previous[a] := current[a];
    oldKeyState[a] := keyState[a]
  END;
  FOR slot := 0 TO MaxPads-1 DO
    FOR a := Left TO FastEdit DO oldSlotState[slot][a] := slotState[slot][a] END
  END;

  commandDown := KeyDown(SC_LGUI) OR KeyDown(SC_RGUI);
  macShortcut := IsMac() AND commandDown AND
                 (KeyDown(SC_RETURN) OR
                  ((KeyDown(SC_LCTRL) OR KeyDown(SC_RCTRL)) AND KeyDown(SC_F)));

  keyState[Left] := KeyDown(SC_LEFT) OR KeyDown(SC_A);
  keyState[Right] := KeyDown(SC_RIGHT) OR KeyDown(SC_D);
  keyState[Up] := KeyDown(SC_UP) OR KeyDown(SC_W);
  keyState[Down] := KeyDown(SC_DOWN) OR KeyDown(SC_S);
  keyState[Fire] := KeyDown(SC_SPACE) OR KeyDown(SC_Z);
  keyState[AltFire] := KeyDown(SC_X) OR KeyDown(SC_LSHIFT);
  keyState[Start] := (KeyDown(SC_RETURN) AND NOT macShortcut) OR KeyDown(SC_Z);
  keyState[Pause] := KeyDown(SC_P);
  keyState[Menu] := KeyDown(SC_M);
  keyState[Fullscreen] := KeyDown(SC_F11) OR macShortcut;
  keyState[Back] := KeyDown(SC_ESCAPE);
  keyState[Cancel] := KeyDown(SC_ESCAPE);
  keyState[SwitchRole] := KeyDown(SC_X) OR KeyDown(SC_LSHIFT);
  keyState[FastEdit] := KeyDown(SC_LCTRL) OR KeyDown(SC_RCTRL);

  typedNumber := -1;
  FOR digit := 0 TO 9 DO
    IF digit = 0 THEN
      down := KeyDown(39);
      keypadDown := KeyDown(SC_KP_0)
    ELSE
      down := KeyDown(VAL(CARDINAL, 29+digit));
      keypadDown := KeyDown(VAL(CARDINAL, SC_KP_1+digit-1))
    END;
    IF (down AND NOT oldDigits[digit]) OR
       (keypadDown AND NOT oldKeypad[digit]) THEN typedNumber := digit END;
    oldDigits[digit] := down; oldKeypad[digit] := keypadDown
  END;
  pointDown := KeyDown(SC_PERIOD) OR KeyDown(SC_KP_PERIOD);
  eraseDown := KeyDown(SC_BACKSPACE);
  typedPoint := pointDown AND NOT oldPoint;
  typedErase := eraseDown AND NOT oldErase;
  oldPoint := pointDown; oldErase := eraseDown;

  FOR a := Left TO FastEdit DO padState[a] := FALSE END;
  keyActivity := FALSE; padActivity := FALSE;
  FOR slot := 0 TO MaxPads-1 DO
    slotState[slot][Left] := PadButton(slot, PAD_BUTTON_DPAD_LEFT) OR
                            (PadAxis(slot, PAD_AXIS_LEFTX) < -PAD_DEADZONE) OR
                            (PadAxis(slot, PAD_AXIS_RIGHTX) < -PAD_DEADZONE);
    slotState[slot][Right] := PadButton(slot, PAD_BUTTON_DPAD_RIGHT) OR
                             (PadAxis(slot, PAD_AXIS_LEFTX) > PAD_DEADZONE) OR
                             (PadAxis(slot, PAD_AXIS_RIGHTX) > PAD_DEADZONE);
    slotState[slot][Up] := PadButton(slot, PAD_BUTTON_DPAD_UP) OR
                          (PadAxis(slot, PAD_AXIS_LEFTY) < -PAD_DEADZONE) OR
                          (PadAxis(slot, PAD_AXIS_RIGHTY) < -PAD_DEADZONE);
    slotState[slot][Down] := PadButton(slot, PAD_BUTTON_DPAD_DOWN) OR
                            (PadAxis(slot, PAD_AXIS_LEFTY) > PAD_DEADZONE) OR
                            (PadAxis(slot, PAD_AXIS_RIGHTY) > PAD_DEADZONE);
    slotState[slot][Fire] := PadButton(slot, PAD_BUTTON_A) OR
                            (PadAxis(slot, PAD_AXIS_TRIGGERRIGHT) > PAD_TRIGGER_DEADZONE);
    slotState[slot][AltFire] := PadButton(slot, PAD_BUTTON_X) OR
                               PadButton(slot, PAD_BUTTON_B) OR
                               PadButton(slot, PAD_BUTTON_Y) OR
                               PadButton(slot, PAD_BUTTON_LEFTSHOULDER) OR
                               PadButton(slot, PAD_BUTTON_RIGHTSHOULDER) OR
                               (PadAxis(slot, PAD_AXIS_TRIGGERLEFT) > PAD_TRIGGER_DEADZONE);
    slotState[slot][Start] := PadButton(slot, PAD_BUTTON_START);
    slotState[slot][Pause] := PadButton(slot, PAD_BUTTON_START);
    slotState[slot][Menu] := PadButton(slot, PAD_BUTTON_BACK);
    slotState[slot][Fullscreen] := PadButton(slot, PAD_BUTTON_RIGHTSTICK);
    slotState[slot][Back] := FALSE;
    slotState[slot][Cancel] := PadButton(slot, PAD_BUTTON_B);
    slotState[slot][SwitchRole] := PadButton(slot, PAD_BUTTON_X) OR
                                   PadButton(slot, PAD_BUTTON_Y) OR
                                   PadButton(slot, PAD_BUTTON_LEFTSHOULDER);
    slotState[slot][FastEdit] := PadButton(slot, PAD_BUTTON_RIGHTSHOULDER);
    FOR a := Left TO FastEdit DO
      padState[a] := padState[a] OR slotState[slot][a];
      IF slotState[slot][a] AND NOT oldSlotState[slot][a] THEN
        padActivity := TRUE;
        activeSlot := slot
      END
    END
  END;

  FOR a := Left TO FastEdit DO
    current[a] := keyState[a] OR padState[a];
    IF keyState[a] AND NOT oldKeyState[a] THEN keyActivity := TRUE END;
    IF current[a] AND NOT previous[a] THEN pressedLatch[a] := TRUE END;
    IF (a = Left) OR (a = Right) OR (a = Up) OR (a = Down) THEN
      IF current[a] THEN
        IF NOT previous[a] OR (now < navStart[a]) THEN
          navStart[a] := now; navLast[a] := now
        ELSIF (now - navStart[a] >= RepeatDelayMs) AND
              (now - navLast[a] >= RepeatIntervalMs) THEN
          menuPulse[a] := TRUE; navLast[a] := now
        END
      ELSE navStart[a] := 0; navLast[a] := 0
      END
    END
  END;
  IF padActivity THEN controllerActive := TRUE
  ELSIF keyActivity OR (typedNumber >= 0) OR typedPoint OR typedErase THEN
    controllerActive := FALSE
  END
END Poll;

PROCEDURE Held(action : Action) : BOOLEAN;
BEGIN RETURN current[action] END Held;

PROCEDURE Pressed(action : Action) : BOOLEAN;
BEGIN RETURN pressedLatch[action] END Pressed;

PROCEDURE TakePressed(action : Action) : BOOLEAN;
VAR result : BOOLEAN;
BEGIN
  result := pressedLatch[action]; pressedLatch[action] := FALSE;
  RETURN result
END TakePressed;

PROCEDURE MenuStep(action : Action) : BOOLEAN;
BEGIN RETURN pressedLatch[action] OR menuPulse[action] END MenuStep;

PROCEDURE ClearPressed;
VAR a : Action;
BEGIN
  FOR a := Left TO FastEdit DO pressedLatch[a] := FALSE; menuPulse[a] := FALSE END;
  typedNumber := -1; typedPoint := FALSE; typedErase := FALSE
END ClearPressed;

PROCEDURE TypedDigit() : INTEGER;
BEGIN RETURN typedNumber END TypedDigit;

PROCEDURE TypedDot() : BOOLEAN;
BEGIN RETURN typedPoint END TypedDot;

PROCEDURE TypedBackspace() : BOOLEAN;
BEGIN RETURN typedErase END TypedBackspace;

PROCEDURE UsingController() : BOOLEAN;
BEGIN
  IF activeSlot < 0 THEN RETURN FALSE END;
  RETURN controllerActive AND (controllers[activeSlot] # NIL)
END UsingController;

PROCEDURE ControllerFamily() : PadFamily;
BEGIN
  IF activeSlot < 0 THEN RETURN GenericPad END;
  RETURN families[activeSlot]
END ControllerFamily;

BEGIN
  controllerActive := FALSE; activeSlot := -1;
  FOR initAction := Left TO FastEdit DO
    current[initAction] := FALSE; previous[initAction] := FALSE;
    pressedLatch[initAction] := FALSE;
    keyState[initAction] := FALSE; oldKeyState[initAction] := FALSE;
    padState[initAction] := FALSE;
    menuPulse[initAction] := FALSE;
    navStart[initAction] := 0; navLast[initAction] := 0
  END
END Input.
