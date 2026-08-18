IMPLEMENTATION MODULE Input;

IMPORT SDL2;

CONST
  SC_A = 4;
  SC_D = 7;
  SC_M = 16;
  SC_P = 19;
  SC_S = 22;
  SC_W = 26;
  SC_X = 27;
  SC_Z = 29;
  SC_RETURN = 40;
  SC_ESCAPE = 41;
  SC_SPACE = 44;
  SC_F11 = 68;
  SC_RIGHT = 79;
  SC_LEFT = 80;
  SC_DOWN = 81;
  SC_UP = 82;
  SC_LSHIFT = 225;

  PAD_AXIS_LEFTX = 0;
  PAD_AXIS_LEFTY = 1;
  PAD_BUTTON_A = 0;
  PAD_BUTTON_B = 1;
  PAD_BUTTON_X = 2;
  PAD_BUTTON_BACK = 4;
  PAD_BUTTON_START = 6;
  PAD_BUTTON_DPAD_UP = 11;
  PAD_BUTTON_DPAD_DOWN = 12;
  PAD_BUTTON_DPAD_LEFT = 13;
  PAD_BUTTON_DPAD_RIGHT = 14;
  PAD_DEADZONE = 10000;

VAR
  current, previous, pressedLatch : ARRAY Action OF BOOLEAN;
  controller : SDL2.SDL_GameController;
  initAction : Action;

PROCEDURE KeyDown(code : CARDINAL) : BOOLEAN;
VAR n : INTEGER; keys : SDL2.SDL_KeyStatePtr;
BEGIN
  keys := SDL2.SDL_GetKeyboardState(n);
  IF keys = NIL THEN RETURN FALSE END;
  IF (code > 511) OR (n <= 0) OR (VAL(INTEGER, code) >= n) THEN RETURN FALSE END;
  RETURN keys^[code] # 0
END KeyDown;

PROCEDURE Init;
VAR a : Action; i, count : INTEGER;
BEGIN
  FOR a := Left TO Back DO
    current[a] := FALSE;
    previous[a] := FALSE;
    pressedLatch[a] := FALSE
  END;
  controller := NIL;
  count := SDL2.SDL_NumJoysticks();
  i := 0;
  WHILE (i < count) AND (controller = NIL) DO
    IF SDL2.SDL_IsGameController(i) # 0 THEN controller := SDL2.SDL_GameControllerOpen(i) END;
    INC(i)
  END
END Init;

PROCEDURE Shutdown;
BEGIN
  IF controller # NIL THEN SDL2.SDL_GameControllerClose(controller); controller := NIL END
END Shutdown;

PROCEDURE PadButton(button : INTEGER) : BOOLEAN;
BEGIN
  IF controller = NIL THEN RETURN FALSE END;
  RETURN SDL2.SDL_GameControllerGetButton(controller, button) # 0
END PadButton;

PROCEDURE PadAxis(axis : INTEGER) : INTEGER;
BEGIN
  IF controller = NIL THEN RETURN 0 END;
  RETURN VAL(INTEGER, SDL2.SDL_GameControllerGetAxis(controller, axis))
END PadAxis;

PROCEDURE Poll;
VAR a : Action;
BEGIN
  SDL2.SDL_PumpEvents;
  FOR a := Left TO Back DO previous[a] := current[a] END;

  current[Left] := KeyDown(SC_LEFT) OR KeyDown(SC_A) OR
                   PadButton(PAD_BUTTON_DPAD_LEFT) OR (PadAxis(PAD_AXIS_LEFTX) < -PAD_DEADZONE);
  current[Right] := KeyDown(SC_RIGHT) OR KeyDown(SC_D) OR
                    PadButton(PAD_BUTTON_DPAD_RIGHT) OR (PadAxis(PAD_AXIS_LEFTX) > PAD_DEADZONE);
  current[Up] := KeyDown(SC_UP) OR KeyDown(SC_W) OR
                 PadButton(PAD_BUTTON_DPAD_UP) OR (PadAxis(PAD_AXIS_LEFTY) < -PAD_DEADZONE);
  current[Down] := KeyDown(SC_DOWN) OR KeyDown(SC_S) OR
                   PadButton(PAD_BUTTON_DPAD_DOWN) OR (PadAxis(PAD_AXIS_LEFTY) > PAD_DEADZONE);
  current[Fire] := KeyDown(SC_SPACE) OR KeyDown(SC_Z) OR PadButton(PAD_BUTTON_A);
  current[AltFire] := KeyDown(SC_X) OR KeyDown(SC_LSHIFT) OR
                      PadButton(PAD_BUTTON_B) OR PadButton(PAD_BUTTON_X);
  current[Start] := KeyDown(SC_RETURN) OR KeyDown(SC_Z) OR PadButton(PAD_BUTTON_START);
  current[Pause] := KeyDown(SC_P) OR PadButton(PAD_BUTTON_START);
  current[Menu] := KeyDown(SC_M) OR PadButton(PAD_BUTTON_BACK);
  current[Fullscreen] := KeyDown(SC_F11);
  current[Back] := KeyDown(SC_ESCAPE);

  (* Tiny taps used to disappear between ticks. Keep them around until the game actually sees them. *)
  FOR a := Left TO Back DO
    IF current[a] AND NOT previous[a] THEN pressedLatch[a] := TRUE END
  END
END Poll;

PROCEDURE Held(action : Action) : BOOLEAN;
BEGIN
  RETURN current[action]
END Held;

PROCEDURE Pressed(action : Action) : BOOLEAN;
BEGIN
  RETURN pressedLatch[action]
END Pressed;

PROCEDURE TakePressed(action : Action) : BOOLEAN;
VAR result : BOOLEAN;
BEGIN
  result := pressedLatch[action];
  pressedLatch[action] := FALSE;
  RETURN result
END TakePressed;

PROCEDURE ClearPressed;
VAR a : Action;
BEGIN
  FOR a := Left TO Back DO pressedLatch[a] := FALSE END
END ClearPressed;

BEGIN
  controller := NIL;
  FOR initAction := Left TO Back DO
    current[initAction] := FALSE;
    previous[initAction] := FALSE;
    pressedLatch[initAction] := FALSE
  END
END Input.
