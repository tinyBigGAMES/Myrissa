{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.TestDemo - Interactive demo framework with game-loop lifecycle

  Base class for demos and interactive examples that run a continuous
  update/render loop. Subclasses override OnSetup/OnShutdown/OnUpdate/
  OnRender hooks. The loop runs until Terminate() is called, with
  high-resolution delta-time tracking.

  Key types:
  - TTestDemo: Base class -- Execute (runs the loop), Terminate,
    OnSetup/OnShutdown/OnUpdate/OnRender hooks, Print/PrintLn helpers
  - TTestDemoClass: Class reference for factory instantiation

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Console
  Notes: Integrates with TConsoleMenu via AddTestDemo() for automatic
    menu registration.
===============================================================================}

unit StdApp.TestDemo;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Console;

type
  { TTestDemoClass }
  TTestDemoClass = class of TTestDemo;

  { TTestDemo }
  TTestDemo = class(TBaseObject)
  private
    FTitle: string;
    FRunning: Boolean;
    FLooping: Boolean;
    FStartTick: UInt64;
    FPrevTick: UInt64;
    FDeltaTime: Double;
    procedure DoUpdateTiming();
  public
    constructor Create(); override;

    // Lifecycle — drives the main loop. Subclasses override OnXXX hooks.
    procedure Execute();

    // Signals the loop in Execute to stop after the current iteration.
    procedure Terminate();

    // Lifecycle hooks — override in subclasses. All have empty defaults.
    procedure OnSetup(); virtual;
    procedure OnShutdown(); virtual;
    procedure OnUpdate(const ADeltaTime: Double); virtual;
    procedure OnRender(); virtual;
    procedure OnFrame(); virtual;

    // Console output helpers — delegates to TMyrUtils.
    procedure Print(const AMsg: string; const AArgs: array of const);
    procedure PrintLn(const AMsg: string; const AArgs: array of const);

    // Prints every entry in AErrors with color-coded severity.
    procedure PrintErrors(const AErrors: TErrors);

    // PrintErrors followed by AErrors.Clear.
    procedure FlushErrors(const AErrors: TErrors);

    // Instantiates ADemoClass, runs its Execute, frees it.
    class procedure Run(const ADemoClass: TTestDemoClass);

    property Title: string read FTitle write FTitle;
    property Running: Boolean read FRunning;
    property Looping: Boolean read FLooping write FLooping;
    property DeltaTime: Double read FDeltaTime;
  end;

implementation

{ TTestDemo }

constructor TTestDemo.Create();
begin
  inherited;
  FTitle := '';
  FRunning := False;
  FLooping := False;
end;

procedure TTestDemo.DoUpdateTiming();
var
  LNowTick: UInt64;
begin
  LNowTick := TUtils.GetTickCount64();
  FDeltaTime := (LNowTick - FPrevTick) / 1000.0;
  FPrevTick := LNowTick;
end;

procedure TTestDemo.Execute();
var
  LElapsedSec: Double;
begin
  FRunning := True;
  FStartTick := TUtils.GetTickCount64();
  FPrevTick := FStartTick;
  FDeltaTime := 0.0;

  // Banner
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_CYAN + COLOR_BOLD + '--- Demo: %s ---', [FTitle]);

  OnSetup();

  if FLooping then
  begin
    // Interactive/graphical loop -- runs until Terminate is called
    while FRunning do
    begin
      DoUpdateTiming();
      OnFrame();
      TUtils.ProcessMessages();
    end;
  end
  else
  begin
    // Single-frame execution
    DoUpdateTiming();
    OnFrame();
  end;

  OnShutdown();

  // Summary
  LElapsedSec := (TUtils.GetTickCount64() - FStartTick) / 1000.0;
  TConsole.PrintLn(COLOR_GREEN + COLOR_BOLD +
    '=== %s: Done (%.3fs) ===', [FTitle, LElapsedSec]);
end;

procedure TTestDemo.Terminate();
begin
  FRunning := False;
end;

procedure TTestDemo.OnSetup();
begin
  // Empty default — override in subclass
end;

procedure TTestDemo.OnShutdown();
begin
  // Empty default — override in subclass
end;

procedure TTestDemo.OnUpdate(const ADeltaTime: Double);
begin
  // Empty default — override in subclass
end;

procedure TTestDemo.OnRender();
begin
  // Empty default — override in subclass
end;

procedure TTestDemo.OnFrame();
begin
  // One frame: update + render. Override for single-frame demos.
  // For looping demos, set Looping := True in OnSetup and
  // override OnUpdate/OnRender instead.
  OnUpdate(FDeltaTime);
  OnRender();
end;

procedure TTestDemo.Print(const AMsg: string; const AArgs: array of const);
begin
  TConsole.Print(AMsg, AArgs);
end;

procedure TTestDemo.PrintLn(const AMsg: string; const AArgs: array of const);
begin
  TConsole.PrintLn(AMsg, AArgs);
end;

procedure TTestDemo.PrintErrors(const AErrors: TErrors);
var
  LItems: TList<TError>;
  LI: Integer;
  LErr: TError;
  LColor: string;
  LLabel: string;
begin
  if AErrors = nil then
    Exit;
  LItems := AErrors.GetItems();
  if LItems.Count = 0 then
    Exit;

  TConsole.PrintLn('');
  for LI := 0 to LItems.Count - 1 do
  begin
    LErr := LItems[LI];
    case LErr.Severity of
      esHint:
      begin
        LColor := COLOR_CYAN;
        LLabel := 'HINT';
      end;
      esWarning:
      begin
        LColor := COLOR_YELLOW;
        LLabel := 'WARN';
      end;
      esError:
      begin
        LColor := COLOR_RED;
        LLabel := 'ERROR';
      end;
      esFatal:
      begin
        LColor := COLOR_MAGENTA;
        LLabel := 'FATAL';
      end;
    else
      LColor := COLOR_WHITE;
      LLabel := '?';
    end;

    if LErr.Code <> '' then
      TConsole.PrintLn(LColor + '[%s] %s: %s',
        [LLabel, LErr.Code, LErr.Message])
    else
      TConsole.PrintLn(LColor + '[%s] %s', [LLabel, LErr.Message]);
  end;
end;

procedure TTestDemo.FlushErrors(const AErrors: TErrors);
begin
  PrintErrors(AErrors);
  if AErrors <> nil then
    AErrors.Clear();
end;

class procedure TTestDemo.Run(const ADemoClass: TTestDemoClass);
var
  LDemo: TTestDemo;
begin
  if ADemoClass = nil then
    Exit;

  LDemo := ADemoClass.Create();
  try
    LDemo.Execute();
  finally
    LDemo.Free();
  end;
end;

end.
