quit:           = false;
window:         *SDL_Window;
window_width :  u32 = 1600;
window_height:  u32 = 800;
mouse_position: Vector2;
keyboard_state: KeyboardState;
mouse_state:    MouseState;

platform_init :: () -> success: bool {
  SDL_Init(SDL_INIT_AUDIO);
  window = SDL_CreateWindow(
      "tempest",
      xx window_width,
      xx window_height,
      SDL_WINDOW_VULKAN, // | SDL_WINDOW_RESIZABLE,
  );
  if !window {
    log_error("Cannot create SDL window: %\n", SDL_GetError());
    return false;
  }
  if !SDL_ShowWindow(window) {
      log_error("Cannot show a window: %", SDL_GetError());
      return false;
  }
  return true;
}

platform_quit :: () {
  SDL_DestroyWindow(window);
  SDL_Quit();
}

platform_vulkan_proc_addr :: () -> vk.PFN_vkGetInstanceProcAddr  {
  return xx SDL_Vulkan_GetVkGetInstanceProcAddr();
}

platform_vulkan_extensions :: () -> []*u8 {
  count: u32 = ---;
  data := SDL_Vulkan_GetInstanceExtensions(*count);
  slice: []*u8 = ---;
  slice.data = data;
  slice.count = count;
  return slice;
}

platform_create_surface :: (instance: vk.VkInstance, surface: *vk.VkSurfaceKHR) {
  if !SDL_Vulkan_CreateSurface(window, xx instance, null, xx surface)
    log_error("Cannot create Vulkan surface. Error: %", SDL_GetError());
}

platform_read_entire_file :: (path: string) -> string, bool {
  data, ok := read_entire_file(path);
  return data, ok;
}

platform_new_frame :: () {
  if !SDL_GetWindowSize(window, xx *window_width, xx *window_height)
    log_error("Cannot get window size. Error: %\n", to_string(SDL_GetError()));
  SDL_GetMouseState(*mouse_position.x, *mouse_position.y);

  new_frame(*keyboard_state);
  new_frame(*mouse_state);

  events: [64]SDL_Event = ---;
  SDL_FlushEvents(xx SDL_EventType.FIRST, xx SDL_EventType.LAST);
  SDL_PumpEvents();
  n_events := SDL_PeepEvents(
    events.data,
    events.count,
    .PEEKEVENT,
    xx SDL_EventType.FIRST,
    xx SDL_EventType.LAST
  );
  for 0..n_events -1 {
    event := events[it];
    if event.type == {
      case xx SDL_EventType.SDL_EVENT_QUIT;
        quit = true;
      // Skip this as it is triggered on key presses
      case xx SDL_EventType.TEXT_INPUT;
      case xx SDL_EventType.KEY_DOWN;
          key := key_from_scancode(xx event.key.key);
          set_pressed(*keyboard_state, xx key);
      case xx SDL_EventType.KEY_UP;
          key := key_from_scancode(xx event.key.key);
          set_released(*keyboard_state, xx key);
      case xx SDL_EventType.MOUSE_MOTION;
      case xx SDL_EventType.MOUSE_BUTTON_DOWN;
          set_pressed(*mouse_state, xx event.button.button);
      case xx SDL_EventType.MOUSE_BUTTON_UP;
          set_released(*mouse_state, xx event.button.button);
      case xx SDL_EventType.MOUSE_WHEEL;
      case;
        log("Got unrecognised SDL event type: %", event.type);
    }
  }
}

KeyboardState :: struct {
  pressed:       StaticBitSet(#run enum_elements_count(KeyboardKey));
  just_pressed:  StaticBitSet(#run enum_elements_count(KeyboardKey));
  just_released: StaticBitSet(#run enum_elements_count(KeyboardKey));
}

new_frame :: (ks: *KeyboardState) {
  reset(*ks.just_pressed);
  reset(*ks.just_released);
}

set_pressed :: (ks: *KeyboardState, key: KeyboardKey) {
  set(*ks.pressed, xx key);
  set(*ks.just_pressed, xx key);
  unset(*ks.just_released, xx key);
}

set_released :: (ks: *KeyboardState, key: KeyboardKey) {
  unset(*ks.pressed, xx key);
  unset(*ks.just_pressed, xx key);
  set(*ks.just_released, xx key);
}

pressed :: (ks: KeyboardState, key: KeyboardKey) -> bool {
  return is_set(ks.pressed, xx key);
}

just_pressed :: (ks: KeyboardState, key: KeyboardKey) -> bool {
  return is_set(ks.just_pressed, xx key);
}

just_released :: (ks: *KeyboardState, key: KeyboardKey) -> bool {
  return is_set(ks.just_released, xx key);
}

MouseState :: struct {
  pressed:       StaticBitSet(#run enum_elements_count(MouseKey));
  just_pressed:  StaticBitSet(#run enum_elements_count(MouseKey));
  just_released: StaticBitSet(#run enum_elements_count(MouseKey));
}

new_frame :: (ms: *MouseState) {
  reset(*ms.just_pressed);
  reset(*ms.just_released);
}

set_pressed :: (ms: *MouseState, key: MouseKey) {
  set(*ms.pressed, xx key);
  set(*ms.just_pressed, xx key);
  unset(*ms.just_released, xx key);
}

set_released :: (ms: *MouseState, key: MouseKey) {
  unset(*ms.pressed, xx key);
  unset(*ms.just_pressed, xx key);
  set(*ms.just_released, xx key);
}

pressed :: (ms: MouseState, key: MouseKey) -> bool {
  return is_set(ms.pressed, xx key);
}

just_pressed :: (ms: MouseState, key: MouseKey) -> bool {
  return is_set(ms.just_pressed, xx key);
}

just_released :: (ms: *MouseState, key: MouseKey) -> bool {
  return is_set(ms.just_released, xx key);
}

MouseKey :: enum u8 {
  UNKNOWN      :: 0;
  LMB          :: 1;
  WHEEL        :: 2;
  RMB          :: 3;
  SIDE_BACK    :: 4;
  SIDE_FORWARD :: 5;
  _;
};

KeyboardKey :: enum u32 {
  UNKNOWN;
  RETURN;
  ESCAPE;
  BACKSPACE;
  TAB;
  SPACE;
  EXCLAIM;
  DBLAPOSTROPHE;
  HASH;
  DOLLAR;
  PERCENT;
  AMPERSAND;
  APOSTROPHE;
  LEFTPAREN;
  RIGHTPAREN;
  ASTERISK;
  PLUS;
  COMMA;
  MINUS;
  PERIOD;
  SLASH;
  _0;
  _1;
  _2;
  _3;
  _4;
  _5;
  _6;
  _7;
  _8;
  _9;
  COLON;
  SEMICOLON;
  LESS;
  EQUALS;
  GREATER;
  QUESTION;
  AT;
  LEFTBRACKET;
  BACKSLASH;
  RIGHTBRACKET;
  CARET;
  UNDERSCORE;
  GRAVE;
  A;
  B;
  C;
  D;
  E;
  F;
  G;
  H;
  I;
  J;
  K;
  L;
  M;
  N;
  O;
  P;
  Q;
  R;
  S;
  T;
  U;
  V;
  W;
  X;
  Y;
  Z;
  LEFTBRACE;
  PIPE;
  RIGHTBRACE;
  TILDE;
  DELETE;
  PLUSMINUS;
  CAPSLOCK;
  F1;
  F2;
  F3;
  F4;
  F5;
  F6;
  F7;
  F8;
  F9;
  F10;
  F11;
  F12;
  PRINTSCREEN;
  SCROLLLOCK;
  PAUSE;
  INSERT;
  HOME;
  PAGEUP;
  END;
  PAGEDOWN;
  RIGHT;
  LEFT;
  DOWN;
  UP;
  NUMLOCKCLEAR;
  KP_DIVIDE;
  KP_MULTIPLY;
  KP_MINUS;
  KP_PLUS;
  KP_ENTER;
  KP_1;
  KP_2;
  KP_3;
  KP_4;
  KP_5;
  KP_6;
  KP_7;
  KP_8;
  KP_9;
  KP_0;
  KP_PERIOD;
  APPLICATION;
  POWER;
  KP_EQUALS;
  F13;
  F14;
  F15;
  F16;
  F17;
  F18;
  F19;
  F20;
  F21;
  F22;
  F23;
  F24;
  EXECUTE;
  HELP;
  MENU;
  SELECT;
  STOP;
  AGAIN;
  UNDO;
  CUT;
  COPY;
  PASTE;
  FIND;
  MUTE;
  VOLUMEUP;
  VOLUMEDOWN;
  KP_COMMA;
  KP_EQUALSAS400;
  ALTERASE;
  SYSREQ;
  CANCEL;
  CLEAR;
  PRIOR;
  RETURN2;
  SEPARATOR;
  OUT;
  OPER;
  CLEARAGAIN;
  CRSEL;
  EXSEL;
  KP_00;
  KP_000;
  THOUSANDSSEPARATOR;
  DECIMALSEPARATOR;
  CURRENCYUNIT;
  CURRENCYSUBUNIT;
  KP_LEFTPAREN;
  KP_RIGHTPAREN;
  KP_LEFTBRACE;
  KP_RIGHTBRACE;
  KP_TAB;
  KP_BACKSPACE;
  KP_A;
  KP_B;
  KP_C;
  KP_D;
  KP_E;
  KP_F;
  KP_XOR;
  KP_POWER;
  KP_PERCENT;
  KP_LESS;
  KP_GREATER;
  KP_AMPERSAND;
  KP_DBLAMPERSAND;
  KP_VERTICALBAR;
  KP_DBLVERTICALBAR;
  KP_COLON;
  KP_HASH;
  KP_SPACE;
  KP_AT;
  KP_EXCLAM;
  KP_MEMSTORE;
  KP_MEMRECALL;
  KP_MEMCLEAR;
  KP_MEMADD;
  KP_MEMSUBTRACT;
  KP_MEMMULTIPLY;
  KP_MEMDIVIDE;
  KP_PLUSMINUS;
  KP_CLEAR;
  KP_CLEARENTRY;
  KP_BINARY;
  KP_OCTAL;
  KP_DECIMAL;
  KP_HEXADECIMAL;
  LCTRL;
  LSHIFT;
  LALT;
  LGUI;
  RCTRL;
  RSHIFT;
  RALT;
  RGUI;
  MODE;
  SLEEP;
  WAKE;
  CHANNEL_INCREMENT;
  CHANNEL_DECREMENT;
  MEDIA_PLAY;
  MEDIA_PAUSE;
  MEDIA_RECORD;
  MEDIA_FAST_FORWARD;
  MEDIA_REWIND;
  MEDIA_NEXT_TRACK;
  MEDIA_PREVIOUS_TRACK;
  MEDIA_STOP;
  MEDIA_EJECT;
  MEDIA_PLAY_PAUSE;
  MEDIA_SELECT;
  AC_NEW;
  AC_OPEN;
  AC_CLOSE;
  AC_EXIT;
  AC_SAVE;
  AC_PRINT;
  AC_PROPERTIES;
  AC_SEARCH;
  AC_HOME;
  AC_BACK;
  AC_FORWARD;
  AC_STOP;
  AC_REFRESH;
  AC_BOOKMARKS;
  SOFTLEFT;
  SOFTRIGHT;
  CALL;
  ENDCALL;
  LEFT_TAB;
  LEVEL5_SHIFT;
  MULTI_KEY_COMPOSE;
  LMETA;
  RMETA;
  LHYPER;
  RHYPER;
}

key_from_scancode :: (scancode: SDLKeyboardScancode) -> KeyboardKey {
  result: KeyboardKey = .UNKNOWN;
  if scancode == {
    case .UNKNOWN; result = .UNKNOWN;
    case .RETURN; result = .RETURN;
    case .ESCAPE; result = .ESCAPE;
    case .BACKSPACE; result = .BACKSPACE;
    case .TAB; result = .TAB;
    case .SPACE; result = .SPACE;
    case .EXCLAIM; result = .EXCLAIM;
    case .DBLAPOSTROPHE; result = .DBLAPOSTROPHE;
    case .HASH; result = .HASH;
    case .DOLLAR; result = .DOLLAR;
    case .PERCENT; result = .PERCENT;
    case .AMPERSAND; result = .AMPERSAND;
    case .APOSTROPHE; result = .APOSTROPHE;
    case .LEFTPAREN; result = .LEFTPAREN;
    case .RIGHTPAREN; result = .RIGHTPAREN;
    case .ASTERISK; result = .ASTERISK;
    case .PLUS; result = .PLUS;
    case .COMMA; result = .COMMA;
    case .MINUS; result = .MINUS;
    case .PERIOD; result = .PERIOD;
    case .SLASH; result = .SLASH;
    case ._0; result = ._0;
    case ._1; result = ._1;
    case ._2; result = ._2;
    case ._3; result = ._3;
    case ._4; result = ._4;
    case ._5; result = ._5;
    case ._6; result = ._6;
    case ._7; result = ._7;
    case ._8; result = ._8;
    case ._9; result = ._9;
    case .COLON; result = .COLON;
    case .SEMICOLON; result = .SEMICOLON;
    case .LESS; result = .LESS;
    case .EQUALS; result = .EQUALS;
    case .GREATER; result = .GREATER;
    case .QUESTION; result = .QUESTION;
    case .AT; result = .AT;
    case .LEFTBRACKET; result = .LEFTBRACKET;
    case .BACKSLASH; result = .BACKSLASH;
    case .RIGHTBRACKET; result = .RIGHTBRACKET;
    case .CARET; result = .CARET;
    case .UNDERSCORE; result = .UNDERSCORE;
    case .GRAVE; result = .GRAVE;
    case .A; result = .A;
    case .B; result = .B;
    case .C; result = .C;
    case .D; result = .D;
    case .E; result = .E;
    case .F; result = .F;
    case .G; result = .G;
    case .H; result = .H;
    case .I; result = .I;
    case .J; result = .J;
    case .K; result = .K;
    case .L; result = .L;
    case .M; result = .M;
    case .N; result = .N;
    case .O; result = .O;
    case .P; result = .P;
    case .Q; result = .Q;
    case .R; result = .R;
    case .S; result = .S;
    case .T; result = .T;
    case .U; result = .U;
    case .V; result = .V;
    case .W; result = .W;
    case .X; result = .X;
    case .Y; result = .Y;
    case .Z; result = .Z;
    case .LEFTBRACE; result = .LEFTBRACE;
    case .PIPE; result = .PIPE;
    case .RIGHTBRACE; result = .RIGHTBRACE;
    case .TILDE; result = .TILDE;
    case .DELETE; result = .DELETE;
    case .PLUSMINUS; result = .PLUSMINUS;
    case .CAPSLOCK; result = .CAPSLOCK;
    case .F1; result = .F1;
    case .F2; result = .F2;
    case .F3; result = .F3;
    case .F4; result = .F4;
    case .F5; result = .F5;
    case .F6; result = .F6;
    case .F7; result = .F7;
    case .F8; result = .F8;
    case .F9; result = .F9;
    case .F10; result = .F10;
    case .F11; result = .F11;
    case .F12; result = .F12;
    case .PRINTSCREEN; result = .PRINTSCREEN;
    case .SCROLLLOCK; result = .SCROLLLOCK;
    case .PAUSE; result = .PAUSE;
    case .INSERT; result = .INSERT;
    case .HOME; result = .HOME;
    case .PAGEUP; result = .PAGEUP;
    case .END; result = .END;
    case .PAGEDOWN; result = .PAGEDOWN;
    case .RIGHT; result = .RIGHT;
    case .LEFT; result = .LEFT;
    case .DOWN; result = .DOWN;
    case .UP; result = .UP;
    case .NUMLOCKCLEAR; result = .NUMLOCKCLEAR;
    case .KP_DIVIDE; result = .KP_DIVIDE;
    case .KP_MULTIPLY; result = .KP_MULTIPLY;
    case .KP_MINUS; result = .KP_MINUS;
    case .KP_PLUS; result = .KP_PLUS;
    case .KP_ENTER; result = .KP_ENTER;
    case .KP_1; result = .KP_1;
    case .KP_2; result = .KP_2;
    case .KP_3; result = .KP_3;
    case .KP_4; result = .KP_4;
    case .KP_5; result = .KP_5;
    case .KP_6; result = .KP_6;
    case .KP_7; result = .KP_7;
    case .KP_8; result = .KP_8;
    case .KP_9; result = .KP_9;
    case .KP_0; result = .KP_0;
    case .KP_PERIOD; result = .KP_PERIOD;
    case .APPLICATION; result = .APPLICATION;
    case .POWER; result = .POWER;
    case .KP_EQUALS; result = .KP_EQUALS;
    case .F13; result = .F13;
    case .F14; result = .F14;
    case .F15; result = .F15;
    case .F16; result = .F16;
    case .F17; result = .F17;
    case .F18; result = .F18;
    case .F19; result = .F19;
    case .F20; result = .F20;
    case .F21; result = .F21;
    case .F22; result = .F22;
    case .F23; result = .F23;
    case .F24; result = .F24;
    case .EXECUTE; result = .EXECUTE;
    case .HELP; result = .HELP;
    case .MENU; result = .MENU;
    case .SELECT; result = .SELECT;
    case .STOP; result = .STOP;
    case .AGAIN; result = .AGAIN;
    case .UNDO; result = .UNDO;
    case .CUT; result = .CUT;
    case .COPY; result = .COPY;
    case .PASTE; result = .PASTE;
    case .FIND; result = .FIND;
    case .MUTE; result = .MUTE;
    case .VOLUMEUP; result = .VOLUMEUP;
    case .VOLUMEDOWN; result = .VOLUMEDOWN;
    case .KP_COMMA; result = .KP_COMMA;
    case .KP_EQUALSAS400; result = .KP_EQUALSAS400;
    case .ALTERASE; result = .ALTERASE;
    case .SYSREQ; result = .SYSREQ;
    case .CANCEL; result = .CANCEL;
    case .CLEAR; result = .CLEAR;
    case .PRIOR; result = .PRIOR;
    case .RETURN2; result = .RETURN2;
    case .SEPARATOR; result = .SEPARATOR;
    case .OUT; result = .OUT;
    case .OPER; result = .OPER;
    case .CLEARAGAIN; result = .CLEARAGAIN;
    case .CRSEL; result = .CRSEL;
    case .EXSEL; result = .EXSEL;
    case .KP_00; result = .KP_00;
    case .KP_000; result = .KP_000;
    case .THOUSANDSSEPARATOR; result = .THOUSANDSSEPARATOR;
    case .DECIMALSEPARATOR; result = .DECIMALSEPARATOR;
    case .CURRENCYUNIT; result = .CURRENCYUNIT;
    case .CURRENCYSUBUNIT; result = .CURRENCYSUBUNIT;
    case .KP_LEFTPAREN; result = .KP_LEFTPAREN;
    case .KP_RIGHTPAREN; result = .KP_RIGHTPAREN;
    case .KP_LEFTBRACE; result = .KP_LEFTBRACE;
    case .KP_RIGHTBRACE; result = .KP_RIGHTBRACE;
    case .KP_TAB; result = .KP_TAB;
    case .KP_BACKSPACE; result = .KP_BACKSPACE;
    case .KP_A; result = .KP_A;
    case .KP_B; result = .KP_B;
    case .KP_C; result = .KP_C;
    case .KP_D; result = .KP_D;
    case .KP_E; result = .KP_E;
    case .KP_F; result = .KP_F;
    case .KP_XOR; result = .KP_XOR;
    case .KP_POWER; result = .KP_POWER;
    case .KP_PERCENT; result = .KP_PERCENT;
    case .KP_LESS; result = .KP_LESS;
    case .KP_GREATER; result = .KP_GREATER;
    case .KP_AMPERSAND; result = .KP_AMPERSAND;
    case .KP_DBLAMPERSAND; result = .KP_DBLAMPERSAND;
    case .KP_VERTICALBAR; result = .KP_VERTICALBAR;
    case .KP_DBLVERTICALBAR; result = .KP_DBLVERTICALBAR;
    case .KP_COLON; result = .KP_COLON;
    case .KP_HASH; result = .KP_HASH;
    case .KP_SPACE; result = .KP_SPACE;
    case .KP_AT; result = .KP_AT;
    case .KP_EXCLAM; result = .KP_EXCLAM;
    case .KP_MEMSTORE; result = .KP_MEMSTORE;
    case .KP_MEMRECALL; result = .KP_MEMRECALL;
    case .KP_MEMCLEAR; result = .KP_MEMCLEAR;
    case .KP_MEMADD; result = .KP_MEMADD;
    case .KP_MEMSUBTRACT; result = .KP_MEMSUBTRACT;
    case .KP_MEMMULTIPLY; result = .KP_MEMMULTIPLY;
    case .KP_MEMDIVIDE; result = .KP_MEMDIVIDE;
    case .KP_PLUSMINUS; result = .KP_PLUSMINUS;
    case .KP_CLEAR; result = .KP_CLEAR;
    case .KP_CLEARENTRY; result = .KP_CLEARENTRY;
    case .KP_BINARY; result = .KP_BINARY;
    case .KP_OCTAL; result = .KP_OCTAL;
    case .KP_DECIMAL; result = .KP_DECIMAL;
    case .KP_HEXADECIMAL; result = .KP_HEXADECIMAL;
    case .LCTRL; result = .LCTRL;
    case .LSHIFT; result = .LSHIFT;
    case .LALT; result = .LALT;
    case .LGUI; result = .LGUI;
    case .RCTRL; result = .RCTRL;
    case .RSHIFT; result = .RSHIFT;
    case .RALT; result = .RALT;
    case .RGUI; result = .RGUI;
    case .MODE; result = .MODE;
    case .SLEEP; result = .SLEEP;
    case .WAKE; result = .WAKE;
    case .CHANNEL_INCREMENT; result = .CHANNEL_INCREMENT;
    case .CHANNEL_DECREMENT; result = .CHANNEL_DECREMENT;
    case .MEDIA_PLAY; result = .MEDIA_PLAY;
    case .MEDIA_PAUSE; result = .MEDIA_PAUSE;
    case .MEDIA_RECORD; result = .MEDIA_RECORD;
    case .MEDIA_FAST_FORWARD; result = .MEDIA_FAST_FORWARD;
    case .MEDIA_REWIND; result = .MEDIA_REWIND;
    case .MEDIA_NEXT_TRACK; result = .MEDIA_NEXT_TRACK;
    case .MEDIA_PREVIOUS_TRACK; result = .MEDIA_PREVIOUS_TRACK;
    case .MEDIA_STOP; result = .MEDIA_STOP;
    case .MEDIA_EJECT; result = .MEDIA_EJECT;
    case .MEDIA_PLAY_PAUSE; result = .MEDIA_PLAY_PAUSE;
    case .MEDIA_SELECT; result = .MEDIA_SELECT;
    case .AC_NEW; result = .AC_NEW;
    case .AC_OPEN; result = .AC_OPEN;
    case .AC_CLOSE; result = .AC_CLOSE;
    case .AC_EXIT; result = .AC_EXIT;
    case .AC_SAVE; result = .AC_SAVE;
    case .AC_PRINT; result = .AC_PRINT;
    case .AC_PROPERTIES; result = .AC_PROPERTIES;
    case .AC_SEARCH; result = .AC_SEARCH;
    case .AC_HOME; result = .AC_HOME;
    case .AC_BACK; result = .AC_BACK;
    case .AC_FORWARD; result = .AC_FORWARD;
    case .AC_STOP; result = .AC_STOP;
    case .AC_REFRESH; result = .AC_REFRESH;
    case .AC_BOOKMARKS; result = .AC_BOOKMARKS;
    case .SOFTLEFT; result = .SOFTLEFT;
    case .SOFTRIGHT; result = .SOFTRIGHT;
    case .CALL; result = .CALL;
    case .ENDCALL; result = .ENDCALL;
    case .LEFT_TAB; result = .LEFT_TAB;
    case .LEVEL5_SHIFT; result = .LEVEL5_SHIFT;
    case .MULTI_KEY_COMPOSE; result = .MULTI_KEY_COMPOSE;
    case .LMETA; result = .LMETA;
    case .RMETA; result = .RMETA;
    case .LHYPER; result = .LHYPER;
    case .RHYPER; result = .RHYPER;
  }
  return result;
}

key_to_scancode :: (key: KeyboardKey) -> SDLKeyboardScancode {
  result: SDLKeyboardScancode = .UNKNOWN;
  if key == {
    case .UNKNOWN; result = .UNKNOWN;
    case .RETURN; result = .RETURN;
    case .ESCAPE; result = .ESCAPE;
    case .BACKSPACE; result = .BACKSPACE;
    case .TAB; result = .TAB;
    case .SPACE; result = .SPACE;
    case .EXCLAIM; result = .EXCLAIM;
    case .DBLAPOSTROPHE; result = .DBLAPOSTROPHE;
    case .HASH; result = .HASH;
    case .DOLLAR; result = .DOLLAR;
    case .PERCENT; result = .PERCENT;
    case .AMPERSAND; result = .AMPERSAND;
    case .APOSTROPHE; result = .APOSTROPHE;
    case .LEFTPAREN; result = .LEFTPAREN;
    case .RIGHTPAREN; result = .RIGHTPAREN;
    case .ASTERISK; result = .ASTERISK;
    case .PLUS; result = .PLUS;
    case .COMMA; result = .COMMA;
    case .MINUS; result = .MINUS;
    case .PERIOD; result = .PERIOD;
    case .SLASH; result = .SLASH;
    case ._0; result = ._0;
    case ._1; result = ._1;
    case ._2; result = ._2;
    case ._3; result = ._3;
    case ._4; result = ._4;
    case ._5; result = ._5;
    case ._6; result = ._6;
    case ._7; result = ._7;
    case ._8; result = ._8;
    case ._9; result = ._9;
    case .COLON; result = .COLON;
    case .SEMICOLON; result = .SEMICOLON;
    case .LESS; result = .LESS;
    case .EQUALS; result = .EQUALS;
    case .GREATER; result = .GREATER;
    case .QUESTION; result = .QUESTION;
    case .AT; result = .AT;
    case .LEFTBRACKET; result = .LEFTBRACKET;
    case .BACKSLASH; result = .BACKSLASH;
    case .RIGHTBRACKET; result = .RIGHTBRACKET;
    case .CARET; result = .CARET;
    case .UNDERSCORE; result = .UNDERSCORE;
    case .GRAVE; result = .GRAVE;
    case .A; result = .A;
    case .B; result = .B;
    case .C; result = .C;
    case .D; result = .D;
    case .E; result = .E;
    case .F; result = .F;
    case .G; result = .G;
    case .H; result = .H;
    case .I; result = .I;
    case .J; result = .J;
    case .K; result = .K;
    case .L; result = .L;
    case .M; result = .M;
    case .N; result = .N;
    case .O; result = .O;
    case .P; result = .P;
    case .Q; result = .Q;
    case .R; result = .R;
    case .S; result = .S;
    case .T; result = .T;
    case .U; result = .U;
    case .V; result = .V;
    case .W; result = .W;
    case .X; result = .X;
    case .Y; result = .Y;
    case .Z; result = .Z;
    case .LEFTBRACE; result = .LEFTBRACE;
    case .PIPE; result = .PIPE;
    case .RIGHTBRACE; result = .RIGHTBRACE;
    case .TILDE; result = .TILDE;
    case .DELETE; result = .DELETE;
    case .PLUSMINUS; result = .PLUSMINUS;
    case .CAPSLOCK; result = .CAPSLOCK;
    case .F1; result = .F1;
    case .F2; result = .F2;
    case .F3; result = .F3;
    case .F4; result = .F4;
    case .F5; result = .F5;
    case .F6; result = .F6;
    case .F7; result = .F7;
    case .F8; result = .F8;
    case .F9; result = .F9;
    case .F10; result = .F10;
    case .F11; result = .F11;
    case .F12; result = .F12;
    case .PRINTSCREEN; result = .PRINTSCREEN;
    case .SCROLLLOCK; result = .SCROLLLOCK;
    case .PAUSE; result = .PAUSE;
    case .INSERT; result = .INSERT;
    case .HOME; result = .HOME;
    case .PAGEUP; result = .PAGEUP;
    case .END; result = .END;
    case .PAGEDOWN; result = .PAGEDOWN;
    case .RIGHT; result = .RIGHT;
    case .LEFT; result = .LEFT;
    case .DOWN; result = .DOWN;
    case .UP; result = .UP;
    case .NUMLOCKCLEAR; result = .NUMLOCKCLEAR;
    case .KP_DIVIDE; result = .KP_DIVIDE;
    case .KP_MULTIPLY; result = .KP_MULTIPLY;
    case .KP_MINUS; result = .KP_MINUS;
    case .KP_PLUS; result = .KP_PLUS;
    case .KP_ENTER; result = .KP_ENTER;
    case .KP_1; result = .KP_1;
    case .KP_2; result = .KP_2;
    case .KP_3; result = .KP_3;
    case .KP_4; result = .KP_4;
    case .KP_5; result = .KP_5;
    case .KP_6; result = .KP_6;
    case .KP_7; result = .KP_7;
    case .KP_8; result = .KP_8;
    case .KP_9; result = .KP_9;
    case .KP_0; result = .KP_0;
    case .KP_PERIOD; result = .KP_PERIOD;
    case .APPLICATION; result = .APPLICATION;
    case .POWER; result = .POWER;
    case .KP_EQUALS; result = .KP_EQUALS;
    case .F13; result = .F13;
    case .F14; result = .F14;
    case .F15; result = .F15;
    case .F16; result = .F16;
    case .F17; result = .F17;
    case .F18; result = .F18;
    case .F19; result = .F19;
    case .F20; result = .F20;
    case .F21; result = .F21;
    case .F22; result = .F22;
    case .F23; result = .F23;
    case .F24; result = .F24;
    case .EXECUTE; result = .EXECUTE;
    case .HELP; result = .HELP;
    case .MENU; result = .MENU;
    case .SELECT; result = .SELECT;
    case .STOP; result = .STOP;
    case .AGAIN; result = .AGAIN;
    case .UNDO; result = .UNDO;
    case .CUT; result = .CUT;
    case .COPY; result = .COPY;
    case .PASTE; result = .PASTE;
    case .FIND; result = .FIND;
    case .MUTE; result = .MUTE;
    case .VOLUMEUP; result = .VOLUMEUP;
    case .VOLUMEDOWN; result = .VOLUMEDOWN;
    case .KP_COMMA; result = .KP_COMMA;
    case .KP_EQUALSAS400; result = .KP_EQUALSAS400;
    case .ALTERASE; result = .ALTERASE;
    case .SYSREQ; result = .SYSREQ;
    case .CANCEL; result = .CANCEL;
    case .CLEAR; result = .CLEAR;
    case .PRIOR; result = .PRIOR;
    case .RETURN2; result = .RETURN2;
    case .SEPARATOR; result = .SEPARATOR;
    case .OUT; result = .OUT;
    case .OPER; result = .OPER;
    case .CLEARAGAIN; result = .CLEARAGAIN;
    case .CRSEL; result = .CRSEL;
    case .EXSEL; result = .EXSEL;
    case .KP_00; result = .KP_00;
    case .KP_000; result = .KP_000;
    case .THOUSANDSSEPARATOR; result = .THOUSANDSSEPARATOR;
    case .DECIMALSEPARATOR; result = .DECIMALSEPARATOR;
    case .CURRENCYUNIT; result = .CURRENCYUNIT;
    case .CURRENCYSUBUNIT; result = .CURRENCYSUBUNIT;
    case .KP_LEFTPAREN; result = .KP_LEFTPAREN;
    case .KP_RIGHTPAREN; result = .KP_RIGHTPAREN;
    case .KP_LEFTBRACE; result = .KP_LEFTBRACE;
    case .KP_RIGHTBRACE; result = .KP_RIGHTBRACE;
    case .KP_TAB; result = .KP_TAB;
    case .KP_BACKSPACE; result = .KP_BACKSPACE;
    case .KP_A; result = .KP_A;
    case .KP_B; result = .KP_B;
    case .KP_C; result = .KP_C;
    case .KP_D; result = .KP_D;
    case .KP_E; result = .KP_E;
    case .KP_F; result = .KP_F;
    case .KP_XOR; result = .KP_XOR;
    case .KP_POWER; result = .KP_POWER;
    case .KP_PERCENT; result = .KP_PERCENT;
    case .KP_LESS; result = .KP_LESS;
    case .KP_GREATER; result = .KP_GREATER;
    case .KP_AMPERSAND; result = .KP_AMPERSAND;
    case .KP_DBLAMPERSAND; result = .KP_DBLAMPERSAND;
    case .KP_VERTICALBAR; result = .KP_VERTICALBAR;
    case .KP_DBLVERTICALBAR; result = .KP_DBLVERTICALBAR;
    case .KP_COLON; result = .KP_COLON;
    case .KP_HASH; result = .KP_HASH;
    case .KP_SPACE; result = .KP_SPACE;
    case .KP_AT; result = .KP_AT;
    case .KP_EXCLAM; result = .KP_EXCLAM;
    case .KP_MEMSTORE; result = .KP_MEMSTORE;
    case .KP_MEMRECALL; result = .KP_MEMRECALL;
    case .KP_MEMCLEAR; result = .KP_MEMCLEAR;
    case .KP_MEMADD; result = .KP_MEMADD;
    case .KP_MEMSUBTRACT; result = .KP_MEMSUBTRACT;
    case .KP_MEMMULTIPLY; result = .KP_MEMMULTIPLY;
    case .KP_MEMDIVIDE; result = .KP_MEMDIVIDE;
    case .KP_PLUSMINUS; result = .KP_PLUSMINUS;
    case .KP_CLEAR; result = .KP_CLEAR;
    case .KP_CLEARENTRY; result = .KP_CLEARENTRY;
    case .KP_BINARY; result = .KP_BINARY;
    case .KP_OCTAL; result = .KP_OCTAL;
    case .KP_DECIMAL; result = .KP_DECIMAL;
    case .KP_HEXADECIMAL; result = .KP_HEXADECIMAL;
    case .LCTRL; result = .LCTRL;
    case .LSHIFT; result = .LSHIFT;
    case .LALT; result = .LALT;
    case .LGUI; result = .LGUI;
    case .RCTRL; result = .RCTRL;
    case .RSHIFT; result = .RSHIFT;
    case .RALT; result = .RALT;
    case .RGUI; result = .RGUI;
    case .MODE; result = .MODE;
    case .SLEEP; result = .SLEEP;
    case .WAKE; result = .WAKE;
    case .CHANNEL_INCREMENT; result = .CHANNEL_INCREMENT;
    case .CHANNEL_DECREMENT; result = .CHANNEL_DECREMENT;
    case .MEDIA_PLAY; result = .MEDIA_PLAY;
    case .MEDIA_PAUSE; result = .MEDIA_PAUSE;
    case .MEDIA_RECORD; result = .MEDIA_RECORD;
    case .MEDIA_FAST_FORWARD; result = .MEDIA_FAST_FORWARD;
    case .MEDIA_REWIND; result = .MEDIA_REWIND;
    case .MEDIA_NEXT_TRACK; result = .MEDIA_NEXT_TRACK;
    case .MEDIA_PREVIOUS_TRACK; result = .MEDIA_PREVIOUS_TRACK;
    case .MEDIA_STOP; result = .MEDIA_STOP;
    case .MEDIA_EJECT; result = .MEDIA_EJECT;
    case .MEDIA_PLAY_PAUSE; result = .MEDIA_PLAY_PAUSE;
    case .MEDIA_SELECT; result = .MEDIA_SELECT;
    case .AC_NEW; result = .AC_NEW;
    case .AC_OPEN; result = .AC_OPEN;
    case .AC_CLOSE; result = .AC_CLOSE;
    case .AC_EXIT; result = .AC_EXIT;
    case .AC_SAVE; result = .AC_SAVE;
    case .AC_PRINT; result = .AC_PRINT;
    case .AC_PROPERTIES; result = .AC_PROPERTIES;
    case .AC_SEARCH; result = .AC_SEARCH;
    case .AC_HOME; result = .AC_HOME;
    case .AC_BACK; result = .AC_BACK;
    case .AC_FORWARD; result = .AC_FORWARD;
    case .AC_STOP; result = .AC_STOP;
    case .AC_REFRESH; result = .AC_REFRESH;
    case .AC_BOOKMARKS; result = .AC_BOOKMARKS;
    case .SOFTLEFT; result = .SOFTLEFT;
    case .SOFTRIGHT; result = .SOFTRIGHT;
    case .CALL; result = .CALL;
    case .ENDCALL; result = .ENDCALL;
    case .LEFT_TAB; result = .LEFT_TAB;
    case .LEVEL5_SHIFT; result = .LEVEL5_SHIFT;
    case .MULTI_KEY_COMPOSE; result = .MULTI_KEY_COMPOSE;
    case .LMETA; result = .LMETA;
    case .RMETA; result = .RMETA;
    case .LHYPER; result = .LHYPER;
    case .RHYPER; result = .RHYPER;
  }
  return result;
}

#scope_file

SDL_WINDOW_FULLSCREEN           :: 0x0000000000000001; //window is in fullscreen mode
SDL_WINDOW_OPENGL               :: 0x0000000000000002; //window usable with OpenGL context
SDL_WINDOW_OCCLUDED             :: 0x0000000000000004; //window is occluded
SDL_WINDOW_HIDDEN               :: 0x0000000000000008; //window is neither mapped onto the desktop nor shown in the taskbar/dock/window list; SDL_ShowWindow() is required for it to become visible
SDL_WINDOW_BORDERLESS           :: 0x0000000000000010; //no window decoration
SDL_WINDOW_RESIZABLE            :: 0x0000000000000020; //window can be resized
SDL_WINDOW_MINIMIZED            :: 0x0000000000000040; //window is minimized
SDL_WINDOW_MAXIMIZED            :: 0x0000000000000080; //window is maximized
SDL_WINDOW_MOUSE_GRABBED        :: 0x0000000000000100; //window has grabbed mouse input
SDL_WINDOW_INPUT_FOCUS          :: 0x0000000000000200; //window has input focus
SDL_WINDOW_MOUSE_FOCUS          :: 0x0000000000000400; //window has mouse focus
SDL_WINDOW_EXTERNAL             :: 0x0000000000000800; //window not created by SDL
SDL_WINDOW_MODAL                :: 0x0000000000001000; //window is modal
SDL_WINDOW_HIGH_PIXEL_DENSITY   :: 0x0000000000002000; //window uses high pixel density back buffer if possible
SDL_WINDOW_MOUSE_CAPTURE        :: 0x0000000000004000; //window has mouse captured (unrelated to MOUSE_GRABBED)
SDL_WINDOW_MOUSE_RELATIVE_MODE  :: 0x0000000000008000; //window has relative mode enabled
SDL_WINDOW_ALWAYS_ON_TOP        :: 0x0000000000010000; //window should always be above others
SDL_WINDOW_UTILITY              :: 0x0000000000020000; //window should be treated as a utility window, not showing in the task bar and window list
SDL_WINDOW_TOOLTIP              :: 0x0000000000040000; //window should be treated as a tooltip and does not get mouse or keyboard focus, requires a parent window
SDL_WINDOW_POPUP_MENU           :: 0x0000000000080000; //window should be treated as a popup menu, requires a parent window
SDL_WINDOW_KEYBOARD_GRABBED     :: 0x0000000000100000; //window has grabbed keyboard input
SDL_WINDOW_FILL_DOCUMENT        :: 0x0000000000200000; //window is in fill-document mode (Emscripten only), since SDL 3.4.0
SDL_WINDOW_VULKAN               :: 0x0000000010000000; //window usable for Vulkan surface
SDL_WINDOW_METAL                :: 0x0000000020000000; //window usable for Metal view
SDL_WINDOW_TRANSPARENT          :: 0x0000000040000000; //window with transparent buffer
SDL_WINDOW_NOT_FOCUSABLE        :: 0x0000000080000000; //window should not be focusable

SDLKeyboardScancode :: enum u32 {
  UNKNOWN              :: 0X00000000;
  RETURN               :: 0X0000000D;
  ESCAPE               :: 0X0000001B;
  BACKSPACE            :: 0X00000008;
  TAB                  :: 0X00000009;
  SPACE                :: 0X00000020;
  EXCLAIM              :: 0X00000021;
  DBLAPOSTROPHE        :: 0X00000022;
  HASH                 :: 0X00000023;
  DOLLAR               :: 0X00000024;
  PERCENT              :: 0X00000025;
  AMPERSAND            :: 0X00000026;
  APOSTROPHE           :: 0X00000027;
  LEFTPAREN            :: 0X00000028;
  RIGHTPAREN           :: 0X00000029;
  ASTERISK             :: 0X0000002A;
  PLUS                 :: 0X0000002B;
  COMMA                :: 0X0000002C;
  MINUS                :: 0X0000002D;
  PERIOD               :: 0X0000002E;
  SLASH                :: 0X0000002F;
  _0                   :: 0X00000030;
  _1                   :: 0X00000031;
  _2                   :: 0X00000032;
  _3                   :: 0X00000033;
  _4                   :: 0X00000034;
  _5                   :: 0X00000035;
  _6                   :: 0X00000036;
  _7                   :: 0X00000037;
  _8                   :: 0X00000038;
  _9                   :: 0X00000039;
  COLON                :: 0X0000003A;
  SEMICOLON            :: 0X0000003B;
  LESS                 :: 0X0000003C;
  EQUALS               :: 0X0000003D;
  GREATER              :: 0X0000003E;
  QUESTION             :: 0X0000003F;
  AT                   :: 0X00000040;
  LEFTBRACKET          :: 0X0000005B;
  BACKSLASH            :: 0X0000005C;
  RIGHTBRACKET         :: 0X0000005D;
  CARET                :: 0X0000005E;
  UNDERSCORE           :: 0X0000005F;
  GRAVE                :: 0X00000060;
  A                    :: 0X00000061;
  B                    :: 0X00000062;
  C                    :: 0X00000063;
  D                    :: 0X00000064;
  E                    :: 0X00000065;
  F                    :: 0X00000066;
  G                    :: 0X00000067;
  H                    :: 0X00000068;
  I                    :: 0X00000069;
  J                    :: 0X0000006A;
  K                    :: 0X0000006B;
  L                    :: 0X0000006C;
  M                    :: 0X0000006D;
  N                    :: 0X0000006E;
  O                    :: 0X0000006F;
  P                    :: 0X00000070;
  Q                    :: 0X00000071;
  R                    :: 0X00000072;
  S                    :: 0X00000073;
  T                    :: 0X00000074;
  U                    :: 0X00000075;
  V                    :: 0X00000076;
  W                    :: 0X00000077;
  X                    :: 0X00000078;
  Y                    :: 0X00000079;
  Z                    :: 0X0000007A;
  LEFTBRACE            :: 0X0000007B;
  PIPE                 :: 0X0000007C;
  RIGHTBRACE           :: 0X0000007D;
  TILDE                :: 0X0000007E;
  DELETE               :: 0X0000007F;
  PLUSMINUS            :: 0X000000B1;
  CAPSLOCK             :: 0X40000039;
  F1                   :: 0X4000003A;
  F2                   :: 0X4000003B;
  F3                   :: 0X4000003C;
  F4                   :: 0X4000003D;
  F5                   :: 0X4000003E;
  F6                   :: 0X4000003F;
  F7                   :: 0X40000040;
  F8                   :: 0X40000041;
  F9                   :: 0X40000042;
  F10                  :: 0X40000043;
  F11                  :: 0X40000044;
  F12                  :: 0X40000045;
  PRINTSCREEN          :: 0X40000046;
  SCROLLLOCK           :: 0X40000047;
  PAUSE                :: 0X40000048;
  INSERT               :: 0X40000049;
  HOME                 :: 0X4000004A;
  PAGEUP               :: 0X4000004B;
  END                  :: 0X4000004D;
  PAGEDOWN             :: 0X4000004E;
  RIGHT                :: 0X4000004F;
  LEFT                 :: 0X40000050;
  DOWN                 :: 0X40000051;
  UP                   :: 0X40000052;
  NUMLOCKCLEAR         :: 0X40000053;
  KP_DIVIDE            :: 0X40000054;
  KP_MULTIPLY          :: 0X40000055;
  KP_MINUS             :: 0X40000056;
  KP_PLUS              :: 0X40000057;
  KP_ENTER             :: 0X40000058;
  KP_1                 :: 0X40000059;
  KP_2                 :: 0X4000005A;
  KP_3                 :: 0X4000005B;
  KP_4                 :: 0X4000005C;
  KP_5                 :: 0X4000005D;
  KP_6                 :: 0X4000005E;
  KP_7                 :: 0X4000005F;
  KP_8                 :: 0X40000060;
  KP_9                 :: 0X40000061;
  KP_0                 :: 0X40000062;
  KP_PERIOD            :: 0X40000063;
  APPLICATION          :: 0X40000065;
  POWER                :: 0X40000066;
  KP_EQUALS            :: 0X40000067;
  F13                  :: 0X40000068;
  F14                  :: 0X40000069;
  F15                  :: 0X4000006A;
  F16                  :: 0X4000006B;
  F17                  :: 0X4000006C;
  F18                  :: 0X4000006D;
  F19                  :: 0X4000006E;
  F20                  :: 0X4000006F;
  F21                  :: 0X40000070;
  F22                  :: 0X40000071;
  F23                  :: 0X40000072;
  F24                  :: 0X40000073;
  EXECUTE              :: 0X40000074;
  HELP                 :: 0X40000075;
  MENU                 :: 0X40000076;
  SELECT               :: 0X40000077;
  STOP                 :: 0X40000078;
  AGAIN                :: 0X40000079;
  UNDO                 :: 0X4000007A;
  CUT                  :: 0X4000007B;
  COPY                 :: 0X4000007C;
  PASTE                :: 0X4000007D;
  FIND                 :: 0X4000007E;
  MUTE                 :: 0X4000007F;
  VOLUMEUP             :: 0X40000080;
  VOLUMEDOWN           :: 0X40000081;
  KP_COMMA             :: 0X40000085;
  KP_EQUALSAS400       :: 0X40000086;
  ALTERASE             :: 0X40000099;
  SYSREQ               :: 0X4000009A;
  CANCEL               :: 0X4000009B;
  CLEAR                :: 0X4000009C;
  PRIOR                :: 0X4000009D;
  RETURN2              :: 0X4000009E;
  SEPARATOR            :: 0X4000009F;
  OUT                  :: 0X400000A0;
  OPER                 :: 0X400000A1;
  CLEARAGAIN           :: 0X400000A2;
  CRSEL                :: 0X400000A3;
  EXSEL                :: 0X400000A4;
  KP_00                :: 0X400000B0;
  KP_000               :: 0X400000B1;
  THOUSANDSSEPARATOR   :: 0X400000B2;
  DECIMALSEPARATOR     :: 0X400000B3;
  CURRENCYUNIT         :: 0X400000B4;
  CURRENCYSUBUNIT      :: 0X400000B5;
  KP_LEFTPAREN         :: 0X400000B6;
  KP_RIGHTPAREN        :: 0X400000B7;
  KP_LEFTBRACE         :: 0X400000B8;
  KP_RIGHTBRACE        :: 0X400000B9;
  KP_TAB               :: 0X400000BA;
  KP_BACKSPACE         :: 0X400000BB;
  KP_A                 :: 0X400000BC;
  KP_B                 :: 0X400000BD;
  KP_C                 :: 0X400000BE;
  KP_D                 :: 0X400000BF;
  KP_E                 :: 0X400000C0;
  KP_F                 :: 0X400000C1;
  KP_XOR               :: 0X400000C2;
  KP_POWER             :: 0X400000C3;
  KP_PERCENT           :: 0X400000C4;
  KP_LESS              :: 0X400000C5;
  KP_GREATER           :: 0X400000C6;
  KP_AMPERSAND         :: 0X400000C7;
  KP_DBLAMPERSAND      :: 0X400000C8;
  KP_VERTICALBAR       :: 0X400000C9;
  KP_DBLVERTICALBAR    :: 0X400000CA;
  KP_COLON             :: 0X400000CB;
  KP_HASH              :: 0X400000CC;
  KP_SPACE             :: 0X400000CD;
  KP_AT                :: 0X400000CE;
  KP_EXCLAM            :: 0X400000CF;
  KP_MEMSTORE          :: 0X400000D0;
  KP_MEMRECALL         :: 0X400000D1;
  KP_MEMCLEAR          :: 0X400000D2;
  KP_MEMADD            :: 0X400000D3;
  KP_MEMSUBTRACT       :: 0X400000D4;
  KP_MEMMULTIPLY       :: 0X400000D5;
  KP_MEMDIVIDE         :: 0X400000D6;
  KP_PLUSMINUS         :: 0X400000D7;
  KP_CLEAR             :: 0X400000D8;
  KP_CLEARENTRY        :: 0X400000D9;
  KP_BINARY            :: 0X400000DA;
  KP_OCTAL             :: 0X400000DB;
  KP_DECIMAL           :: 0X400000DC;
  KP_HEXADECIMAL       :: 0X400000DD;
  LCTRL                :: 0X400000E0;
  LSHIFT               :: 0X400000E1;
  LALT                 :: 0X400000E2;
  LGUI                 :: 0X400000E3;
  RCTRL                :: 0X400000E4;
  RSHIFT               :: 0X400000E5;
  RALT                 :: 0X400000E6;
  RGUI                 :: 0X400000E7;
  MODE                 :: 0X40000101;
  SLEEP                :: 0X40000102;
  WAKE                 :: 0X40000103;
  CHANNEL_INCREMENT    :: 0X40000104;
  CHANNEL_DECREMENT    :: 0X40000105;
  MEDIA_PLAY           :: 0X40000106;
  MEDIA_PAUSE          :: 0X40000107;
  MEDIA_RECORD         :: 0X40000108;
  MEDIA_FAST_FORWARD   :: 0X40000109;
  MEDIA_REWIND         :: 0X4000010A;
  MEDIA_NEXT_TRACK     :: 0X4000010B;
  MEDIA_PREVIOUS_TRACK :: 0X4000010C;
  MEDIA_STOP           :: 0X4000010D;
  MEDIA_EJECT          :: 0X4000010E;
  MEDIA_PLAY_PAUSE     :: 0X4000010F;
  MEDIA_SELECT         :: 0X40000110;
  AC_NEW               :: 0X40000111;
  AC_OPEN              :: 0X40000112;
  AC_CLOSE             :: 0X40000113;
  AC_EXIT              :: 0X40000114;
  AC_SAVE              :: 0X40000115;
  AC_PRINT             :: 0X40000116;
  AC_PROPERTIES        :: 0X40000117;
  AC_SEARCH            :: 0X40000118;
  AC_HOME              :: 0X40000119;
  AC_BACK              :: 0X4000011A;
  AC_FORWARD           :: 0X4000011B;
  AC_STOP              :: 0X4000011C;
  AC_REFRESH           :: 0X4000011D;
  AC_BOOKMARKS         :: 0X4000011E;
  SOFTLEFT             :: 0X4000011F;
  SOFTRIGHT            :: 0X40000120;
  CALL                 :: 0X40000121;
  ENDCALL              :: 0X40000122;
  LEFT_TAB             :: 0X20000001;
  LEVEL5_SHIFT         :: 0X20000002;
  MULTI_KEY_COMPOSE    :: 0X20000003;
  LMETA                :: 0X20000004;
  RMETA                :: 0X20000005;
  LHYPER               :: 0X20000006;
  RHYPER               :: 0X20000007;
};

#import,file "utils.jai";
#import,file "math.jai";
#import,file "static_bitset.jai";
#import "SDL3";
#import "File";
#import "Basic";
vk :: #import "Vulkan";
