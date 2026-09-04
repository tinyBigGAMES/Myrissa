{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Console - ANSI terminal output and input

  Static class providing console I/O with full ANSI escape sequence
  support: colored text, cursor movement, terminal queries, progress
  bars, spinners, and raw key input. All output is guarded by
  HasConsole() so GUI applications silently skip console calls.

  Key types:
  - TConsole: Static class -- Print/PrintLn, cursor control, scrolling,
    terminal size queries, HRule, ProgressBar, Spinner, ReadKey
  - ANSI constants: COLOR_*, STYLE_*, BG_* escape sequences

  Dependencies: none
  Notes: Requires Windows Virtual Terminal Processing (enabled automatically
    by StdApp.Utils.InitConsole on first use).
===============================================================================}

unit StdApp.Console;

{$I StdApp.Defines.inc}

interface

uses
  WinApi.Windows,
  System.SysUtils;

const
  LF = #10;
  CR = #13;
  LFCR = #10#13;

  COLOR_RESET  = #27'[0m';
  COLOR_BOLD   = #27'[1m';
  COLOR_RED    = #27'[31m';
  COLOR_GREEN  = #27'[32m';
  COLOR_YELLOW = #27'[33m';
  COLOR_BLUE   = #27'[34m';
  COLOR_MAGENTA = #27'[35m';
  COLOR_CYAN   = #27'[36m';
  COLOR_WHITE  = #27'[37m';
  COLOR_DARKGRAY = #27'[90m';

  // Text Styles
  STYLE_DIM       = #27'[2m';
  STYLE_ITALIC    = #27'[3m';
  STYLE_UNDERLINE = #27'[4m';
  STYLE_BLINK     = #27'[5m';
  STYLE_INVERSE   = #27'[7m';
  STYLE_STRIKE    = #27'[9m';

  // Background Colors
  BG_BLACK   = #27'[40m';
  BG_RED     = #27'[41m';
  BG_GREEN   = #27'[42m';
  BG_YELLOW  = #27'[43m';
  BG_BLUE    = #27'[44m';
  BG_MAGENTA = #27'[45m';
  BG_CYAN    = #27'[46m';
  BG_WHITE   = #27'[47m';
  BG_DARK_GREY = #27'[48;5;238m';

type

  { TMsgBoxType }
  TMsgBoxType = (
    mbtInfo,
    mbtWarning,
    mbtError
  );

  { TTextAlign }
  TTextAlign = (
    taLeft,
    taCenter,
    taRight
  );

  { TConsole }
  TConsole = class
    class function  HasConsole(): Boolean; static;
    class procedure ClearToEOL(); static;
    class procedure ClearScreen(); static;
    class procedure Print(); overload; static;
    class procedure PrintLn(); overload; static;
    class procedure Print(const AText: string; const AResetColor: Boolean = True); overload; static;
    class procedure Print(const AText: string; const AArgs: array of const; const AResetColor: Boolean = True); overload; static;
    class procedure PrintLn(const AText: string; const AResetColor: Boolean = True); overload; static;
    class procedure PrintLn(const AText: string; const AArgs: array of const; const AResetColor: Boolean = True); overload; static;
    class procedure MsgBox(const ATitle, AMessage: string; const AType: TMsgBoxType = TMsgBoxType.mbtInfo); static;
    class function  RGB(const AR, AG, AB: Byte): string; static;
    class function  BgRGB(const AR, AG, AB: Byte): string; static;
    class function  Pause(const AMsg: string = ''; const AQuit: string = ''): Boolean; static;

    // Cursor movement
    class procedure CursorUp(const ACount: Integer = 1); static;
    class procedure CursorDown(const ACount: Integer = 1); static;
    class procedure CursorLeft(const ACount: Integer = 1); static;
    class procedure CursorRight(const ACount: Integer = 1); static;
    class procedure CursorTo(const ACol: Integer; const ARow: Integer); static;
    class procedure CursorToCol(const ACol: Integer); static;

    // Cursor visibility
    class procedure HideCursor(); static;
    class procedure ShowCursor(); static;

    // Save/restore cursor position
    class procedure SaveCursor(); static;
    class procedure RestoreCursor(); static;

    // Line operations
    class procedure ClearLine(const AResetCursor: Boolean = False); static;
    class procedure InsertLines(const ACount: Integer = 1); static;
    class procedure DeleteLines(const ACount: Integer = 1); static;
    class procedure ScrollUp(const ACount: Integer = 1); static;
    class procedure ScrollDown(const ACount: Integer = 1); static;

    // Terminal info
    class function  GetTerminalWidth(): Integer; static;
    class function  GetTerminalHeight(): Integer; static;
    class procedure SetTitle(const ATitle: string); static;

    // High-level helpers
    class procedure HRule(const AChar: Char = '-'; const AWidth: Integer = 0); static;
    class procedure PrintPadded(const AText: string; const AWidth: Integer;
      const APadChar: Char = ' '; const AAlign: TTextAlign = TTextAlign.taLeft); static;
    class procedure ProgressBar(const ACurrent: Integer; const ATotal: Integer;
      const AWidth: Integer = 40; const ABarColor: string = COLOR_GREEN); static;
    class function  Spinner(const AFrame: Integer): Char; static;

    // Key input
    class function  ReadKey(): Char; static;
    class function  KeyAvailable(): Boolean; static;
    class procedure WaitForKey(const AKey: Char = #13); static;
  end;

implementation

class function TConsole.HasConsole(): Boolean;
begin
  Result := Boolean(GetConsoleWindow() <> 0);
end;

class procedure TConsole.ClearToEOL();
begin
  if not HasConsole() then Exit;
  Write(#27'[0K');
end;

class procedure TConsole.ClearScreen();
begin
  if not HasConsole() then Exit;
  Write(#27'[2J' + #27'[3J' + #27'[H');
end;

class procedure TConsole.Print();
begin
  Print('');
end;

class procedure TConsole.PrintLn();
begin
  PrintLn('');
end;

class procedure TConsole.Print(const AText: string; const AResetColor: Boolean);
begin
  if not HasConsole() then Exit;
  if AResetColor then
    Write(AText + COLOR_RESET)
  else
    Write(AText);
end;

class procedure TConsole.Print(const AText: string; const AArgs: array of const;
  const AResetColor: Boolean);
begin
  if not HasConsole() then Exit;
  if AResetColor then
    Write(Format(AText, AArgs) + COLOR_RESET)
  else
    Write(Format(AText, AArgs));
end;

class procedure TConsole.PrintLn(const AText: string; const AResetColor: Boolean);
begin
  if not HasConsole() then Exit;
  if AResetColor then
    WriteLn(AText + COLOR_RESET)
  else
    WriteLn(AText);
end;

class procedure TConsole.PrintLn(const AText: string; const AArgs: array of const;
  const AResetColor: Boolean);
begin
  if not HasConsole() then Exit;
  if AResetColor then
    WriteLn(Format(AText, AArgs) + COLOR_RESET)
  else
    WriteLn(Format(AText, AArgs));
end;

class procedure TConsole.MsgBox(const ATitle, AMessage: string;
  const AType: TMsgBoxType);
var
  LFlags: UINT;
begin
  case AType of
    TMsgBoxType.mbtInfo:    LFlags := MB_OK or MB_ICONINFORMATION;
    TMsgBoxType.mbtWarning: LFlags := MB_OK or MB_ICONWARNING;
    TMsgBoxType.mbtError:   LFlags := MB_OK or MB_ICONERROR;
  else
    LFlags := MB_OK;
  end;
  MessageBoxW(0, PWideChar(AMessage), PWideChar(ATitle), LFlags);
end;

class function TConsole.RGB(const AR, AG, AB: Byte): string;
begin
  Result := #27'[38;2;' + IntToStr(AR) + ';' + IntToStr(AG) + ';' + IntToStr(AB) + 'm';
end;

class function TConsole.BgRGB(const AR, AG, AB: Byte): string;
begin
  Result := #27'[48;2;' + IntToStr(AR) + ';' + IntToStr(AG) + ';' + IntToStr(AB) + 'm';
end;

class function TConsole.Pause(const AMsg, AQuit: string): Boolean;
var
  LInput: string;
begin
  Result := False;
  PrintLn('');
  if AMsg.IsEmpty then
    Print('Press ENTER to continue...')
  else
    Print(AMsg);
  ReadLn(LInput);
  if not AQuit.IsEmpty then
  begin
    if SameText(LInput, AQuit) then
      Result := True;
  end;
  PrintLn('');
end;

// Cursor movement

class procedure TConsole.CursorUp(const ACount: Integer);
begin
  if not HasConsole() then Exit;
  Write(#27'[' + IntToStr(ACount) + 'A');
end;

class procedure TConsole.CursorDown(const ACount: Integer);
begin
  if not HasConsole() then Exit;
  Write(#27'[' + IntToStr(ACount) + 'B');
end;

class procedure TConsole.CursorRight(const ACount: Integer);
begin
  if not HasConsole() then Exit;
  Write(#27'[' + IntToStr(ACount) + 'C');
end;

class procedure TConsole.CursorLeft(const ACount: Integer);
begin
  if not HasConsole() then Exit;
  Write(#27'[' + IntToStr(ACount) + 'D');
end;

class procedure TConsole.CursorTo(const ACol: Integer; const ARow: Integer);
begin
  if not HasConsole() then Exit;
  // ANSI uses 1-based row;col
  Write(#27'[' + IntToStr(ARow) + ';' + IntToStr(ACol) + 'H');
end;

class procedure TConsole.CursorToCol(const ACol: Integer);
begin
  if not HasConsole() then Exit;
  Write(#27'[' + IntToStr(ACol) + 'G');
end;

// Cursor visibility

class procedure TConsole.HideCursor();
begin
  if not HasConsole() then Exit;
  Write(#27'[?25l');
end;

class procedure TConsole.ShowCursor();
begin
  if not HasConsole() then Exit;
  Write(#27'[?25h');
end;

// Save/restore cursor position

class procedure TConsole.SaveCursor();
begin
  if not HasConsole() then Exit;
  Write(#27'[s');
end;

class procedure TConsole.RestoreCursor();
begin
  if not HasConsole() then Exit;
  Write(#27'[u');
end;

// Line operations

class procedure TConsole.ClearLine(const AResetCursor: Boolean);
begin
  if not HasConsole() then Exit;
  Write(#27'[2K');
  if AResetCursor then
    Write(#13);
end;

class procedure TConsole.InsertLines(const ACount: Integer);
begin
  if not HasConsole() then Exit;
  Write(#27'[' + IntToStr(ACount) + 'L');
end;

class procedure TConsole.DeleteLines(const ACount: Integer);
begin
  if not HasConsole() then Exit;
  Write(#27'[' + IntToStr(ACount) + 'M');
end;

class procedure TConsole.ScrollUp(const ACount: Integer);
begin
  if not HasConsole() then Exit;
  Write(#27'[' + IntToStr(ACount) + 'S');
end;

class procedure TConsole.ScrollDown(const ACount: Integer);
begin
  if not HasConsole() then Exit;
  Write(#27'[' + IntToStr(ACount) + 'T');
end;

// Terminal info

class function TConsole.GetTerminalWidth(): Integer;
var
  LInfo: TConsoleScreenBufferInfo;
begin
  if GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), LInfo) then
    Result := LInfo.srWindow.Right - LInfo.srWindow.Left + 1
  else
    Result := 80;
end;

class function TConsole.GetTerminalHeight(): Integer;
var
  LInfo: TConsoleScreenBufferInfo;
begin
  if GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), LInfo) then
    Result := LInfo.srWindow.Bottom - LInfo.srWindow.Top + 1
  else
    Result := 25;
end;

class procedure TConsole.SetTitle(const ATitle: string);
begin
  if not HasConsole() then Exit;
  SetConsoleTitleW(PWideChar(ATitle));
end;

// High-level helpers

class procedure TConsole.HRule(const AChar: Char; const AWidth: Integer);
var
  LWidth: Integer;
begin
  if not HasConsole() then Exit;
  LWidth := AWidth;
  if LWidth <= 0 then
    LWidth := GetTerminalWidth();
  WriteLn(StringOfChar(AChar, LWidth));
end;

class procedure TConsole.PrintPadded(const AText: string; const AWidth: Integer;
  const APadChar: Char; const AAlign: TTextAlign);
var
  LPadTotal: Integer;
  LPadLeft: Integer;
  LPadRight: Integer;
begin
  if not HasConsole() then Exit;
  if AText.Length >= AWidth then
  begin
    Write(AText);
    Exit;
  end;

  LPadTotal := AWidth - AText.Length;
  case AAlign of
    TTextAlign.taLeft:
    begin
      Write(AText + StringOfChar(APadChar, LPadTotal));
    end;
    TTextAlign.taRight:
    begin
      Write(StringOfChar(APadChar, LPadTotal) + AText);
    end;
    TTextAlign.taCenter:
    begin
      LPadLeft := LPadTotal div 2;
      LPadRight := LPadTotal - LPadLeft;
      Write(StringOfChar(APadChar, LPadLeft) + AText +
        StringOfChar(APadChar, LPadRight));
    end;
  end;
end;

class procedure TConsole.ProgressBar(const ACurrent: Integer;
  const ATotal: Integer; const AWidth: Integer; const ABarColor: string);
var
  LFraction: Double;
  LFilled: Integer;
  LEmpty: Integer;
  LPercent: Integer;
begin
  if not HasConsole() then Exit;
  if ATotal <= 0 then
    LFraction := 0.0
  else
    LFraction := ACurrent / ATotal;
  if LFraction > 1.0 then
    LFraction := 1.0;

  LFilled := Round(LFraction * AWidth);
  LEmpty := AWidth - LFilled;
  LPercent := Round(LFraction * 100);

  // Move to start of line, draw bar, reset color
  Write(#13 + ABarColor + '[' +
    StringOfChar('=', LFilled) +
    StringOfChar(' ', LEmpty) +
    '] ' + COLOR_RESET + Format('%3d', [LPercent]) + '%');
end;

const
  SPINNER_CHARS: array[0..3] of Char = ('|', '/', '-', '\');

class function TConsole.Spinner(const AFrame: Integer): Char;
begin
  Result := SPINNER_CHARS[AFrame mod Length(SPINNER_CHARS)];
end;

// Key input

class function TConsole.ReadKey(): Char;
var
  LHandle: THandle;
  LInputRec: TInputRecord;
  LEventsRead: DWORD;
  LOldMode: DWORD;
begin
  LHandle := GetStdHandle(STD_INPUT_HANDLE);
  GetConsoleMode(LHandle, LOldMode);
  // Disable line input and echo so we get raw keypresses
  SetConsoleMode(LHandle, 0);
  try
    while True do
    begin
      ReadConsoleInputW(LHandle, LInputRec, 1, LEventsRead);
      if (LInputRec.EventType = KEY_EVENT) and
         LInputRec.Event.KeyEvent.bKeyDown then
      begin
        Result := LInputRec.Event.KeyEvent.UnicodeChar;
        if Result <> #0 then
          Break;
      end;
    end;
  finally
    SetConsoleMode(LHandle, LOldMode);
  end;
end;

class function TConsole.KeyAvailable(): Boolean;
var
  LHandle: THandle;
  LCount: DWORD;
begin
  LHandle := GetStdHandle(STD_INPUT_HANDLE);
  GetNumberOfConsoleInputEvents(LHandle, LCount);
  Result := LCount > 0;
end;

class procedure TConsole.WaitForKey(const AKey: Char);
var
  LCh: Char;
begin
  repeat
    LCh := ReadKey();
  until LCh = AKey;
end;

end.
