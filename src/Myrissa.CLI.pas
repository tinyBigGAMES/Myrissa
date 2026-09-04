{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Myrissa.CLI - Command-line front-end

  Parses command-line arguments, configures the compiler, runs the full
  pipeline. Single entry point: TMyrCLI.Execute().

  Dependencies: Myrissa.Compiler, Myrissa.ZigBuild, StdApp.Console
===============================================================================}

unit Myrissa.CLI;

interface

uses
  System.IOUtils,
  StdApp.Console,
  Myrissa.Common,
  Myrissa.Compiler;

type

  { TMyrCLI }
  TMyrCLI = class
  private
    FCompiler: TMyrCompiler;
    FSourceFile: string;
    FAutoRun: Boolean;
    FDebug: Boolean;
    FTarget: string;
    FOutputPath: string;
    FSubsystem: string;
    FOptLevel: string;
    FDumpSSA: Boolean;
    FCImportFile: string;
    procedure ShowBanner();
    procedure ShowHelp();
    procedure ShowErrors();
    procedure SetupCallbacks();
    function ParseArgs(): Boolean;
    procedure DoCompile();
    procedure DoDebug();
    procedure DoCImport();
  public
    constructor Create();
    destructor Destroy(); override;
    procedure Execute();
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  StdApp.Base,
  StdApp.Utils,
  Myrissa.CImporter.Script,
  Myrissa.Debug,
  Myrissa.Backend;

{ TMyrCLI }

constructor TMyrCLI.Create();
begin
  inherited Create();

  FCompiler := TMyrCompiler.Create();
  FSourceFile := '';
  FAutoRun := False;
  FDebug := False;
  FTarget := '';
  FOutputPath := '';
  FSubsystem := '';
  FOptLevel := '';
  FDumpSSA := False;
  FCImportFile := '';
end;

destructor TMyrCLI.Destroy();
begin
  FreeAndNil(FCompiler);

  inherited Destroy();
end;

procedure TMyrCLI.ShowBanner();
var
  LVerInfo: TVersionInfo;
begin
  LVerInfo := Default(TVersionInfo);

  (*
  LVerInfo.ProductName := 'Myrissa™ CLI';
  LVerInfo.VersionString := MYR_VERSION;
  LVerInfo.Copyright := 'Copyright © 2026-present tinyBigGAMES™ LLC';
  LVerInfo.URL := 'https://myrissa.org';
  *)

  TUtils.GetVersionInfo(LVerInfo);

  TConsole.PrintLn(COLOR_WHITE + COLOR_BOLD +
    Format('%s v%s', [LVerInfo.ProductName, LVerInfo.VersionString]));
  TConsole.PrintLn(COLOR_WHITE +
    Format('%s, All Rights Reserved.', [LVerInfo.Copyright]));
  TConsole.PrintLn(COLOR_YELLOW + LVerInfo.URL);

  TConsole.PrintLn('');
end;

procedure TMyrCLI.ShowHelp();
var
  LExeName: string;
begin
  LExeName := TPath.GetFileNameWithoutExtension(ParamStr(0));

  TConsole.PrintLn(COLOR_BOLD + 'USAGE:');
  TConsole.PrintLn('  ' + LExeName + ' ' + COLOR_CYAN +
    '<source>' + COLOR_RESET + ' [OPTIONS]');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'SUBCOMMANDS:');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'cimport <script.cps>   ' + COLOR_RESET +
    '  Run a C import script to generate bindings');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'REQUIRED:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '<source>' + COLOR_RESET +
    '                  Myrissa source file (.myr)');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'OPTIONS:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-r, --run              ' + COLOR_RESET +
    '  Run the compiled executable after building');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-d, --debug            ' + COLOR_RESET +
    '  Build and debug the compiled binary');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-t, --target    <target>' + COLOR_RESET +
    '  Set compilation target (e.g. win64)');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-o, --output    <path>  ' + COLOR_RESET +
    '  Set output directory');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-sub, --subsystem <type>' + COLOR_RESET +
    '  Set subsystem: console (default), gui');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-opt, --optimize <level>' + COLOR_RESET +
    '  Set optimize level: none (default), basic, full');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-h, --help             ' + COLOR_RESET +
    '  Display this help message');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'EXAMPLES:');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello -r');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello -r -t linux64');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello -r -opt release_fast');
  TConsole.PrintLn('');
end;

procedure TMyrCLI.ShowErrors();
begin
  FCompiler.PrintErrors();
end;

procedure TMyrCLI.SetupCallbacks();
begin
  FCompiler.SetStatusCallback(
    procedure(const AText: string; const AUserData: Pointer)
    begin
      TConsole.PrintLn(AText);
    end, nil);
end;

function TMyrCLI.ParseArgs(): Boolean;
var
  LI: Integer;
  LFlag: string;
begin
  Result := True;

  if ParamCount() = 0 then
  begin
    ShowHelp();
    Result := False;
    Exit;
  end;

  LI := 1;
  while LI <= ParamCount() do
  begin
    LFlag := ParamStr(LI).Trim();

    if (LFlag = '-h') or (LFlag = '--help') then
    begin
      ShowHelp();
      Result := False;
      Exit;
    end
    else if (LFlag = '-r') or (LFlag = '--run') then
    begin
      FAutoRun := True;
    end
    else if (LFlag = '-d') or (LFlag = '--debug') then
    begin
      FDebug := True;
    end
    else if (LFlag = '-ds') or (LFlag = '--dump-ssa') then
    begin
      FDumpSSA := True;
    end
    else if (LFlag = '-t') or (LFlag = '--target') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires a target argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FTarget := ParamStr(LI).Trim();
    end
    else if (LFlag = '-o') or (LFlag = '--output') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires a path argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FOutputPath := ParamStr(LI).Trim();
    end
    else if (LFlag = '-sub') or (LFlag = '--subsystem') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires a subsystem argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FSubsystem := ParamStr(LI).Trim();
    end
    else if (LFlag = '-opt') or (LFlag = '--optimize') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires an optimize level argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FOptLevel := ParamStr(LI).Trim();
    end
    else if LFlag.StartsWith('-') then
    begin
      TConsole.PrintLn(COLOR_RED + 'Error: Unknown flag: ' +
        COLOR_YELLOW + LFlag);
      TConsole.PrintLn('');
      TConsole.PrintLn('Run ' + COLOR_CYAN +
        TPath.GetFileNameWithoutExtension(ParamStr(0)) + ' -h' +
        COLOR_RESET + ' to see available options');
      TConsole.PrintLn('');
      ExitCode := 2;
      Result := False;
      Exit;
    end
    else
    begin
      // Check for cimport subcommand
      if (FSourceFile = '') and (FCImportFile = '') and
         (LFlag.ToLower() = 'cimport') then
      begin
        Inc(LI);
        if LI > ParamCount() then
        begin
          TConsole.PrintLn(COLOR_RED + 'Error: cimport requires a script file argument');
          TConsole.PrintLn('');
          TConsole.PrintLn(COLOR_BOLD + 'USAGE:');
          TConsole.PrintLn('  ' + TPath.GetFileNameWithoutExtension(ParamStr(0)) +
            ' ' + COLOR_CYAN + 'cimport <script.mys>' + COLOR_RESET);
          TConsole.PrintLn('');
          ExitCode := 2;
          Result := False;
          Exit;
        end;
        FCImportFile := ParamStr(LI).Trim();
        if (FCImportFile = '-h') or (FCImportFile = '--help') then
        begin
          FCImportFile := '-h';
        end
        else
        begin
          if not FCImportFile.EndsWith('.mys', True) then
            FCImportFile := FCImportFile + '.mys';
          if not TFile.Exists(FCImportFile) then
          begin
            TConsole.PrintLn(COLOR_RED +
              'Error: Script file not found: ' + COLOR_YELLOW + FCImportFile);
            TConsole.PrintLn('');
            ExitCode := 2;
            Result := False;
            Exit;
          end;
        end;
      end
      // Positional argument: source file
      else if FSourceFile = '' then
        FSourceFile := LFlag
      else
      begin
        TConsole.PrintLn(COLOR_RED +
          'Error: Unexpected argument: ' + COLOR_YELLOW + LFlag);
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
    end;

    Inc(LI);
  end;

  // Validate: source file is required (unless cimport mode)
  if (FSourceFile = '') and (FCImportFile = '') then
  begin
    TConsole.PrintLn(COLOR_RED +
      'Error: Source file is required');
    TConsole.PrintLn('');
    TConsole.PrintLn('Run ' + COLOR_CYAN +
      TPath.GetFileNameWithoutExtension(ParamStr(0)) + ' -h' +
      COLOR_RESET + ' to see available options');
    TConsole.PrintLn('');
    ExitCode := 2;
    Result := False;
    Exit;
  end;

  // Validate: -r and -d are mutually exclusive
  if FAutoRun and FDebug then
  begin
    TConsole.PrintLn(COLOR_RED +
      'Error: -r and -d cannot be used together');
    TConsole.PrintLn('');
    ExitCode := 2;
    Result := False;
    Exit;
  end;

  // Source file validation (skip in cimport mode)
  if FSourceFile <> '' then
  begin
    // Normalize source file extension
    FSourceFile := TUtils.ResolvePath(TPath.ChangeExtension(FSourceFile, MYR_SRCFILE_EXT));

    // Validate: source file must exist
    if not TFile.Exists(FSourceFile) then
    begin
      TConsole.PrintLn(COLOR_RED +
        'Error: Source file not found: ' + COLOR_YELLOW + FSourceFile);
      TConsole.PrintLn('');
      ExitCode := 2;
      Result := False;
      Exit;
    end;
  end;
end;

procedure TMyrCLI.DoCompile();
var
  LOutputPath: string;
  LTarget: string;
  LSubsystem: string;
  LOptLevel: string;
  LDumpSSA: Boolean;
  LCLIOutputPath: string;
begin
  SetupCallbacks();

  // Register pre-parse callback to store CLI directives in key-value store
  LTarget := FTarget;
  LSubsystem := FSubsystem;
  LOptLevel := FOptLevel;
  LCLIOutputPath := FOutputPath;
  LDumpSSA := FDumpSSA;
  FCompiler.AddPreParseCallback(
    procedure(const ACompiler: TMyrCompiler; const AUserData: Pointer)
    begin
      if LTarget <> '' then
        ACompiler.SetKeyValue('target', LTarget);
      if LSubsystem <> '' then
        ACompiler.SetKeyValue('subsystem', LSubsystem);
      if LOptLevel <> '' then
        ACompiler.SetKeyValue('optimize', LOptLevel);
      if LCLIOutputPath <> '' then
        ACompiler.SetKeyValue('outputpath', LCLIOutputPath);
      if LDumpSSA then
        ACompiler.SetKeyValue('dumpssa', 'on');
    end);

  // Determine output path
  if FOutputPath <> '' then
    LOutputPath := TUtils.ResolvePath(FOutputPath)
  else
    LOutputPath := TUtils.ResolvePath('output');

  // Compile
  FCompiler.Compile(FSourceFile, LOutputPath, FAutoRun);

  // Display errors
  ShowErrors();

  if FCompiler.GetErrors().HasErrors() then
  begin
    TConsole.PrintLn(COLOR_RED + 'Failed.');
    ExitCode := 1;
  end
  else
    ExitCode := FCompiler.GetLastExitCode();
end;

//win64

{ TMyrCLI.DoDebug }
procedure TMyrCLI.DoDebug();
var
  LExePath: string;
  LREPL: TMyrDebugREPL;
begin
  // Debugger is Win64 only
  if not SameText(FCompiler.GetTarget(), MYR_DEFAULT_TARGET) then

  begin
    TConsole.PrintLn(COLOR_RED + 'Error: Debugger requires win64 target.');
    ExitCode := 1;
    Exit;
  end;

  LExePath := FCompiler.GetOutputFilename();

  if not FileExists(LExePath) then
  begin
    TConsole.PrintLn(COLOR_RED + 'Executable not found: ' + LExePath);
    ExitCode := 1;
    Exit;
  end;

  LREPL := TMyrDebugREPL.Create();
  try
    LREPL.Run(LExePath);
  finally
    LREPL.Free();
  end;
end;

{ TMyrCLI.DoCImport }
procedure TMyrCLI.DoCImport();
var
  LScript: TMyrCImportScript;
begin
  LScript := TMyrCImportScript.Create();
  try
    LScript.SetStatusCallback(
      procedure(const AText: string; const AUserData: Pointer)
      begin
        TConsole.PrintLn(AText);
      end, nil);

    if FCImportFile = '-h' then
    begin
      LScript.ShowHelp();
      Exit;
    end;

    if not LScript.ExecuteFile(FCImportFile) then
    begin
      LScript.PrintErrors();
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'CImport failed.');
      ExitCode := 1;
    end
    else
    begin
      TConsole.PrintLn(COLOR_GREEN + 'CImport completed successfully.');
      ExitCode := 0;
    end;
  finally
    LScript.Free();
  end;
end;

procedure TMyrCLI.Execute();
begin
  ShowBanner();

  if not ParseArgs() then
    Exit;

  try
    if FCImportFile <> '' then
      DoCImport()
    else
    begin
      DoCompile();

      if FDebug and (not FCompiler.GetErrors().HasErrors()) then
        DoDebug();
    end;
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + COLOR_BOLD + 'Fatal Error: ' +
        E.Message + COLOR_RESET);
      TConsole.PrintLn('');
      ExitCode := 1;
    end;
  end;
end;

end.
