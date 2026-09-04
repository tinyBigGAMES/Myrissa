{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.TestCase - Lightweight test framework with Section/Check pattern

  Base class for registering and running named test cases with colored
  console output. Tests register via RegisterTest(), run via Execute(),
  and report per-assertion pass/fail with automatic section numbering.

  Key types:
  - TTestCase: Base class -- RegisterTest, Execute, Section, Check,
    PrintErrors, FlushErrors. Supports test filtering by name and
    single-test execution via class method RunTest.
  - TTestCaseClass: Class reference for factory instantiation

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Console
  Notes: Integrates with TConsoleMenu via AddTestCase() for automatic
    menu generation with per-test and run-all options.
===============================================================================}

unit StdApp.TestCase;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Console;

type

  { TTestCallback }
  TTestCallback = reference to procedure;

  { TTestEntry }
  TTestEntry = record
    EntryName: string;
    EntryProc: TTestCallback;
  end;

  { TTestCaseClass }
  TTestCaseClass = class of TTestCase;

  { TTestCase }
  TTestCase = class(TBaseObject)
  private
    FTitle: string;
    FAllPassed: Boolean;
    FSectionIndex: Integer;
    FPause: Boolean;
    FTestFilter: TArray<string>;
  protected
    FTests: TList<TTestEntry>;
    // Register a test method with a descriptive name
    procedure RegisterTest(const AName: string; const AProc: TTestCallback);

    // Configure which tests to run (call in Create for default filter)
    procedure RunTests(); overload;

    // Default: iterates registered tests matching filter
    procedure Run(); overload; virtual;
  public
    // Set test filter to run only named tests
    procedure RunTests(const ANames: array of string); overload;

    // Returns the names of all registered tests
    function GetTestNames(): TArray<string>;

    // Instantiates ATestClass, filters to one test, runs it, frees it
    class function RunTest(const ATestClass: TTestCaseClass;
      const ATestName: string): Boolean;
    constructor Create(); override;
    destructor Destroy(); override;

    // One-shot entry point: prints the banner, invokes Run, prints the
    // pass/fail summary. Resets FAllPassed / FSectionIndex up front so
    // the same instance can be re-executed if the caller wants.
    procedure Execute();

    // Prints a dim, auto-numbered sub-section header. Each call
    // increments FSectionIndex, so the caller never writes numbers.
    procedure Section(const ATitle: string); overload;
    procedure Section(const ATitle: string;
      const AArgs: array of const); overload;

    // Records one assertion. Prints [PASS] green / [FAIL] red and
    // flips FAllPassed to False on any failure. The test's overall
    // result is the AND of every Check call in Run.
    procedure Check(const ACondition: Boolean; const ALabel: string); overload;
    procedure Check(const ACondition: Boolean; const ALabel: string;
      const AArgs: array of const); overload;

    // Prints every entry in AErrors with color-coded severity
    // (HINT / WARN / ERROR / FATAL). Nil-safe, empty-safe.
    procedure PrintErrors(const AErrors: TErrors);

    // PrintErrors followed by AErrors.Clear — use this at the end of
    // each object's lifetime in a test so subsequent checks aren't
    // polluted by stale entries from a prior operation.
    procedure FlushErrors(const AErrors: TErrors);

    // Instantiates ATestClass, runs its Execute, frees it. Returns the
    // test's overall pass flag so a caller can chain or aggregate
    // multiple test runs. Safe to call repeatedly.
    class function Run(const ATestClass: TTestCaseClass): Boolean; overload;

    property Title: string read FTitle write FTitle;
    property AllPassed: Boolean read FAllPassed;
    property Pause: Boolean read FPause write FPause;
  end;

implementation

{ TTestCase }

constructor TTestCase.Create();
begin
  inherited;
  FTitle := '';
  FAllPassed := True;
  FSectionIndex := 0;
  FPause := True;
  FTests := TList<TTestEntry>.Create();
  FTestFilter := [];
end;

destructor TTestCase.Destroy();
begin
  FTests.Free();
  inherited;
end;

procedure TTestCase.Execute();
begin
  // Reset so the same instance can be Execute'd multiple times.
  FAllPassed := True;
  FSectionIndex := 0;

  // Banner
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_CYAN + COLOR_BOLD + '--- %s ---',
    [FTitle]);

  Run();

  // Summary
  if FAllPassed then
    TConsole.PrintLn(COLOR_GREEN + COLOR_BOLD +
      '=== %s: ALL PASSED ===', [FTitle])
  else
    TConsole.PrintLn(COLOR_RED + COLOR_BOLD +
      '=== %s: FAILED ===', [FTitle]);

  if FPause then
    TConsole.Pause();
end;

procedure TTestCase.Section(const ATitle: string);
begin
  Inc(FSectionIndex);
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BLUE + '[ %d. %s ]',
    [FSectionIndex, ATitle]);
end;

procedure TTestCase.Section(const ATitle: string;
  const AArgs: array of const);
begin
  Section(Format(ATitle, AArgs));
end;

procedure TTestCase.Check(const ACondition: Boolean; const ALabel: string);
begin
  if ACondition then
    TConsole.PrintLn(COLOR_GREEN + '[PASS] %s', [ALabel])
  else
  begin
    TConsole.PrintLn(COLOR_RED + '[FAIL] %s', [ALabel]);
    FAllPassed := False;
  end;
end;

procedure TTestCase.Check(const ACondition: Boolean; const ALabel: string;
  const AArgs: array of const);
begin
  Check(ACondition, Format(ALabel, AArgs));
end;

procedure TTestCase.PrintErrors(const AErrors: TErrors);
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
    begin
      if not LErr.Range.IsEmpty() then
        TConsole.PrintLn(LColor + '[%s] %s %s: %s',
          [LLabel, LErr.Range.ToPointString(), LErr.Code, LErr.Message])
      else
        TConsole.PrintLn(LColor + '[%s] %s: %s',
          [LLabel, LErr.Code, LErr.Message]);
    end
    else
    begin
      if not LErr.Range.IsEmpty() then
        TConsole.PrintLn(LColor + '[%s] %s %s',
          [LLabel, LErr.Range.ToPointString(), LErr.Message])
      else
        TConsole.PrintLn(LColor + '[%s] %s', [LLabel, LErr.Message]);
    end;
  end;
end;

procedure TTestCase.FlushErrors(const AErrors: TErrors);
begin
  PrintErrors(AErrors);
  if AErrors <> nil then
    AErrors.Clear();
end;

procedure TTestCase.RegisterTest(const AName: string; const AProc: TTestCallback);
var
  LEntry: TTestEntry;
begin
  LEntry.EntryName := AName;
  LEntry.EntryProc := AProc;
  FTests.Add(LEntry);
end;

procedure TTestCase.RunTests();
begin
  FTestFilter := [];
end;

procedure TTestCase.RunTests(const ANames: array of string);
var
  LI: Integer;
begin
  SetLength(FTestFilter, Length(ANames));
  for LI := 0 to High(ANames) do
    FTestFilter[LI] := ANames[LI];
end;

procedure TTestCase.Run();
var
  LI: Integer;
  LJ: Integer;
  LEntry: TTestEntry;
  LMatch: Boolean;
begin
  for LI := 0 to FTests.Count - 1 do
  begin
    LEntry := FTests[LI];

    // Apply test name filter (empty = run all)
    if Length(FTestFilter) > 0 then
    begin
      LMatch := False;
      for LJ := 0 to High(FTestFilter) do
      begin
        if SameText(FTestFilter[LJ], LEntry.EntryName) then
        begin
          LMatch := True;
          Break;
        end;
      end;
      if not LMatch then
        Continue;
    end;

    Section(LEntry.EntryName);
    LEntry.EntryProc();
  end;
end;

{ TTestCase.Run }

class function TTestCase.Run(const ATestClass: TTestCaseClass): Boolean;
var
  LTest: TTestCase;
begin
  Result := False;
  if ATestClass = nil then
    Exit;

  LTest := ATestClass.Create();
  try
    LTest.Execute();
    Result := LTest.AllPassed;
  finally
    LTest.Free();
  end;
end;

{ TTestCase.GetTestNames }

function TTestCase.GetTestNames(): TArray<string>;
var
  LI: Integer;
begin
  SetLength(Result, FTests.Count);
  for LI := 0 to FTests.Count - 1 do
    Result[LI] := FTests[LI].EntryName;
end;

{ TTestCase.RunTest }

class function TTestCase.RunTest(const ATestClass: TTestCaseClass;
  const ATestName: string): Boolean;
var
  LTest: TTestCase;
begin
  Result := False;
  if ATestClass = nil then
    Exit;

  LTest := ATestClass.Create();
  try
    if not TUtils.RunFromIDE() then
      LTest.Pause := False;
    LTest.RunTests([ATestName]);
    LTest.Execute();
    Result := LTest.AllPassed;
  finally
    LTest.Free();
  end;
end;

end.
