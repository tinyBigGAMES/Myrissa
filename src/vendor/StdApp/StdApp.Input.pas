{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Input - Input device polling and state tracking

  Static class providing real-time input polling with edge detection.
  Each input subsystem (keyboard, joystick) uses a private record to
  hold tracking state. Keyboard uses GetAsyncKeyState for real-time
  polling with independent pressed/released transition flags.

  Key types:
  - TInput: Static class -- KeyDown, KeyPressed, KeyReleased, Clear

  Dependencies: Winapi.Windows
  Notes: KeyPressed/KeyReleased are self-polling with no explicit
    update call required. Call Clear() to reset all tracking state.
===============================================================================}

unit StdApp.Input;

{$I StdApp.Defines.inc}

interface

uses
  Winapi.Windows;

type
  { TInput }
  TInput = class
  private type
    { TKeyboard }
    TKeyboard = record
      // State[0, key] = pressed edge tracking
      // State[1, key] = released edge tracking
      State: array[0..1, 0..255] of Boolean;
    end;

    { TJoystick }
    TJoystick = record
    end;
  private class var
    FKeyboard: TKeyboard;
  public
    // Keyboard -- real-time polling with edge detection
    class function KeyDown(const AKey: Integer): Boolean; static;
    class function KeyPressed(const AKey: Integer): Boolean; static;
    class function KeyReleased(const AKey: Integer): Boolean; static;

    // State management
    class procedure Clear(); static;
  end;

implementation

{ TInput }

class function TInput.KeyDown(const AKey: Integer): Boolean;
begin
  Result := (GetAsyncKeyState(AKey) and $8000) <> 0;
end;

class function TInput.KeyPressed(const AKey: Integer): Boolean;
var
  LDown: Boolean;
begin
  Result := False;
  LDown := KeyDown(AKey);
  if LDown then
  begin
    // Key is currently down -- fire once on transition
    if not FKeyboard.State[0, AKey] then
    begin
      FKeyboard.State[0, AKey] := True;
      Result := True;
    end;
  end
  else
  begin
    // Key is up -- reset so next press can fire
    FKeyboard.State[0, AKey] := False;
  end;
end;

class function TInput.KeyReleased(const AKey: Integer): Boolean;
var
  LDown: Boolean;
begin
  Result := False;
  LDown := KeyDown(AKey);
  if not LDown then
  begin
    // Key is currently up -- fire once on transition
    if not FKeyboard.State[1, AKey] then
    begin
      FKeyboard.State[1, AKey] := True;
      Result := True;
    end;
  end
  else
  begin
    // Key is down -- reset so next release can fire
    FKeyboard.State[1, AKey] := False;
  end;
end;

class procedure TInput.Clear();
begin
  FillChar(FKeyboard.State[0], SizeOf(FKeyboard.State[0]), 0);
  FillChar(FKeyboard.State[1], SizeOf(FKeyboard.State[1]), 1);
end;

initialization
  TInput.Clear();

end.
