{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}

unit Myrissa.Tester;

{$I StdApp.Defines.inc}

{===============================================================================
  Test File Comment Directives
  ---------------------------------------------------------------------------
  These special comment tokens are embedded in .myr test source files and
  are parsed by TMyrTester before invoking the compiler.

  /* EXITCODE: <n> */
    Expected process exit code after running the compiled executable.
    Defaults to 0 if omitted. The test fails if the actual exit code differs.

  /* EXPECT:
    <text>
  */
    Expected stdout output. Displayed in the test runner output for manual
    comparison. Not automatically diffed -- for human review only.

  /* ALLOW_WARNINGS */
    Suppresses the "warnings present" failure. Use when a test intentionally
    produces compiler warnings.

  /* PLATFORMS: <P1>, <P2>, ... */
    Comma-separated list of platforms on which this test is valid.
    If the current target platform is not in the list the test is skipped
    (counted as neither pass nor fail). Omit entirely to run on all platforms.
    Valid platform names: WIN64, LINUX64
    Example: /* PLATFORMS: WIN64 */
===============================================================================}

interface

uses
  System.Types,
  System.IOUtils,
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  StdApp.Base,
  StdApp.JSON,
  StdApp.Utils,
  StdApp.Console,
  StdApp.Console.Menu,
  Myrissa.Common,
  Myrissa.Backend,
  Myrissa.Debug,
  Myrissa.Compiler;

const
  MYR_COMMENT_OPEN = '/*';
  MYR_COMMENT_CLOSE = '*/';
  MYR_TESTS_JSON = 'tests.json';

type
  TMyrTester = class;

  { TMyrTestRunMode }
  TMyrTestRunMode = (
    rmNone,         // compile only
    rmExecute,      // compile + run
    rmDebug         // compile + debug via REPL
  );

  { TMyrOptLevelSet }
  TMyrOptLevelSet = set of TMyrOptimizeLevel;

  { TMyrTargetSet }
  TMyrTargetSet = set of TMyrTargetKind;

  { TMyrTestEntry }
  TMyrTestEntry = record
    TestName:             string;
    Category:             string;
    Dependencies:         TArray<string>;
    Targets:              TMyrTargetSet;     // [] = tester's Targets
    RunMode:              TMyrTestRunMode;
    DefineName:           string;
    DefineValue:          string;
    OptLevels:            TMyrOptLevelSet;   // [] = use global default
    Subsystem:            TMyrSubsystem;
    HasSubsystemOverride: Boolean;           // false = use global default
  end;

  { TMyrTester }
  TMyrTester = class(TBaseObject)
  private
    FTestFolder:      string;
    FOutputPath:      string;
    FOptLevels:       TMyrOptLevelSet;
    FSubsystem:       TMyrSubsystem;
    FShowStatus:      Boolean;
    FDumpSSA:         Boolean;
    FPassCount:       Integer;
    FFailCount:       Integer;
    FSkipCount:       Integer;
    FLastTestSkipped: Boolean;
    FFailedTests:     TList<string>;
    FRegisteredTests: TDictionary<Integer, TMyrTestEntry>;
    FTargets:         TMyrTargetSet;
    FTarget:          TMyrTargetKind;
    FTargetPass:      TDictionary<TMyrTargetKind, Integer>;
    FTargetFail:      TDictionary<TMyrTargetKind, Integer>;
    FTargetSkip:      TDictionary<TMyrTargetKind, Integer>;
    FTargetOrder:     TList<TMyrTargetKind>;
    FOutputCallback:  TProc<string>;
    FCurrentCategory: string;
    FCheckSectionIdx: Integer;
    FAllChecksPassed: Boolean;

    procedure SetTestFolder(const AValue: string);
    procedure SetOutputPath(const AValue: string);
    function ExtractExpected(const ASource: string): string;
    function ExtractExpectedExitCode(const ASource: string): Integer;
    function ExtractAllowWarnings(const ASource: string): Boolean;
    function ExtractPlatforms(const ASource: string): TArray<string>;
    function PlatformMatchesCurrent(const APlatforms: TArray<string>): Boolean;
    function ExtractTestName(const AFilePath: string): string;
    function TargetName(const ATarget: TMyrTargetKind): string;
    procedure DoTally(const ATarget: TMyrTargetKind; const APass: Integer;
      const AFail: Integer; const ASkip: Integer);
    procedure PrintMatrix();
    function RunDepForCurrentTarget(const ADepName: string): Boolean;
    function RunTestFileAtLevel(const AFilePath: string;
      const ARunMode: TMyrTestRunMode;
      const AOptLevel: TMyrOptimizeLevel;
      const ASubsystem: TMyrSubsystem;
      const ADefine: string;
      const ADefineValue: string): Boolean;
    function RunTestFile(const AFilePath: string;
      const ARunMode: TMyrTestRunMode = rmNone;
      const ADefine: string = '';
      const ADefineValue: string = '';
      const AOptLevels: TMyrOptLevelSet = [];
      const ASubsystem: TMyrSubsystem = ssConsole;
      const AHasSubsystemOverride: Boolean = False): Boolean;
    procedure PrintResults();
    procedure Print(const AText: string); overload;
    procedure Print(const AFormat: string;
      const AArgs: array of const); overload;
    function GetFailedTests(): TArray<string>;
    function GetRegisteredTestCount(): Integer;

    // CLI mode helpers
    procedure DoShowBanner();
    procedure DoShowCLIHelp();
    procedure DoListTests();
    function DoParseIdRange(const AArg: string; out ALow: Integer;
      out AHigh: Integer): Boolean;
    function DoSelectByCategory(const ACategory: string): TArray<Integer>;
    function DoResolveSelector(const ASelector: string;
      const ASelected: TList<Integer>): Integer;
    procedure DoRunSelected(const ASelected: TList<Integer>);

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Registration (indexed, ordered execution)
    // ATargets is the test's TARGET LIST. [] = run on the tester's Targets.
    procedure RegisterTest(const AIndex: Integer;
      const ATestName: string;
      const ARunMode: TMyrTestRunMode = rmNone;
      const ADefine: string = '';
      const ADefineValue: string = '';
      const ATargets: TMyrTargetSet = []); overload;
    procedure RegisterTests(const AIndex: Integer;
      const ATestName: string;
      const ADependencies: array of string;
      const ARunMode: TMyrTestRunMode = rmNone;
      const ADefine: string = '';
      const ADefineValue: string = '';
      const ATargets: TMyrTargetSet = []); overload;
    procedure ClearRegisteredTests();

    // Per-test overrides (call after RegisterTest)
    procedure SetTestOptLevels(const AIndex: Integer;
      const AOptLevels: TMyrOptLevelSet);
    procedure SetTestSubsystem(const AIndex: Integer;
      const ASubsystem: TMyrSubsystem);

    // Execution
    function RunTest(const ATestName: string;
      const ARunMode: TMyrTestRunMode = rmNone;
      const ADefine: string = '';
      const ADefineValue: string = '';
      const AOptLevels: TMyrOptLevelSet = [];
      const ASubsystem: TMyrSubsystem = ssConsole;
      const AHasSubsystemOverride: Boolean = False): Boolean;
    function RunTestByIndex(const AIndex: Integer): Boolean;
    function RunAllTests(): Integer;
    function RunTestsMatching(const APattern: string;
      const ARunMode: TMyrTestRunMode = rmNone): Integer;

    // State
    procedure Reset();

    // Category
    procedure SetCategory(const ACategory: string);
    function GetTestCategory(const AIndex: Integer): string;
    function GetTests(): TArray<TPair<Integer, TMyrTestEntry>>;

    // Invoke callback helpers (Section/Check pattern from TTestCase)
    procedure Section(const ATitle: string); overload;
    procedure Section(const ATitle: string;
      const AArgs: array of const); overload;
    procedure Check(const ACondition: Boolean; const ALabel: string); overload;
    procedure Check(const ACondition: Boolean; const ALabel: string;
      const AArgs: array of const); overload;

    // CLI
    // Returns False ONLY when ParamCount() = 0 -- the interactive path, where
    // the caller opens the menu. Any argument switches to headless CLI mode,
    // sets ExitCode, and returns True.
    function CLI(): Boolean;

    // Menu builder
    class function CreateMenu(const ATester: TMyrTester): TConsoleMenu;

    // JSON persistence
    procedure SaveTests(const AFilename: string = MYR_TESTS_JSON);
    function LoadTests(const AFilename: string = MYR_TESTS_JSON): Boolean;

    // Properties
    property TestFolder:      string              read FTestFolder      write SetTestFolder;
    property OutputPath:      string              read FOutputPath      write SetOutputPath;
    property OptLevels:       TMyrOptLevelSet     read FOptLevels       write FOptLevels;
    property Targets:         TMyrTargetSet          read FTargets         write FTargets;
    property Subsystem:       TMyrSubsystem          read FSubsystem       write FSubsystem;
    property ShowStatus:      Boolean             read FShowStatus      write FShowStatus;
    property DumpSSA:         Boolean             read FDumpSSA         write FDumpSSA;
    property OutputCallback:  TProc<string>       read FOutputCallback  write FOutputCallback;
    property PassCount:       Integer             read FPassCount;
    property FailCount:       Integer             read FFailCount;
    property SkipCount:       Integer             read FSkipCount;
    property FailedTests:     TArray<string>      read GetFailedTests;
    property RegisteredTestCount: Integer         read GetRegisteredTestCount;
  end;

implementation

{ TMyrTester }

constructor TMyrTester.Create();
begin
  inherited;
  FFailedTests     := TList<string>.Create();
  FRegisteredTests := TDictionary<Integer, TMyrTestEntry>.Create();
  FTargetPass      := TDictionary<TMyrTargetKind, Integer>.Create();
  FTargetFail      := TDictionary<TMyrTargetKind, Integer>.Create();
  FTargetSkip      := TDictionary<TMyrTargetKind, Integer>.Create();
  FTargetOrder     := TList<TMyrTargetKind>.Create();
  FShowStatus      := False;
  FDumpSSA         := False;
  FOutputPath      := TUtils.ResolvePath('output');
  FOptLevels       := [olNone];
  FSubsystem       := ssConsole;
  FTestFolder      := TUtils.ResolvePath(MYR_RES_TESTS_DIR);

  // The full matrix by default. Narrow it by assigning Targets.
  FTargets         := [tgWin64, tgLinux64];
  FTarget          := tgWin64;
end;

destructor TMyrTester.Destroy();
begin
  FTargetOrder.Free();
  FTargetSkip.Free();
  FTargetFail.Free();
  FTargetPass.Free();
  FRegisteredTests.Free();
  FFailedTests.Free();
  inherited;
end;

{ SetTestFolder }
procedure TMyrTester.SetTestFolder(const AValue: string);
begin
  // Ingest boundary: everything downstream combines against an absolute path.
  FTestFolder := TUtils.ResolvePath(AValue);
end;

{ SetOutputPath }
procedure TMyrTester.SetOutputPath(const AValue: string);
begin
  FOutputPath := TUtils.ResolvePath(AValue);
end;

procedure TMyrTester.Reset();
begin
  FPassCount       := 0;
  FFailCount       := 0;
  FSkipCount       := 0;
  FLastTestSkipped := False;
  FFailedTests.Clear();
  FTargetPass.Clear();
  FTargetFail.Clear();
  FTargetSkip.Clear();
  FTargetOrder.Clear();
end;

procedure TMyrTester.SetCategory(const ACategory: string);
begin
  FCurrentCategory := ACategory;
end;

function TMyrTester.GetTestCategory(const AIndex: Integer): string;
var
  LEntry: TMyrTestEntry;
begin
  Result := '';
  if FRegisteredTests.TryGetValue(AIndex, LEntry) then
    Result := LEntry.Category;
end;

function TMyrTester.GetTests(): TArray<TPair<Integer, TMyrTestEntry>>;
var
  LKeys: TArray<Integer>;
  LI: Integer;
begin
  // Dictionary order is unspecified. Sorted ascending by ID so -list output and
  // range runs are deterministic and diffable between runs.
  LKeys := FRegisteredTests.Keys.ToArray();
  TArray.Sort<Integer>(LKeys);

  SetLength(Result, Length(LKeys));
  for LI := 0 to High(LKeys) do
    Result[LI] := TPair<Integer, TMyrTestEntry>.Create(
      LKeys[LI], FRegisteredTests[LKeys[LI]]);
end;

procedure TMyrTester.DoShowBanner();
var
  LVersion: TVersionInfo;
begin
  // Same shape as TMyrCLI.ShowBanner in Myrissa.CLI.pas: prefer the exe's own
  // version resource so the binary self-describes, and fall back to the
  // compiled-in version constant when the resource is absent.
  if TUtils.GetVersionInfo(LVersion, '') then
  begin
    TConsole.PrintLn(COLOR_WHITE + COLOR_BOLD + LVersion.ProductName +
      ' v' + LVersion.VersionString);
    TConsole.PrintLn(COLOR_WHITE + LVersion.Copyright);
    if LVersion.URL <> '' then
      TConsole.PrintLn(COLOR_YELLOW + LVersion.URL);
  end
  else
  begin
    TConsole.PrintLn(COLOR_WHITE + COLOR_BOLD +
      'Myrissa Tester™ v' + MYR_VERSION_STR);
    TConsole.PrintLn(COLOR_WHITE +
      'Copyright © 2026-present tinyBigGAMES™ LLC, All Rights Reserved.');
  end;
  TConsole.PrintLn('');
end;

procedure TMyrTester.DoShowCLIHelp();
begin
  TConsole.PrintLn(COLOR_CYAN + 'MyrissaTester [selector] [options]');
  TConsole.PrintLn('');
  TConsole.PrintLn('A bare invocation opens the interactive menu.');
  TConsole.PrintLn('Any argument switches to headless CLI mode.');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_CYAN + 'Selectors (combinable; union of all matches):');
  TConsole.PrintLn('  -all                  every registered test');
  TConsole.PrintLn('  N                     single test by ID          e.g. 250');
  TConsole.PrintLn('  N-N                   inclusive ID range         e.g. 250-299');
  TConsole.PrintLn('  name                  exact test name            e.g. test_exe_stdmap');
  TConsole.PrintLn('  name*                 name prefix wildcard');
  TConsole.PrintLn('  -cat "<category>"     every test in a category');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_CYAN + 'Options:');
  TConsole.PrintLn('  -t win64|linux64|both      target       (default both)');
  TConsole.PrintLn('  -opt none|basic|full|all   opt levels   (default all)');
  TConsole.PrintLn('  -q                         failures only, then a summary line');
  TConsole.PrintLn('  -list                      print ID, name, category; run nothing');
  TConsole.PrintLn('  -dump                      enable SSA dump');
  TConsole.PrintLn('  -h, --help                 this text');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_CYAN + 'Exit codes:');
  TConsole.PrintLn('  0  every selected test passed');
  TConsole.PrintLn('  1  one or more failed, OR the selection matched nothing');
  TConsole.PrintLn('  2  usage error (unknown flag, missing argument)');
end;

procedure TMyrTester.DoListTests();
var
  LTests: TArray<TPair<Integer, TMyrTestEntry>>;
  LPair:  TPair<Integer, TMyrTestEntry>;
begin
  LTests := GetTests();

  TConsole.PrintLn(COLOR_CYAN + Format('%-6s %-34s %s',
    ['ID', 'NAME', 'CATEGORY']));
  TConsole.PrintLn(StringOfChar('-', 70));

  for LPair in LTests do
    TConsole.PrintLn(Format('%-6d %-34s %s',
      [LPair.Key, LPair.Value.TestName, LPair.Value.Category]));

  TConsole.PrintLn('');
  TConsole.PrintLn(Format('%d test(s) registered.', [Length(LTests)]));
end;

function TMyrTester.DoParseIdRange(const AArg: string; out ALow: Integer;
  out AHigh: Integer): Boolean;
var
  LPos:   Integer;
  LLeft:  string;
  LRight: string;
begin
  Result := False;
  ALow   := 0;
  AHigh  := 0;

  // IndexOf is zero-based. A hyphen at position 0 is a flag, not a range,
  // so only an interior hyphen can separate two IDs.
  LPos := AArg.IndexOf('-');
  if LPos <= 0 then
    Exit;

  LLeft  := AArg.Substring(0, LPos).Trim();
  LRight := AArg.Substring(LPos + 1).Trim();

  if (LLeft = '') or (LRight = '') then
    Exit;

  if not TryStrToInt(LLeft, ALow) then
    Exit;

  if not TryStrToInt(LRight, AHigh) then
    Exit;

  Result := ALow <= AHigh;
end;

function TMyrTester.DoSelectByCategory(const ACategory: string): TArray<Integer>;
var
  LTests: TArray<TPair<Integer, TMyrTestEntry>>;
  LPair:  TPair<Integer, TMyrTestEntry>;
  LCount: Integer;
begin
  LTests := GetTests();
  SetLength(Result, Length(LTests));
  LCount := 0;

  for LPair in LTests do
  begin
    if SameText(LPair.Value.Category, ACategory) then
    begin
      Result[LCount] := LPair.Key;
      Inc(LCount);
    end;
  end;

  SetLength(Result, LCount);
end;

function TMyrTester.DoResolveSelector(const ASelector: string;
  const ASelected: TList<Integer>): Integer;
var
  LTests:  TArray<TPair<Integer, TMyrTestEntry>>;
  LPair:   TPair<Integer, TMyrTestEntry>;
  LIds:    TArray<Integer>;
  LId:     Integer;
  LLow:    Integer;
  LHigh:   Integer;
  LStem:   string;
  LBefore: Integer;
begin
  LBefore := ASelected.Count;
  LTests  := GetTests();

  if ASelector = '-all' then
  begin
    for LPair in LTests do
      if not ASelected.Contains(LPair.Key) then
        ASelected.Add(LPair.Key);
  end
  else if ASelector.StartsWith('cat:') then
  begin
    LIds := DoSelectByCategory(ASelector.Substring(4));
    for LId in LIds do
      if not ASelected.Contains(LId) then
        ASelected.Add(LId);
  end
  else if TryStrToInt(ASelector, LId) then
  begin
    for LPair in LTests do
      if (LPair.Key = LId) and not ASelected.Contains(LPair.Key) then
        ASelected.Add(LPair.Key);
  end
  else if DoParseIdRange(ASelector, LLow, LHigh) then
  begin
    for LPair in LTests do
      if (LPair.Key >= LLow) and (LPair.Key <= LHigh) and
        not ASelected.Contains(LPair.Key) then
        ASelected.Add(LPair.Key);
  end
  else if ASelector.Contains('*') then
  begin
    // Prefix wildcard over the REGISTERED set. RunTestsMatching cannot serve
    // this: it Contains() the raw pattern against file names on disk, so the
    // '*' is matched literally and never hits anything.
    LStem := ASelector.Replace('*', '');
    for LPair in LTests do
      if LPair.Value.TestName.StartsWith(LStem, True) and
        not ASelected.Contains(LPair.Key) then
        ASelected.Add(LPair.Key);
  end
  else
  begin
    for LPair in LTests do
      if SameText(LPair.Value.TestName, ASelector) and
        not ASelected.Contains(LPair.Key) then
        ASelected.Add(LPair.Key);
  end;

  Result := ASelected.Count - LBefore;
end;

procedure TMyrTester.DoRunSelected(const ASelected: TList<Integer>);
var
  LI:     Integer;
  LEntry: TMyrTestEntry;
begin
  Print(COLOR_CYAN + 'Running %d selected test(s)...', [ASelected.Count]);
  Print('');

  for LI := 0 to ASelected.Count - 1 do
  begin
    if not FRegisteredTests.TryGetValue(ASelected[LI], LEntry) then
      Continue;

    // RunTest is the only execution primitive that does NOT call Reset() or
    // print aggregate results, so it is the one that can be driven in a loop
    // across a multi-selector union without clobbering the running tally.
    RunTest(LEntry.TestName, LEntry.RunMode,
      LEntry.DefineName, LEntry.DefineValue,
      LEntry.OptLevels, LEntry.Subsystem,
      LEntry.HasSubsystemOverride);

    Print('');
    Print(COLOR_BLUE + '----------------------------------------');
    Print('');
  end;

  PrintMatrix();
end;

function TMyrTester.CLI(): Boolean;
var
  LI:         Integer;
  LFlag:      string;
  LValue:     string;
  LSelectors: TList<string>;
  LSelected:  TList<Integer>;
  LSel:       string;
  LName:      string;
  LQuiet:     Boolean;
begin
  // Bare invocation is the interactive path. Touch nothing, let the caller
  // open the menu.
  if ParamCount() = 0 then
    Exit(False);

  // CLI mode only. The menu path never reaches here, so its own title screen
  // is unaffected.
  DoShowBanner();

  Result     := True;
  LQuiet     := False;
  LSelectors := TList<string>.Create();
  LSelected  := TList<Integer>.Create();
  try
    LI := 1;
    while LI <= ParamCount() do
    begin
      LFlag := ParamStr(LI).Trim();

      if (LFlag = '-h') or (LFlag = '--help') then
      begin
        DoShowCLIHelp();
        ExitCode := 0;
        Exit(True);
      end
      else if LFlag = '-list' then
      begin
        DoListTests();
        ExitCode := 0;
        Exit(True);
      end
      else if LFlag = '-all' then
        LSelectors.Add('-all')
      else if LFlag = '-q' then
        LQuiet := True
      else if LFlag = '-dump' then
        FDumpSSA := True
      else if (LFlag = '-t') or (LFlag = '--target') then
      begin
        Inc(LI);
        if LI > ParamCount() then
        begin
          TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
            ' requires a target argument (win64, linux64, both)');
          ExitCode := 2;
          Exit(True);
        end;
        LValue := ParamStr(LI).Trim().ToLower();
        if LValue = 'win64' then
          FTargets := [tgWin64]
        else if LValue = 'linux64' then
          FTargets := [tgLinux64]
        else if LValue = 'both' then
          FTargets := [tgWin64, tgLinux64]
        else
        begin
          TConsole.PrintLn(COLOR_RED + 'Error: unknown target: ' + LValue);
          ExitCode := 2;
          Exit(True);
        end;
      end
      else if LFlag = '-opt' then
      begin
        Inc(LI);
        if LI > ParamCount() then
        begin
          TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
            ' requires a level argument (none, basic, full, all)');
          ExitCode := 2;
          Exit(True);
        end;
        LValue := ParamStr(LI).Trim().ToLower();
        if LValue = 'none' then
          FOptLevels := [olNone]
        else if LValue = 'basic' then
          FOptLevels := [olBasic]
        else if LValue = 'full' then
          FOptLevels := [olFull]
        else if LValue = 'all' then
          FOptLevels := [olNone, olBasic, olFull]
        else
        begin
          TConsole.PrintLn(COLOR_RED + 'Error: unknown opt level: ' + LValue);
          ExitCode := 2;
          Exit(True);
        end;
      end
      else if LFlag = '-cat' then
      begin
        Inc(LI);
        if LI > ParamCount() then
        begin
          TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
            ' requires a category argument');
          ExitCode := 2;
          Exit(True);
        end;
        LSelectors.Add('cat:' + ParamStr(LI).Trim());
      end
      else if LFlag.StartsWith('-') then
      begin
        // An ID range never starts with a hyphen, so anything that does and
        // is not a known flag is a usage error.
        TConsole.PrintLn(COLOR_RED + 'Error: unknown flag: ' + LFlag);
        TConsole.PrintLn('');
        DoShowCLIHelp();
        ExitCode := 2;
        Exit(True);
      end
      else
        LSelectors.Add(LFlag);

      Inc(LI);
    end;

    if LSelectors.Count = 0 then
    begin
      TConsole.PrintLn(COLOR_RED + 'Error: no selector given.');
      TConsole.PrintLn('');
      DoShowCLIHelp();
      ExitCode := 2;
      Exit(True);
    end;

    // Selectors are resolved only AFTER the whole command line is parsed, so
    // that options may appear in any position relative to them.
    for LSel in LSelectors do
      DoResolveSelector(LSel, LSelected);

    if LSelected.Count = 0 then
    begin
      // An empty selection must NOT exit 0. A typo'd selector that reported
      // success would be a gate incapable of failing.
      TConsole.PrintLn(COLOR_RED + 'No tests matched the selection.');
      for LSel in LSelectors do
        TConsole.PrintLn(COLOR_RED + '  selector: ' + LSel);
      ExitCode := 1;
      Exit(True);
    end;

    if LQuiet then
    begin
      FShowStatus := False;
      FOutputCallback :=
        procedure(ALine: string)
        begin
          if ALine.ToUpper().Contains('FAIL') or
            ALine.ToUpper().Contains('ERROR') then
            TConsole.PrintLn(ALine);
        end;
    end;

    Reset();
    DoRunSelected(LSelected);

    // The summary must survive -q, so the filter is dropped before it prints.
    FOutputCallback := nil;

    Print('');
    Print(COLOR_CYAN + '=== PASS %d  FAIL %d  SKIP %d  (%d selected) ===',
      [FPassCount, FFailCount, FSkipCount, LSelected.Count]);

    if FFailCount > 0 then
    begin
      for LName in FailedTests do
        Print(COLOR_RED + '  FAILED: ' + LName);
      ExitCode := 1;
    end
    else
      ExitCode := 0;
  finally
    LSelected.Free();
    LSelectors.Free();
  end;
end;

procedure TMyrTester.Section(const ATitle: string);
begin
  Inc(FCheckSectionIdx);
  Print(COLOR_BLUE + '[ %d. %s ]', [FCheckSectionIdx, ATitle]);
end;

procedure TMyrTester.Section(const ATitle: string;
  const AArgs: array of const);
begin
  Section(Format(ATitle, AArgs));
end;

procedure TMyrTester.Check(const ACondition: Boolean; const ALabel: string);
begin
  if ACondition then
    Print(COLOR_GREEN + '[PASS] %s', [ALabel])
  else
  begin
    Print(COLOR_RED + '[FAIL] %s', [ALabel]);
    FAllChecksPassed := False;
  end;
end;

procedure TMyrTester.Check(const ACondition: Boolean; const ALabel: string;
  const AArgs: array of const);
begin
  Check(ACondition, Format(ALabel, AArgs));
end;

class function TMyrTester.CreateMenu(const ATester: TMyrTester): TConsoleMenu;

  // Capture index by value for closure safety
  function MakeTestRunner(const AIdx: Integer): TMenuCallback;
  begin
    Result :=
      procedure
      begin
        ATester.RunTestByIndex(AIdx);
      end;
  end;

  // Capture category by value for closure safety
  function MakeCategoryRunner(const ACat: string): TMenuCallback;
  begin
    Result :=
      procedure
      var
        LSorted: TArray<Integer>;
        LK:      Integer;
        LEntry:  TMyrTestEntry;
      begin
        ATester.Reset();
        LSorted := ATester.FRegisteredTests.Keys.ToArray();
        TArray.Sort<Integer>(LSorted);
        for LK := 0 to High(LSorted) do
        begin
          LEntry := ATester.FRegisteredTests[LSorted[LK]];
          if SameText(LEntry.Category, ACat) then
            ATester.RunTest(LEntry.TestName, LEntry.RunMode,
              LEntry.DefineName, LEntry.DefineValue,
              LEntry.OptLevels, LEntry.Subsystem,
              LEntry.HasSubsystemOverride);
        end;
        ATester.PrintResults();
        ATester.PrintMatrix();
      end;
  end;

var
  LCategories:  TStringList;
  LI:           Integer;
  LEntry:       TMyrTestEntry;
  LCat:         string;
  LSubMenu:     TConsoleMenu;
  LCatIdx:      Integer;
  LSortedKeys:  TArray<Integer>;
begin
  Result := TConsoleMenu.Create();
  Result.Title(ATester.FTestFolder);
  Result.Pause := True;

  // Add "Run All Tests" at root level
  Result.Add('Run All Tests',
    procedure
    begin
      ATester.RunAllTests();
    end);

  Result.AddSeparator();

  // Collect unique categories in registration order
  LCategories := TStringList.Create();
  try
    LCategories.Duplicates := dupIgnore;
    LCategories.CaseSensitive := False;

    LSortedKeys := ATester.FRegisteredTests.Keys.ToArray();
    TArray.Sort<Integer>(LSortedKeys);

    for LI := 0 to High(LSortedKeys) do
    begin
      LEntry := ATester.FRegisteredTests[LSortedKeys[LI]];
      if LEntry.Category <> '' then
      begin
        if LCategories.IndexOf(LEntry.Category) < 0 then
          LCategories.Add(LEntry.Category);
      end;
    end;

    // Create a submenu per category
    for LCatIdx := 0 to LCategories.Count - 1 do
    begin
      LCat := LCategories[LCatIdx];
      LSubMenu := Result.AddSubmenu(LCat);

      // Add "Run All" for this category
      LSubMenu.Add('Run All', MakeCategoryRunner(LCat));
      LSubMenu.AddSeparator();

      // Add individual tests for this category
      for LI := 0 to High(LSortedKeys) do
      begin
        LEntry := ATester.FRegisteredTests[LSortedKeys[LI]];
        if SameText(LEntry.Category, LCat) then
          LSubMenu.Add(Format('#%d %s', [LSortedKeys[LI], LEntry.TestName]),
            MakeTestRunner(LSortedKeys[LI]));
      end;
    end;
  finally
    LCategories.Free();
  end;
end;

procedure TMyrTester.RegisterTest(const AIndex: Integer;
  const ATestName: string; const ARunMode: TMyrTestRunMode;
  const ADefine: string; const ADefineValue: string;
  const ATargets: TMyrTargetSet);
var
  LEntry: TMyrTestEntry;
  LKey:   Integer;
  LMax:   Integer;
  LK:     Integer;
begin
  LEntry.TestName             := ATestName;
  LEntry.Category             := FCurrentCategory;
  LEntry.Dependencies         := [];
  LEntry.Targets              := ATargets;
  LEntry.RunMode              := ARunMode;
  LEntry.DefineName           := ADefine;
  LEntry.DefineValue          := ADefineValue;
  LEntry.OptLevels            := [];      // use global default
  LEntry.Subsystem            := ssConsole;
  LEntry.HasSubsystemOverride := False;   // use global default

  if AIndex >= 0 then
    LKey := AIndex
  else
  begin
    LMax := -1;
    for LK in FRegisteredTests.Keys do
      if LK > LMax then
        LMax := LK;
    LKey := LMax + 1;
  end;

  FRegisteredTests.AddOrSetValue(LKey, LEntry);
end;

procedure TMyrTester.RegisterTests(const AIndex: Integer;
  const ATestName: string; const ADependencies: array of string;
  const ARunMode: TMyrTestRunMode; const ADefine: string;
  const ADefineValue: string;
  const ATargets: TMyrTargetSet);
var
  LEntry: TMyrTestEntry;
  LI:     Integer;
  LKey:   Integer;
  LMax:   Integer;
  LK:     Integer;
begin
  LEntry.TestName             := ATestName;
  LEntry.Category             := FCurrentCategory;
  LEntry.Targets              := ATargets;
  LEntry.RunMode              := ARunMode;
  LEntry.DefineName           := ADefine;
  LEntry.DefineValue          := ADefineValue;
  LEntry.OptLevels            := [];      // use global default
  LEntry.Subsystem            := ssConsole;
  LEntry.HasSubsystemOverride := False;   // use global default
  SetLength(LEntry.Dependencies, Length(ADependencies));
  for LI := 0 to High(ADependencies) do
    LEntry.Dependencies[LI] := ADependencies[LI];

  if AIndex >= 0 then
    LKey := AIndex
  else
  begin
    LMax := -1;
    for LK in FRegisteredTests.Keys do
      if LK > LMax then
        LMax := LK;
    LKey := LMax + 1;
  end;

  FRegisteredTests.AddOrSetValue(LKey, LEntry);
end;

procedure TMyrTester.ClearRegisteredTests();
begin
  FRegisteredTests.Clear();
end;

procedure TMyrTester.SetTestOptLevels(const AIndex: Integer;
  const AOptLevels: TMyrOptLevelSet);
var
  LEntry: TMyrTestEntry;
begin
  if FRegisteredTests.TryGetValue(AIndex, LEntry) then
  begin
    LEntry.OptLevels := AOptLevels;
    FRegisteredTests[AIndex] := LEntry;
  end;
end;

procedure TMyrTester.SetTestSubsystem(const AIndex: Integer;
  const ASubsystem: TMyrSubsystem);
var
  LEntry: TMyrTestEntry;
begin
  if FRegisteredTests.TryGetValue(AIndex, LEntry) then
  begin
    LEntry.Subsystem := ASubsystem;
    LEntry.HasSubsystemOverride := True;
    FRegisteredTests[AIndex] := LEntry;
  end;
end;

function TMyrTester.GetFailedTests(): TArray<string>;
begin
  Result := FFailedTests.ToArray();
end;

function TMyrTester.GetRegisteredTestCount(): Integer;
begin
  Result := FRegisteredTests.Count;
end;

procedure TMyrTester.Print(const AText: string);
begin
  if Assigned(FOutputCallback) then
    FOutputCallback(AText)
  else
    TConsole.PrintLn(AText);
end;

procedure TMyrTester.Print(const AFormat: string;
  const AArgs: array of const);
var
  LText: string;
begin
  LText := Format(AFormat, AArgs);

  if Assigned(FOutputCallback) then
    FOutputCallback(LText)
  else
    TConsole.PrintLn(LText);
end;

function TMyrTester.ExtractExpected(const ASource: string): string;
var
  LStart:  Integer;
  LEnd:    Integer;
  LBlock:  string;
  LPrefix: string;
begin
  Result  := '';
  LPrefix := MYR_COMMENT_OPEN + ' EXPECT:';

  LStart := ASource.IndexOf(LPrefix);
  if LStart < 0 then
    Exit;

  LStart := LStart + Length(LPrefix);
  LEnd   := ASource.IndexOf(MYR_COMMENT_CLOSE, LStart);
  if LEnd < 0 then
    Exit;

  LBlock := ASource.Substring(LStart, LEnd - LStart);
  Result := LBlock.Trim();
end;

function TMyrTester.ExtractExpectedExitCode(
  const ASource: string): Integer;
var
  LStart:  Integer;
  LEnd:    Integer;
  LValue:  string;
  LPrefix: string;
begin
  Result  := 0;
  LPrefix := MYR_COMMENT_OPEN + ' EXITCODE:';

  LStart := ASource.IndexOf(LPrefix);
  if LStart < 0 then
    Exit;

  LStart := LStart + Length(LPrefix);
  LEnd   := ASource.IndexOf(MYR_COMMENT_CLOSE, LStart);
  if LEnd < 0 then
    Exit;

  LValue := ASource.Substring(LStart, LEnd - LStart).Trim();
  Result := StrToIntDef(LValue, 0);
end;

function TMyrTester.ExtractAllowWarnings(
  const ASource: string): Boolean;
begin
  Result := ASource.Contains(
    MYR_COMMENT_OPEN + ' ALLOW_WARNINGS ' + MYR_COMMENT_CLOSE);
end;

function TMyrTester.ExtractPlatforms(
  const ASource: string): TArray<string>;
var
  LStart:  Integer;
  LEnd:    Integer;
  LBlock:  string;
  LPrefix: string;
  LParts:  TArray<string>;
  LI:      Integer;
begin
  SetLength(Result, 0);
  LPrefix := MYR_COMMENT_OPEN + ' PLATFORMS:';

  LStart := ASource.IndexOf(LPrefix);
  if LStart < 0 then
    Exit;

  LStart := LStart + Length(LPrefix);
  LEnd := ASource.IndexOf(MYR_COMMENT_CLOSE, LStart);
  if LEnd < 0 then
    Exit;

  LBlock := ASource.Substring(LStart, LEnd - LStart).Trim();
  LParts := LBlock.Split([',']);

  SetLength(Result, Length(LParts));
  for LI := 0 to High(LParts) do
    Result[LI] := LParts[LI].Trim().ToUpper();
end;

function TMyrTester.PlatformMatchesCurrent(
  const APlatforms: TArray<string>): Boolean;
var
  LPlatform: string;
begin
  // No platforms specified means run everywhere
  if Length(APlatforms) = 0 then
    Exit(True);

  // Match against the current target being built
  Result := False;
  for LPlatform in APlatforms do
  begin
    if SameText(LPlatform, TargetName(FTarget)) then
    begin
      Result := True;
      Break;
    end;
  end;
end;

function TMyrTester.ExtractTestName(const AFilePath: string): string;
begin
  Result := TPath.GetFileNameWithoutExtension(AFilePath);
end;

function TMyrTester.TargetName(const ATarget: TMyrTargetKind): string;
begin
  case ATarget of
    tgWin64:   Result := 'win64';
    tgLinux64: Result := 'linux64';
  else
    Result := '?';
  end;
end;

// Accumulate a per-target result. FTargetOrder preserves first-seen order so
// the matrix prints in the order the targets were actually exercised.
procedure TMyrTester.DoTally(const ATarget: TMyrTargetKind; const APass: Integer;
  const AFail: Integer; const ASkip: Integer);
var
  LValue: Integer;
begin
  if not FTargetOrder.Contains(ATarget) then
    FTargetOrder.Add(ATarget);

  if not FTargetPass.TryGetValue(ATarget, LValue) then
    LValue := 0;
  FTargetPass.AddOrSetValue(ATarget, LValue + APass);

  if not FTargetFail.TryGetValue(ATarget, LValue) then
    LValue := 0;
  FTargetFail.AddOrSetValue(ATarget, LValue + AFail);

  if not FTargetSkip.TryGetValue(ATarget, LValue) then
    LValue := 0;
  FTargetSkip.AddOrSetValue(ATarget, LValue + ASkip);
end;

procedure TMyrTester.PrintMatrix();
var
  LI:      Integer;
  LTarget: TMyrTargetKind;
  LPass:   Integer;
  LFail:   Integer;
  LSkip:   Integer;
  LColor:  string;
begin
  if FTargetOrder.Count = 0 then
    Exit;

  Print('');
  Print(COLOR_CYAN + '=== TARGET MATRIX ===');
  Print(COLOR_WHITE +
    Format('%-14s %6s %6s %6s', ['TARGET', 'PASS', 'FAIL', 'SKIP']));

  for LI := 0 to FTargetOrder.Count - 1 do
  begin
    LTarget := FTargetOrder[LI];

    if not FTargetPass.TryGetValue(LTarget, LPass) then
      LPass := 0;
    if not FTargetFail.TryGetValue(LTarget, LFail) then
      LFail := 0;
    if not FTargetSkip.TryGetValue(LTarget, LSkip) then
      LSkip := 0;

    if LFail = 0 then
      LColor := COLOR_GREEN
    else
      LColor := COLOR_RED;

    Print(LColor + Format('%-14s %6d %6d %6d',
      [TargetName(LTarget), LPass, LFail, LSkip]));
  end;
end;

// Build a dependency at the CURRENT FTarget only. A dep is infrastructure
// for its parent, not a test result -- no tally, no FFailedTests, and no
// target loop of its own (the consumer dictates the target).
function TMyrTester.RunDepForCurrentTarget(const ADepName: string): Boolean;
var
  LFilePath: string;
begin
  LFilePath := TPath.Combine(FTestFolder,
    TPath.ChangeExtension(ADepName, MYR_SRCFILE_EXT));

  if not TFile.Exists(LFilePath) then
  begin
    Print(COLOR_RED + 'ERROR: Dependency not found: ' + LFilePath);
    Exit(False);
  end;

  Print(COLOR_BLUE + '[dep] ' + ADepName);

  // rmNone: a dependency is compiled, never run.
  Result := RunTestFile(LFilePath, rmNone);
  if not Result then
    Print(COLOR_RED + 'Dependency build failed: ' + ADepName);

  Print('');
end;

function TMyrTester.RunTestFileAtLevel(const AFilePath: string;
  const ARunMode: TMyrTestRunMode;
  const AOptLevel: TMyrOptimizeLevel;
  const ASubsystem: TMyrSubsystem;
  const ADefine: string;
  const ADefineValue: string): Boolean;
var
  LCompiler:         TMyrCompiler;
  LExitCode:         Cardinal;
  LSource:           string;
  LExpected:         string;
  LExpectedExitCode: Integer;
  LAllowWarnings:    Boolean;
  LTestName:         string;
  LExePath:          string;
  LREPL:             TMyrDebugREPL;
begin
  LExitCode := 0;

  LSource           := TFile.ReadAllText(AFilePath);
  LExpected         := ExtractExpected(LSource);
  LExpectedExitCode := ExtractExpectedExitCode(LSource);
  LAllowWarnings    := ExtractAllowWarnings(LSource);
  LTestName         := ExtractTestName(AFilePath);

  Print(COLOR_CYAN + '[%s] [opt %d] %s',
    [TargetName(FTarget), Ord(AOptLevel), LTestName]);

  LCompiler := TMyrCompiler.Create();
  try
    // Configure compiler
    LCompiler.SetTarget(FTarget);
    LCompiler.SetOptimizeLevel(Ord(AOptLevel));
    LCompiler.SetSubsystem(ASubsystem);
    LCompiler.SetDumpIR(FDumpSSA);

    // Set status callback
    if FShowStatus then
      LCompiler.SetStatusCallback(
        procedure(const AText: string; const AUserData: Pointer)
        begin
          if Assigned(FOutputCallback) then
            FOutputCallback(AText)
          else
            TConsole.PrintLn(AText);
        end);

    // Compile
    LCompiler.Compile(AFilePath, FOutputPath);
    Result := not LCompiler.GetErrors().HasErrors();

    // The SSA dump file is written by the compiler itself, gated on the
    // SetDumpIR flag above. Do not write it here as well.

    if (Result = True) and (ARunMode = rmExecute) then
    begin
      Result := LCompiler.Run();
      LExitCode := LCompiler.GetLastExitCode();
    end;

    // Compilation errors override result
    if LCompiler.GetErrors().HasErrors() then
      Result := False;

    // Print any errors/warnings
    LCompiler.PrintErrors();

    // Exit if build failed
    if not Result then
    begin
      // Tolerate build "failure" when expected exit code is non-zero
      // and the actual exit code matches
      if (LExpectedExitCode <> 0) and
         (LExitCode = Cardinal(LExpectedExitCode)) then
        Result := True
      else
      begin
        Print(COLOR_RED + 'Build failed.');
        Exit;
      end;
    end;

    // Check for warnings (fail unless allowed)
    if LCompiler.GetErrors().HasWarnings() and (not LAllowWarnings) then
    begin
      Print(COLOR_RED + 'Test failed: warnings present (use ' +
        MYR_COMMENT_OPEN + ' ALLOW_WARNINGS ' +
        MYR_COMMENT_CLOSE + ' to allow).');
      Result := False;
      Exit;
    end;

    // Show success
    Print(COLOR_GREEN + 'Build OK');

    // Capture exe path for debug mode (before compiler is freed)
    if ARunMode = rmDebug then
      LExePath := TPath.GetFullPath(LCompiler.GetOutputFilename());

    // Check exit code if the test was run
    if ARunMode = rmExecute then
    begin
      if LExitCode <> Cardinal(LExpectedExitCode) then
      begin
        Print(COLOR_RED + 
          '  Test failed: expected exit code %d, got %d.',
          [LExpectedExitCode, LExitCode]);
        Result := False;
        Exit;
      end;

      if LExpected <> '' then
      begin
        Print(COLOR_YELLOW + '[EXPECTED]');
        Print(LExpected);
      end;
    end;

  finally
    LCompiler.Free();
  end;

  // Launch debug REPL after compiler is freed
  if (ARunMode = rmDebug) and Result then
  begin
    Print(COLOR_CYAN + 'Launching debugger for: %s', [LExePath]);
    Print('');
    LREPL := TMyrDebugREPL.Create();
    try
      LREPL.Run(LExePath);
    finally
      LREPL.Free();
    end;
  end;
end;

function TMyrTester.RunTestFile(const AFilePath: string;
  const ARunMode: TMyrTestRunMode;
  const ADefine: string;
  const ADefineValue: string;
  const AOptLevels: TMyrOptLevelSet;
  const ASubsystem: TMyrSubsystem;
  const AHasSubsystemOverride: Boolean): Boolean;
var
  LEffectiveOptLevels: TMyrOptLevelSet;
  LEffectiveSubsystem: TMyrSubsystem;
  LOpt:                TMyrOptimizeLevel;
  LTestName:           string;
  LSource:             string;
begin
  Result           := True;
  FLastTestSkipped := False;

  if not TFile.Exists(AFilePath) then
  begin
    Print(COLOR_RED + 'ERROR: File not found: ' + AFilePath);
    Result := False;
    Exit;
  end;

  LTestName := ExtractTestName(AFilePath);

  Print(COLOR_CYAN + '=== Test: ' + LTestName + ' ===');
  Print('');

  // Check platform requirements before doing any work
  LSource := TFile.ReadAllText(AFilePath);
  if not PlatformMatchesCurrent(ExtractPlatforms(LSource)) then
  begin
    Print(COLOR_YELLOW + 'Skipped (not supported on current platform).');
    Print('');
    FLastTestSkipped := True;
    Result := False;
    Exit;
  end;

  // Resolve effective settings: per-test overrides or global defaults
  // Debug mode forces olNone (no optimizations)
  if ARunMode = rmDebug then
    LEffectiveOptLevels := [olNone]
  else if AOptLevels <> [] then
    LEffectiveOptLevels := AOptLevels
  else
    LEffectiveOptLevels := FOptLevels;

  if AHasSubsystemOverride then
    LEffectiveSubsystem := ASubsystem
  else
    LEffectiveSubsystem := FSubsystem;

  // Run at each optimization level
  for LOpt in LEffectiveOptLevels do
  begin
    if not RunTestFileAtLevel(AFilePath, ARunMode, LOpt,
      LEffectiveSubsystem, ADefine, ADefineValue) then
    begin
      Result := False;
      // Continue to next opt level -- report all failures
    end;
  end;
end;

function TMyrTester.RunTest(const ATestName: string;
  const ARunMode: TMyrTestRunMode; const ADefine: string;
  const ADefineValue: string; const AOptLevels: TMyrOptLevelSet;
  const ASubsystem: TMyrSubsystem;
  const AHasSubsystemOverride: Boolean): Boolean;
var
  LFilePath: string;
  LEntry:    TMyrTestEntry;
  LScan:     TMyrTestEntry;
  LFound:    Boolean;
  LDep:      string;
  LTargets:  TMyrTargetSet;
  LTgt:      TMyrTargetKind;
  LLast:     TMyrTargetKind;
  LDepsOk:   Boolean;
begin
  Result := True;

  // Look up registered entry -- supplies dependencies and target list
  LEntry := Default(TMyrTestEntry);
  LFound := False;
  for LScan in FRegisteredTests.Values do
  begin
    if SameText(LScan.TestName, ATestName) then
    begin
      LEntry := LScan;
      LFound := True;
      Break;
    end;
  end;

  // The test's target list IS its build matrix. [] = tester's Targets.
  if LFound and (LEntry.Targets <> []) then
    LTargets := LEntry.Targets
  else
    LTargets := FTargets;

  // Find the last selected target (for separator placement)
  LLast := tgWin64;
  for LTgt := Low(TMyrTargetKind) to High(TMyrTargetKind) do
  begin
    if LTgt in LTargets then
      LLast := LTgt;
  end;

  LFilePath := TPath.Combine(FTestFolder,
    TPath.ChangeExtension(ATestName, MYR_SRCFILE_EXT));

  for LTgt := Low(TMyrTargetKind) to High(TMyrTargetKind) do
  begin
    if not (LTgt in LTargets) then
      Continue;

    FTarget := LTgt;

    // Rebuild every dependency at THIS target -- the build artifact is a
    // single file on disk and every build overwrites it, so the dep must be
    // regenerated immediately before each parent build.
    LDepsOk := True;
    for LDep in LEntry.Dependencies do
    begin
      if not RunDepForCurrentTarget(LDep) then
      begin
        LDepsOk := False;
        Break;
      end;
    end;

    if not LDepsOk then
    begin
      Result := False;
      Inc(FFailCount);
      FFailedTests.Add(Format('%s [%s] (dependency failed)',
        [ATestName, TargetName(LTgt)]));
      DoTally(LTgt, 0, 1, 0);
    end
    else if RunTestFile(LFilePath, ARunMode, ADefine, ADefineValue,
      AOptLevels, ASubsystem, AHasSubsystemOverride) then
    begin
      Inc(FPassCount);
      DoTally(LTgt, 1, 0, 0);
    end
    else if FLastTestSkipped then
    begin
      Inc(FSkipCount);
      DoTally(LTgt, 0, 0, 1);
    end
    else
    begin
      Result := False;
      Inc(FFailCount);
      FFailedTests.Add(Format('%s [%s]', [ATestName, TargetName(LTgt)]));
      DoTally(LTgt, 0, 1, 0);
    end;

    if LTgt <> LLast then
    begin
      Print('');
      Print(COLOR_BLUE + '- - - - - - - - - - - - - - - - - - - - ');
      Print('');
    end;
  end;
end;

function TMyrTester.RunTestByIndex(const AIndex: Integer): Boolean;
var
  LEntry: TMyrTestEntry;
begin
  Result := True;
  if AIndex < 0 then
  begin
    RunAllTests();
    Exit(FFailCount = 0);
  end;

  if not FRegisteredTests.TryGetValue(AIndex, LEntry) then
  begin
    Print(COLOR_RED + 'ERROR: Test index %d not found', [AIndex]);
    Exit(False);
  end;

  Reset();
  Print(COLOR_CYAN + 'Running test #%d...', [AIndex]);
  Print('');

  if not RunTest(LEntry.TestName, LEntry.RunMode,
    LEntry.DefineName, LEntry.DefineValue,
    LEntry.OptLevels, LEntry.Subsystem,
    LEntry.HasSubsystemOverride) then
    Result := False;

  Print('');
  PrintResults();
  PrintMatrix();
end;

function TMyrTester.RunAllTests(): Integer;
var
  LFiles:      TStringDynArray;
  LFile:       string;
  LTotal:      Integer;
  LEntry:      TMyrTestEntry;
  LI:          Integer;
  LSortedKeys: TArray<Integer>;
begin
  Reset();

  if not TDirectory.Exists(FTestFolder) then
  begin
    Print(COLOR_RED + 'ERROR: Test folder not found: ' + FTestFolder);
    Exit(0);
  end;

  // If tests have been registered, run them in key order
  if FRegisteredTests.Count > 0 then
  begin
    LTotal := FRegisteredTests.Count;
    Print(COLOR_CYAN + 
      'Running %d registered test(s) in order...', [LTotal]);
    Print('');

    LSortedKeys := FRegisteredTests.Keys.ToArray();
    TArray.Sort<Integer>(LSortedKeys);

    for LI := 0 to High(LSortedKeys) do
    begin
      LEntry := FRegisteredTests[LSortedKeys[LI]];
      RunTest(LEntry.TestName, LEntry.RunMode,
        LEntry.DefineName, LEntry.DefineValue,
        LEntry.OptLevels, LEntry.Subsystem,
        LEntry.HasSubsystemOverride);
      Print('');
      Print(COLOR_BLUE + '----------------------------------------');
      Print('');
    end;
  end
  else
  begin
    // No registered tests -- scan directory (alphabetical)
    LFiles := TDirectory.GetFiles(FTestFolder, 'test_*' + MYR_SRCFILE_EXT);
    TArray.Sort<string>(LFiles);
    LTotal := Length(LFiles);

    Print(COLOR_CYAN + 
      'Found %d test(s) in %s', [LTotal, FTestFolder]);
    Print('');

    for LFile in LFiles do
    begin
      // Route through RunTest so the per-target loop and tally apply. An
      // unregistered file has no entry, so it runs on the tester's Targets.
      RunTest(TPath.GetFileNameWithoutExtension(LFile), rmNone);
      Print('');
      Print(COLOR_BLUE + '----------------------------------------');
      Print('');
    end;
  end;

  PrintResults();
  PrintMatrix();
  Result := FPassCount;
end;

function TMyrTester.RunTestsMatching(const APattern: string;
  const ARunMode: TMyrTestRunMode): Integer;
var
  LFiles:    TStringDynArray;
  LFile:     string;
  LTestName: string;
  LEntry:    TMyrTestEntry;
  LRunMode:  TMyrTestRunMode;
  LDefine:   string;
  LDefVal:   string;
  LOptLvls:  TMyrOptLevelSet;
  LSubsys:   TMyrSubsystem;
  LHasSub:   Boolean;
  LKey:      Integer;
begin
  Reset();

  if not TDirectory.Exists(FTestFolder) then
  begin
    Print(COLOR_RED + 'ERROR: Test folder not found: ' + FTestFolder);
    Exit(0);
  end;

  LFiles := TDirectory.GetFiles(FTestFolder, 'test_*' + MYR_SRCFILE_EXT);
  TArray.Sort<string>(LFiles);

  for LFile in LFiles do
  begin
    if TPath.GetFileName(LFile).Contains(APattern) then
    begin
      LTestName := TPath.GetFileNameWithoutExtension(LFile);

      // Look up registered entry to use its settings
      LRunMode := ARunMode;
      LDefine  := '';
      LDefVal  := '';
      LOptLvls := [];
      LSubsys  := ssConsole;
      LHasSub  := False;
      for LKey in FRegisteredTests.Keys do
      begin
        LEntry := FRegisteredTests[LKey];
        if SameText(LEntry.TestName, LTestName) then
        begin
          LRunMode := LEntry.RunMode;
          LDefine  := LEntry.DefineName;
          LDefVal  := LEntry.DefineValue;
          LOptLvls := LEntry.OptLevels;
          LSubsys  := LEntry.Subsystem;
          LHasSub  := LEntry.HasSubsystemOverride;
          Break;
        end;
      end;

      // Route through RunTest so the per-target loop and tally apply.
      RunTest(LTestName, LRunMode, LDefine, LDefVal,
        LOptLvls, LSubsys, LHasSub);
      Print('');
      Print(COLOR_BLUE + '----------------------------------------');
      Print('');
    end;
  end;

  Print('Pattern: ' + APattern);
  PrintResults();
  PrintMatrix();
  Result := FPassCount;
end;

procedure TMyrTester.PrintResults();
var
  LTotal: Integer;
  LI:     Integer;
begin
  LTotal := FPassCount + FFailCount + FSkipCount;

  Print('');
  Print(COLOR_CYAN + '=== RESULTS ===');
  if FFailCount = 0 then
  begin
    Print(COLOR_GREEN + 'Passed: %d / %d', [FPassCount, LTotal]);
    if FSkipCount > 0 then
      Print(COLOR_YELLOW + 'Skipped: %d', [FSkipCount]);
  end
  else
  begin
    Print(COLOR_RED + 'Passed: %d / %d', [FPassCount, LTotal]);
    if FSkipCount > 0 then
      Print(COLOR_YELLOW + 'Skipped: %d', [FSkipCount]);
    Print('');
    Print(COLOR_RED + 'Failed tests:');
    for LI := 0 to FFailedTests.Count - 1 do
      Print(COLOR_RED + '  - ' + FFailedTests[LI]);
  end;
end;

procedure TMyrTester.SaveTests(const AFilename: string);
var
  LPath:    string;
  LKeys:    TArray<Integer>;
  LI:       Integer;
  LEntry:   TMyrTestEntry;
  LJson:    TJSON;
  LJ:       Integer;
  LOpt:     TMyrOptimizeLevel;
  LTgt:     TMyrTargetKind;
begin
  LPath := TPath.Combine(FTestFolder, AFilename);

  LKeys := FRegisteredTests.Keys.ToArray();
  TArray.Sort<Integer>(LKeys);

  LJson := TJSON.Create();
  try
    LJson.BeginArray('tests');

    for LI := 0 to High(LKeys) do
    begin
      LEntry := FRegisteredTests[LKeys[LI]];

      LJson.BeginObject();
      LJson.Add('index', LKeys[LI]);
      LJson.Add('name', LEntry.TestName);

      if LEntry.Category <> '' then
        LJson.Add('category', LEntry.Category);

      if Length(LEntry.Dependencies) > 0 then
      begin
        LJson.BeginArray('deps');
        for LJ := 0 to High(LEntry.Dependencies) do
          LJson.Add(LEntry.Dependencies[LJ]);
        LJson.EndArray();
      end;

      // Absent means: runs on the tester's Targets.
      if LEntry.Targets <> [] then
      begin
        LJson.BeginArray('targets');
        for LTgt := Low(TMyrTargetKind) to High(TMyrTargetKind) do
        begin
          if LTgt in LEntry.Targets then
            LJson.Add(Ord(LTgt));
        end;
        LJson.EndArray();
      end;

      if LEntry.RunMode = rmNone then
        LJson.Add('run_mode', 'none')
      else if LEntry.RunMode = rmDebug then
        LJson.Add('run_mode', 'debug')
      else
        LJson.Add('run_mode', 'execute');

      if LEntry.DefineName <> '' then
        LJson.Add('define', LEntry.DefineName);

      if LEntry.DefineValue <> '' then
        LJson.Add('define_value', LEntry.DefineValue);

      // Save per-test opt levels (if overridden)
      if LEntry.OptLevels <> [] then
      begin
        LJson.BeginArray('opt_levels');
        for LOpt := Low(TMyrOptimizeLevel) to High(TMyrOptimizeLevel) do
        begin
          if LOpt in LEntry.OptLevels then
            LJson.Add(Ord(LOpt));
        end;
        LJson.EndArray();
      end;

      // Save per-test subsystem (if overridden)
      if LEntry.HasSubsystemOverride then
      begin
        if LEntry.Subsystem = ssGui then
          LJson.Add('subsystem', 'gui')
        else
          LJson.Add('subsystem', 'console');
      end;

      LJson.EndObject();
    end;

    LJson.EndArray();
    LJson.SaveToFile(LPath);
  finally
    LJson.Free();
  end;
end;

function TMyrTester.LoadTests(const AFilename: string): Boolean;
var
  LPath:        string;
  LJson:        TJSON;
  LTests:       TJSON;
  LItem:        TJSON;
  LIndex:       Integer;
  LName:        string;
  LDeps:        TArray<string>;
  LRunModeStr:  string;
  LRunMode:     TMyrTestRunMode;
  LDefine:      string;
  LDefineValue: string;
  LEntry:       TMyrTestEntry;
  LOptItem:     TJSON;
  LSubStr:      string;
begin
  Result := False;
  LPath := TPath.Combine(FTestFolder, AFilename);

  if not TFile.Exists(LPath) then
    Exit;

  LJson := TJSON.FromFile(LPath);
  try
    LTests := LJson.Get('tests');
    if LTests.IsNull() then
      Exit;

    ClearRegisteredTests();

    for LItem in LTests do
    begin
      LName := LItem.Get('name').AsString();
      if LName = '' then
        Continue;

      LIndex       := LItem.Get('index').AsInt32(0);
      LDefine      := LItem.Get('define').AsString();
      LDefineValue := LItem.Get('define_value').AsString();

      // Extract dependencies array
      if LItem.Has('deps') then
        LDeps := LItem.Get('deps').AsStringArray()
      else
        SetLength(LDeps, 0);

      // Determine run mode
      LRunModeStr := LItem.Get('run_mode').AsString();
      if SameText(LRunModeStr, 'none') then
        LRunMode := rmNone
      else if SameText(LRunModeStr, 'debug') then
        LRunMode := rmDebug
      else
        LRunMode := rmExecute;

      LEntry.TestName             := LName;
      LEntry.Category             := LItem.Get('category').AsString();
      LEntry.Dependencies         := LDeps;
      LEntry.Targets              := [];
      LEntry.RunMode              := LRunMode;
      LEntry.DefineName           := LDefine;
      LEntry.DefineValue          := LDefineValue;
      LEntry.OptLevels            := [];
      LEntry.Subsystem            := ssConsole;
      LEntry.HasSubsystemOverride := False;

      // Load per-test targets (if present)
      if LItem.Has('targets') then
      begin
        for LOptItem in LItem.Get('targets') do
          Include(LEntry.Targets, TMyrTargetKind(LOptItem.AsInt32(0)));
      end;

      // Load per-test opt levels (if present)
      if LItem.Has('opt_levels') then
      begin
        LEntry.OptLevels := [];
        for LOptItem in LItem.Get('opt_levels') do
          Include(LEntry.OptLevels, TMyrOptimizeLevel(LOptItem.AsInt32(0)));
      end;

      // Load per-test subsystem (if present)
      if LItem.Has('subsystem') then
      begin
        LSubStr := LItem.Get('subsystem').AsString();
        if SameText(LSubStr, 'gui') then
          LEntry.Subsystem := ssGui
        else
          LEntry.Subsystem := ssConsole;
        LEntry.HasSubsystemOverride := True;
      end;

      FRegisteredTests.Add(LIndex, LEntry);
    end;

    Result := FRegisteredTests.Count > 0;
  finally
    LJson.Free();
  end;
end;

end.
