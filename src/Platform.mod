IMPLEMENTATION MODULE Platform;

FROM SYSTEM IMPORT ADR, CARDINAL32;
IMPORT SDL2, FrameBuffer, Input, Audio;

CONST
  SDL_INIT_TIMER = 1;
  SDL_INIT_AUDIO = 16;
  SDL_INIT_VIDEO = 32;
  SDL_INIT_EVENTS = 16384;

  SDL_WINDOW_SHOWN = 4;
  SDL_WINDOW_RESIZABLE = 32;
  SDL_WINDOW_ALLOW_HIGHDPI = 8192;
  SDL_WINDOW_FULLSCREEN_DESKTOP = 4097;
  SDL_WINDOWPOS_CENTERED = 805240832;

  SDL_RENDERER_SOFTWARE = 1;
  SDL_RENDERER_ACCELERATED = 2;
  SDL_RENDERER_PRESENTVSYNC = 4;

  SDL_TEXTUREACCESS_STREAMING = 1;
  SDL_PIXELFORMAT_ARGB8888 = 372645892;
  SDL_SCALEMODE_NEAREST = 0;
  SDL_QUIT = 256;
  MaxEventsPerFrame = 96;

VAR
  window : SDL2.SDL_Window;
  renderer : SDL2.SDL_Renderer;
  texture : SDL2.SDL_Texture;
  quitRequested, fullscreen : BOOLEAN;
  title : ARRAY [0..31] OF CHAR;

PROCEDURE CopyZ(VAR dst : ARRAY OF CHAR; src : ARRAY OF CHAR);
VAR i : CARDINAL;
BEGIN
  i := 0;
  LOOP
    IF (i >= HIGH(dst)) OR (i > HIGH(src)) THEN EXIT END;
    IF ORD(src[i]) = 0 THEN EXIT END;
    dst[i] := src[i];
    INC(i)
  END;
  dst[i] := CHR(0);
  WHILE i < HIGH(dst) DO INC(i); dst[i] := CHR(0) END
END CopyZ;

PROCEDURE CreateSafeRenderer() : SDL2.SDL_Renderer;
VAR result : SDL2.SDL_Renderer;
BEGIN
  (* It is a 320x180 texture. Software rendering is plenty fast and dodges busted GL setups. *)
  result := SDL2.SDL_CreateRenderer(window, -1, VAL(CARDINAL32, SDL_RENDERER_SOFTWARE));
  IF result # NIL THEN RETURN result END;

  result := SDL2.SDL_CreateRenderer(window, -1,
              VAL(CARDINAL32, SDL_RENDERER_ACCELERATED + SDL_RENDERER_PRESENTVSYNC));
  RETURN result
END CreateSafeRenderer;

PROCEDURE Open() : BOOLEAN;
VAR flags : CARDINAL32; soundOK : BOOLEAN;
BEGIN
  window := NIL; renderer := NIL; texture := NIL;
  quitRequested := FALSE; fullscreen := FALSE;
  CopyZ(title, "IONLANCER - GNU MODULA-2");

  flags := VAL(CARDINAL32, SDL_INIT_TIMER + SDL_INIT_AUDIO + SDL_INIT_VIDEO + SDL_INIT_EVENTS);
  IF SDL2.SDL_Init(flags) # 0 THEN RETURN FALSE END;

  window := SDL2.SDL_CreateWindow(ADR(title), SDL_WINDOWPOS_CENTERED,
             SDL_WINDOWPOS_CENTERED, 1280, 720,
             VAL(CARDINAL32, SDL_WINDOW_SHOWN + SDL_WINDOW_RESIZABLE + SDL_WINDOW_ALLOW_HIGHDPI));
  IF window = NIL THEN SDL2.SDL_Quit; RETURN FALSE END;

  (* Resizable, yes. Microscopic unreadable mush, no. *)
  SDL2.SDL_SetWindowMinimumSize(window, 640, 360);

  renderer := CreateSafeRenderer();
  IF renderer = NIL THEN
    SDL2.SDL_DestroyWindow(window); window := NIL; SDL2.SDL_Quit; RETURN FALSE
  END;

  texture := SDL2.SDL_CreateTexture(renderer, VAL(CARDINAL32, SDL_PIXELFORMAT_ARGB8888),
             SDL_TEXTUREACCESS_STREAMING, FrameBuffer.Width, FrameBuffer.Height);
  IF texture = NIL THEN
    SDL2.SDL_DestroyRenderer(renderer); SDL2.SDL_DestroyWindow(window); SDL2.SDL_Quit;
    renderer := NIL; window := NIL; RETURN FALSE
  END;
  SDL2.SDL_SetTextureBlendMode(texture, 0);
  SDL2.SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST);

  Input.Init;
  soundOK := Audio.Init();
  IF NOT soundOK THEN Audio.SetMusic(FALSE) END;
  RETURN TRUE
END Open;

PROCEDURE Close;
BEGIN
  Input.Shutdown;
  Audio.Shutdown;
  IF texture # NIL THEN SDL2.SDL_DestroyTexture(texture); texture := NIL END;
  IF renderer # NIL THEN SDL2.SDL_DestroyRenderer(renderer); renderer := NIL END;
  IF window # NIL THEN SDL2.SDL_DestroyWindow(window); window := NIL END;
  SDL2.SDL_Quit
END Close;

PROCEDURE Poll;
VAR event : SDL2.SDL_Event; count : CARDINAL;
BEGIN
  (* X11 can spam resize events like hell. Give them a budget so the game still gets a frame. *)
  count := 0;
  WHILE (count < MaxEventsPerFrame) AND (SDL2.SDL_PollEvent(event) # 0) DO
    IF event.kind = SDL_QUIT THEN quitRequested := TRUE END;
    INC(count)
  END;
  Input.Poll;
  IF Input.TakePressed(Input.Fullscreen) THEN ToggleFullscreen END
END Poll;

PROCEDURE CalculateDestination(outputW, outputH : INTEGER; VAR dst : SDL2.SDL_Rect);
BEGIN
  IF (outputW <= 0) OR (outputH <= 0) THEN
    dst.x := 0; dst.y := 0; dst.w := 0; dst.h := 0;
    RETURN
  END;

  (* Same aspect check, no float needed. *)
  IF outputW * FrameBuffer.Height <= outputH * FrameBuffer.Width THEN
    dst.w := outputW;
    dst.h := outputW * FrameBuffer.Height DIV FrameBuffer.Width
  ELSE
    dst.h := outputH;
    dst.w := outputH * FrameBuffer.Width DIV FrameBuffer.Height
  END;

  IF dst.w < 1 THEN dst.w := 1 END;
  IF dst.h < 1 THEN dst.h := 1 END;
  dst.x := (outputW - dst.w) DIV 2;
  (* Keep the HUD glued to the top instead of floating under a black bar. *)
  dst.y := 0
END CalculateDestination;

PROCEDURE Present;
VAR outputW, outputH, status : INTEGER; destination : SDL2.SDL_Rect;
BEGIN
  (* Some window managers report zero size for a moment. Just skip that frame. *)
  status := SDL2.SDL_GetRendererOutputSize(renderer, outputW, outputH);
  IF (status = 0) AND (outputW > 0) AND (outputH > 0) THEN
    FrameBuffer.Convert;
    SDL2.SDL_UpdateTexture(texture, NIL, FrameBuffer.RGBAAddress(), FrameBuffer.RGBAPitch());
    SDL2.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    SDL2.SDL_RenderClear(renderer);
    CalculateDestination(outputW, outputH, destination);
    IF (destination.w > 0) AND (destination.h > 0) THEN
      SDL2.SDL_RenderCopy(renderer, texture, NIL, ADR(destination))
    END;
    SDL2.SDL_RenderPresent(renderer)
  END;
  Audio.Update
END Present;

PROCEDURE Ticks() : CARDINAL;
BEGIN
  RETURN VAL(CARDINAL, SDL2.SDL_GetTicks())
END Ticks;

PROCEDURE Sleep(ms : CARDINAL);
BEGIN
  SDL2.SDL_Delay(ms)
END Sleep;

PROCEDURE ShouldQuit() : BOOLEAN;
BEGIN
  RETURN quitRequested
END ShouldQuit;

PROCEDURE RequestQuit;
BEGIN
  quitRequested := TRUE
END RequestQuit;

PROCEDURE ToggleFullscreen;
BEGIN
  fullscreen := NOT fullscreen;
  IF fullscreen THEN
    IF SDL2.SDL_SetWindowFullscreen(window, VAL(CARDINAL32, SDL_WINDOW_FULLSCREEN_DESKTOP)) # 0 THEN
      fullscreen := FALSE
    END
  ELSE
    SDL2.SDL_SetWindowFullscreen(window, VAL(CARDINAL32, 0))
  END
END ToggleFullscreen;

PROCEDURE IsFullscreen() : BOOLEAN;
BEGIN
  RETURN fullscreen
END IsFullscreen;

BEGIN
  window := NIL; renderer := NIL; texture := NIL;
  quitRequested := FALSE; fullscreen := FALSE
END Platform.
