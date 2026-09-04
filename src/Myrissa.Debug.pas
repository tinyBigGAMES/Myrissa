{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
===============================================================================}

unit Myrissa.Debug;

{$I StdApp.Defines.inc}

interface

uses
  WinApi.Windows,
  WinApi.WinSock,
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Console,
  StdApp.JSON,
  Myrissa.Common,
  Myrissa.Backend;

const
  TRAP_FLAG = $100;
  INT3_OPCODE = $CC;
  CDefaultDAPPort = 4711;
  CTimeoutContinueMS = 5000;
  CTimeoutStepMS = 2000;

type
  TMyrDebugContext = WinApi.Windows.TContext;
  TMyrDebugEvent = WinApi.Windows.TDebugEvent;

  { TMyrDebugStopReason }
  TMyrDebugStopReason = (
    dsrNone,
    dsrBreakpoint,
    dsrSingleStep,
    dsrException,
    dsrProcessExit,
    dsrDllLoad
  );

  { TMyrResumeAction }
  TMyrResumeAction = (
    raContinue,
    raStepOver,
    raStepIn,
    raStepOut
  );

  { TMyrDebugMode }
  TMyrDebugMode = (
    dmExe,
    dmDll
  );

  { TMyrDAPState }
  TMyrDAPState = (
    dsIdle,
    dsListening,
    dsConnected,
    dsInitialized,
    dsConfiguring,
    dsRunning,
    dsStopped,
    dsTerminated
  );

  { TMyrDAPClientState }
  TMyrDAPClientState = (
    dcsDisconnected,
    dcsConnected,
    dcsInitialized,
    dcsLaunched,
    dcsStopped,
    dcsExited
  );

  { TMyrDebugStopEvent }
  TMyrDebugStopEvent = record
    Reason: TMyrDebugStopReason;
    Address: UInt64;
    CodeOffset: Cardinal;
    ThreadId: DWORD;
    ExitCode: Cardinal;
    ExceptionCode: Cardinal;
    ExceptionMessage: string;
  end;

  { TMyrBreakpointInfo }
  TMyrBreakpointInfo = record
    ID: Integer;
    SourceFile: string;
    SourceLine: Integer;
    CodeOffset: Cardinal;
    OriginalByte: Byte;
    IsTemporary: Boolean;
    IsEnabled: Boolean;
    IsPatched: Boolean;
    HitCount: Integer;
    Condition: string;
    HitCondition: Integer;
  end;

  { TMyrDebugStackFrame }
  TMyrDebugStackFrame = record
    FrameID: Integer;
    FunctionName: string;
    SourceFile: string;
    SourceLine: Integer;
    SourceColumn: Integer;
    CodeOffset: Cardinal;
    RBP: UInt64;
    RIP: UInt64;
  end;

  { TMyrDebugVariable }
  TMyrDebugVariable = record
    VarName: string;
    VarValue: string;
    VarType: string;
    IsParam: Boolean;
  end;

  { TMyrDAPClientVariable }
  TMyrDAPClientVariable = record
    VarName: string;
    VarValue: string;
    VarType: string;
    VariablesReference: Integer;
  end;

  { TMyrDAPClientStackFrame }
  TMyrDAPClientStackFrame = record
    FrameID: Integer;
    FunctionName: string;
    SourceFile: string;
    SourceLine: Integer;
  end;

  { TMyrDAPClientScope }
  TMyrDAPClientScope = record
    ScopeName: string;
    VariablesReference: Integer;
    Expensive: Boolean;
  end;

  { TMyrREPLBreakpoint }
  TMyrREPLBreakpoint = record
    SourceFile: string;
    SourceLine: Integer;
    Verified: Boolean;
  end;

  // Callbacks
  TMyrDAPClientStoppedCallback = reference to procedure(const AReason: string; const AThreadId: Integer);
  TMyrDAPClientOutputCallback = reference to procedure(const AOutput: string);
  TMyrDAPClientExitedCallback = reference to procedure(const AExitCode: Integer);

  // Forwards
  TMyrPEDebugTarget = class;
  TMyrDebugServer = class;
  TMyrDebugRuntime = class;
  TMyrDAPServer = class;

  { TMyrDebugTarget }
  TMyrDebugTarget = class(TBaseObject)
  protected
    FBreakOnExceptions: Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    function ReadByte(const AAddress: UInt64): Byte; virtual; abstract;
    procedure WriteByte(const AAddress: UInt64; const AValue: Byte); virtual; abstract;
    function ReadUInt64(const AAddress: UInt64): UInt64; virtual; abstract;
    function ReadBytes(const AAddress: UInt64; const ASize: Cardinal): TBytes; virtual;
    procedure FlushCode(const AAddress: UInt64; const ASize: Cardinal); virtual; abstract;
    procedure Resume(); virtual; abstract;
    procedure SetTrapFlag(); virtual; abstract;
    procedure ClearTrapFlag(); virtual; abstract;
    function GetContext(): TMyrDebugContext; virtual; abstract;
    procedure SetContext(const AContext: TMyrDebugContext); virtual; abstract;
    function CodeOffsetToAddress(const AOffset: Cardinal): UInt64; virtual; abstract;
    function AddressToCodeOffset(const AAddress: UInt64): Cardinal; virtual; abstract;
    function DataOffsetToAddress(const AOffset: Cardinal): UInt64; virtual;
    function IsOurCode(const AAddress: UInt64): Boolean; virtual; abstract;
    procedure SetRepatchOffset(const AOffset: Integer); virtual;
    function GetRepatchOffset(): Integer; virtual;
    procedure SetDebugActive(const AActive: Boolean); virtual;
    procedure SignalConfigDone(); virtual;
    procedure WaitUntilReady(); virtual;
    procedure UnblockWaitForStop(); virtual;
    function Start(): Boolean; virtual; abstract;
    procedure Stop(); virtual; abstract;
    function WaitForStop(out AEvent: TMyrDebugStopEvent): Boolean; virtual; abstract;
    function IsRunning(): Boolean; virtual; abstract;
    procedure SetBreakOnExceptions(const AEnabled: Boolean);
    function GetBreakOnExceptions(): Boolean;
  end;

  { TMyrPEDebugLoopThread }
  TMyrPEDebugLoopThread = class(TThread)
  private
    FTarget: TMyrPEDebugTarget;
    function IsTargetDll(const AEvent: TMyrDebugEvent): Boolean;
  protected
    procedure Execute(); override;
  public
    constructor Create(const ATarget: TMyrPEDebugTarget);
  end;

  { TMyrPEDebugTarget }
  TMyrPEDebugTarget = class(TMyrDebugTarget)
  private
    FExePath: string;
    FProcessHandle: THandle;
    FMainThreadHandle: THandle;
    FProcessId: DWORD;
    FMainThreadId: DWORD;
    FActualImageBase: UInt64;
    FTextSectionRVA: Cardinal;
    FTextSectionSize: Cardinal;
    FDataSectionRVA: Cardinal;
    FStoppedEvent: THandle;
    FResumeEvent: THandle;
    FCapturedContext: TMyrDebugContext;
    FStoppedReason: TMyrDebugStopReason;
    FStoppedAddress: UInt64;
    FStoppedThreadId: DWORD;
    FExceptionCode: Cardinal;
    FStarted: Boolean;
    FExitCode: Cardinal;
    FProcessExited: Boolean;
    FInitialBreakpointSeen: Boolean;
    FRepatchOffset: Integer;
    FConfigDoneEvent: THandle;
    FReadyEvent: THandle;
    FLaunchDoneEvent: THandle;
    FLaunchPath: string;
    FLaunchSucceeded: Boolean;
    FLaunchError: string;
    FDebugLoopThread: TMyrPEDebugLoopThread;
    FDllPath: string;
    FHostExePath: string;
    FIsAttachedToDll: Boolean;
    FDllBaseAddress: UInt64;
    FDllFound: Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetExePath(const APath: string);
    procedure SetTextSectionRVA(const ARVA: Cardinal);
    procedure SetTextSectionSize(const ASize: Cardinal);
    procedure SetDataSectionRVA(const ARVA: Cardinal);
    procedure SetDllMode(const ADllPath: string; const AHostExePath: string);
    function ReadByte(const AAddress: UInt64): Byte; override;
    procedure WriteByte(const AAddress: UInt64; const AValue: Byte); override;
    function ReadUInt64(const AAddress: UInt64): UInt64; override;
    procedure FlushCode(const AAddress: UInt64; const ASize: Cardinal); override;
    procedure Resume(); override;
    procedure SetTrapFlag(); override;
    procedure ClearTrapFlag(); override;
    function GetContext(): TMyrDebugContext; override;
    procedure SetContext(const AContext: TMyrDebugContext); override;
    function CodeOffsetToAddress(const AOffset: Cardinal): UInt64; override;
    function AddressToCodeOffset(const AAddress: UInt64): Cardinal; override;
    function DataOffsetToAddress(const AOffset: Cardinal): UInt64; override;
    function IsOurCode(const AAddress: UInt64): Boolean; override;
    function Start(): Boolean; override;
    procedure Stop(); override;
    function WaitForStop(out AEvent: TMyrDebugStopEvent): Boolean; override;
    function IsRunning(): Boolean; override;
    procedure SetRepatchOffset(const AOffset: Integer); override;
    function GetRepatchOffset(): Integer; override;
    procedure SignalConfigDone(); override;
    procedure WaitUntilReady(); override;
    procedure UnblockWaitForStop(); override;
    property ProcessHandle: THandle read FProcessHandle;
    property ExitCodeValue: Cardinal read FExitCode;
    property IsAttachedToDll: Boolean read FIsAttachedToDll;
    property DllFound: Boolean read FDllFound;
    property DllBaseAddress: UInt64 read FDllBaseAddress;
  end;

  { TMyrBreakpointManager }
  TMyrBreakpointManager = class(TBaseObject)
  private
    FTarget: TMyrDebugTarget;
    FSourceMap: TMyrSourceMap;
    FBreakpoints: TList<TMyrBreakpointInfo>;
    FNextID: Integer;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetTarget(const ATarget: TMyrDebugTarget);
    procedure SetSourceMap(const ASourceMap: TMyrSourceMap);
    function SetBreakpoint(const AFile: string; const ALine: Integer;
      const ACondition: string = ''; const AHitCondition: Integer = 0): Integer;
    function RemoveBreakpoint(const AID: Integer): Boolean;
    function SetTempBreakpoint(const AOffset: Cardinal): Integer;
    procedure RemoveAllTemp();
    procedure RemoveAll();
    function IsOurBreakpoint(const AOffset: Cardinal): Boolean;
    function GetBreakpointAt(const AOffset: Cardinal; out AInfo: TMyrBreakpointInfo): Boolean;
    function GetBreakpointByID(const AID: Integer; out AInfo: TMyrBreakpointInfo): Boolean;
    function GetBreakpointCount(): Integer;
    function GetBreakpoint(const AIndex: Integer): TMyrBreakpointInfo;
    procedure ApplyAll();
    procedure PatchBreakpoint(const AIndex: Integer);
    procedure UnpatchBreakpoint(const AIndex: Integer);
  end;

  { TMyrStackWalker }
  TMyrStackWalker = class(TBaseObject)
  public
    function WalkStack(const ATarget: TMyrDebugTarget;
      const ASourceMap: TMyrSourceMap;
      const AContext: TMyrDebugContext): TArray<TMyrDebugStackFrame>;
  end;

  { TMyrDebugRuntime }
  TMyrDebugRuntime = class(TBaseObject)
  private
    FTarget: TMyrDebugTarget;
    FSourceMap: TMyrSourceMap;
    FBreakpoints: TMyrBreakpointManager;
    FStackWalker: TMyrStackWalker;
    FLastStopEvent: TMyrDebugStopEvent;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetTarget(const ATarget: TMyrDebugTarget);
    procedure SetSourceMap(const ASourceMap: TMyrSourceMap);
    function SetBreakpoint(const AFile: string; const ALine: Integer;
      const ACondition: string = ''; const AHitCondition: Integer = 0): Integer;
    function RemoveBreakpoint(const AID: Integer): Boolean;
    function Continue(): Boolean;
    function StepOver(): Boolean;
    function StepIn(): Boolean;
    function StepOut(): Boolean;
    function WaitForStop(): Boolean;
    procedure ConfigurationDone();
    function GetCallStack(): TArray<TMyrDebugStackFrame>;
    function GetLastStopEvent(): TMyrDebugStopEvent;
    function GetVariables(): TArray<TMyrDebugVariable>;
    function Evaluate(const AExpression: string): TMyrDebugVariable;
    function GetBreakpoints(): TMyrBreakpointManager;
    function GetTarget(): TMyrDebugTarget;
    function GetSourceMap(): TMyrSourceMap;
  end;

  { TMyrDAPServer }
  TMyrDAPServer = class(TBaseObject)
  private
    FRuntime: TMyrDebugRuntime;
    FSourceMap: TMyrSourceMap;
    FPort: Integer;
    FState: TMyrDAPState;
    FSeq: Integer;
    FListenSocket: TSocket;
    FClientSocket: TSocket;
    FWSAData: TWSAData;
    FWSAInitialized: Boolean;
    FSourceRoot: string;
    FVerboseLogging: Boolean;
    FProgram: string;
    FStopOnEntry: Boolean;
    function ReadMessage(): TJSON;
    procedure SendMessage(const AMsg: TJSON);
    procedure SendResponse(const ARequestSeq: Integer;
      const ACommand: string; const ASuccess: Boolean;
      const ABody: TJSON = nil; const AMessage: string = '');
    procedure SendEvent(const AEventName: string; const ABody: TJSON = nil);
    procedure HandleInitialize(const ASeq: Integer; const AArgs: TJSON);
    procedure HandleLaunch(const ASeq: Integer; const AArgs: TJSON);
    procedure HandleSetBreakpoints(const ASeq: Integer; const AArgs: TJSON);
    procedure HandleConfigurationDone(const ASeq: Integer);
    procedure HandleThreads(const ASeq: Integer);
    procedure HandleStackTrace(const ASeq: Integer; const AArgs: TJSON);
    procedure HandleScopes(const ASeq: Integer; const AArgs: TJSON);
    procedure HandleVariables(const ASeq: Integer; const AArgs: TJSON);
    procedure HandleContinue(const ASeq: Integer);
    procedure HandleNext(const ASeq: Integer);
    procedure HandleStepIn(const ASeq: Integer);
    procedure HandleStepOut(const ASeq: Integer);
    procedure HandlePause(const ASeq: Integer);
    procedure HandleDisconnect(const ASeq: Integer);
    procedure HandleEvaluate(const ASeq: Integer; const AArgs: TJSON);
    procedure HandleSetExceptionBreakpoints(const ASeq: Integer; const AArgs: TJSON);
    procedure DispatchRequest(const AMsg: TJSON);
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetRuntime(const ARuntime: TMyrDebugRuntime);
    procedure SetSourceMap(const ASourceMap: TMyrSourceMap);
    function StartListening(const APort: Integer): Boolean;
    function WaitForConnection(): Boolean;
    procedure RunMessageLoop();
    procedure StopServer();
    procedure ProcessStopEvent();
    function GetPort(): Integer;
    function GetState(): TMyrDAPState;
    property VerboseLogging: Boolean read FVerboseLogging write FVerboseLogging;
  end;

  { TMyrDebugClient }
  TMyrDebugClient = class(TBaseObject)
  private
    FSocket: TSocket;
    FState: TMyrDAPClientState;
    FNextSeq: Integer;
    FLastError: string;
    FCurrentThreadId: Integer;
    FVerboseLogging: Boolean;
    FReadBuffer: TBytes;
    FReadBufferLen: Integer;
    FOnStopped: TMyrDAPClientStoppedCallback;
    FOnOutput: TMyrDAPClientOutputCallback;
    FOnExited: TMyrDAPClientExitedCallback;
    function GetNextSeq(): Integer;
    procedure SetError(const AError: string);
    function SendRaw(const AData: string): Boolean;
    function ReadDAPMessage(out AJson: string; const ATimeoutMS: Integer = 5000): Boolean;
    procedure SendDAPMessage(const AJson: string);
    function SendRequest(const ACommand: string; const AArgs: TJSON = nil): TJSON;
    procedure ProcessEvent(const AEvent: TJSON);
  public
    constructor Create(); override;
    destructor Destroy(); override;
    function Connect(const AHost: string; const APort: Integer): Boolean;
    procedure Disconnect();
    function Initialize(): Boolean;
    function Launch(const AProgram: string; const AStopOnEntry: Boolean = False): Boolean;
    function ConfigurationDone(): Boolean;
    function SetBreakpoints(const ASourcePath: string;
      const ALines: array of Integer): Boolean; overload;
    function SetBreakpoints(const ASourcePath: string;
      const ALines: array of Integer;
      const AHitConditions: array of Integer): Boolean; overload;
    function Continue(): Boolean;
    function StepOver(): Boolean;
    function StepIn(): Boolean;
    function StepOut(): Boolean;
    function GetCallStack(const AThreadId: Integer = 0): TArray<TMyrDAPClientStackFrame>;
    function GetScopes(const AFrameId: Integer): TArray<TMyrDAPClientScope>;
    function GetVariables(const AVariablesReference: Integer): TArray<TMyrDAPClientVariable>;
    function Evaluate(const AExpression: string; const AFrameId: Integer = 0): string;
    procedure ProcessPendingEvents(const ATimeoutMS: Integer = 1000);
    function DisconnectDAP(): Boolean;
    function HasError(): Boolean;
    function GetLastError(): string;
    function GetState(): TMyrDAPClientState;
    function GetCurrentThreadId(): Integer;
    property State: TMyrDAPClientState read FState;
    property VerboseLogging: Boolean read FVerboseLogging write FVerboseLogging;
    property OnStopped: TMyrDAPClientStoppedCallback read FOnStopped write FOnStopped;
    property OnOutput: TMyrDAPClientOutputCallback read FOnOutput write FOnOutput;
    property OnExited: TMyrDAPClientExitedCallback read FOnExited write FOnExited;
  end;

  { TMyrDAPListenerThread }
  TMyrDAPListenerThread = class(TThread)
  private
    FServer: TMyrDAPServer;
  protected
    procedure Execute(); override;
  public
    constructor Create(const AServer: TMyrDAPServer);
  end;

  { TMyrStopWatcherThread }
  TMyrStopWatcherThread = class(TThread)
  private
    FDebugger: TMyrDebugServer;
  protected
    procedure Execute(); override;
  public
    constructor Create(const ADebugger: TMyrDebugServer);
  end;

  { TMyrDebugServer }
  TMyrDebugServer = class(TBaseObject)
  private
    FSourceMap: TMyrSourceMap;
    FTarget: TMyrDebugTarget;
    FRuntime: TMyrDebugRuntime;
    FDAPServer: TMyrDAPServer;
    FDAPThread: TMyrDAPListenerThread;
    FStopWatcher: TMyrStopWatcherThread;
    FPort: Integer;
    FMode: TMyrDebugMode;
    FOwnSourceMap: Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    function DebugExe(const AExePath: string; const APort: Integer = 4711): Boolean;
    function DebugDll(const ADllPath: string; const AHostExe: string = '';
      const APort: Integer = 4711): Boolean;
    procedure StopDebugging();
    function HasErrors(): Boolean;
    function HasWarnings(): Boolean;
    function HasHints(): Boolean;
    function HasFatal(): Boolean;
    function ErrorCount(): Integer;
    function WarningCount(): Integer;
    function GetErrorItems(): TList<TError>;
    function GetErrorText(): string;
    function GetRuntime(): TMyrDebugRuntime;
    function GetDAPServer(): TMyrDAPServer;
    function GetSourceMap(): TMyrSourceMap;
    property Port: Integer read FPort;
    property Mode: TMyrDebugMode read FMode;
  end;

  { TMyrDebugREPL }
  TMyrDebugREPL = class(TBaseObject)
  private
    FServer: TMyrDebugServer;
    FClient: TMyrDebugClient;
    FServerThread: TThread;
    FBreakpoints: TList<TMyrREPLBreakpoint>;
    FRunning: Boolean;
    FExePath: string;
    FPort: Integer;
    FPrompt: string;
    FTimeoutContinueMS: Integer;
    FTimeoutStepMS: Integer;
    FVerboseLogging: Boolean;
    procedure ProcessCommand(const ACommand: string);
    procedure ShowHelp();
    procedure HandleSetBreakpoint(const ACommand: string);
    procedure HandleListBreakpoints();
    procedure HandleDeleteBreakpoint(const ACommand: string);
    procedure HandleClearBreakpoints();
    procedure HandleBacktrace();
    procedure HandleLocals();
    procedure HandlePrint(const ACommand: string);
    procedure HandleContinue();
    procedure HandleNext();
    procedure HandleStepInto();
    procedure HandleStepOut();
    procedure HandleRestart();
    procedure HandleFile(const ACommand: string);
    procedure HandleVerbose(const ACommand: string);
    procedure HandleThreads();
    procedure StartSession();
    procedure StopSession();
    function DoDAHandshake(): Boolean;
    procedure ShowSourceContext();
    procedure SendBreakpointsForFile(const ASourceFile: string);
    procedure LoadBreakpointsFromMdbg(const APath: string);
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Run(const AExePath: string; const APort: Integer = CDefaultDAPPort);
    procedure Stop();
    property TimeoutContinueMS: Integer read FTimeoutContinueMS write FTimeoutContinueMS;
    property TimeoutStepMS: Integer read FTimeoutStepMS write FTimeoutStepMS;
    property VerboseLogging: Boolean read FVerboseLogging write FVerboseLogging;
  end;

implementation

{ TMyrDebugTarget }
constructor TMyrDebugTarget.Create();
begin
  inherited Create();
  FBreakOnExceptions := False;
end;

destructor TMyrDebugTarget.Destroy();
begin
  inherited Destroy();
end;

function TMyrDebugTarget.ReadBytes(const AAddress: UInt64;
  const ASize: Cardinal): TBytes;
var
  LI: Cardinal;
begin
  SetLength(Result, ASize);
  for LI := 0 to ASize - 1 do
    Result[LI] := ReadByte(AAddress + LI);
end;

procedure TMyrDebugTarget.SetRepatchOffset(const AOffset: Integer);
begin
  // Default no-op - overridden by concrete targets
end;

function TMyrDebugTarget.GetRepatchOffset(): Integer;
begin
  Result := -1;
end;

function TMyrDebugTarget.DataOffsetToAddress(const AOffset: Cardinal): UInt64;
begin
  // Default: not supported — PE target overrides with ImageBase + DataRVA + offset
  Result := 0;
end;

procedure TMyrDebugTarget.SetDebugActive(const AActive: Boolean);
begin
  // Default no-op - concrete targets may override
end;

procedure TMyrDebugTarget.SignalConfigDone();
begin
  // Default no-op — PE target overrides to release the held process
end;

procedure TMyrDebugTarget.WaitUntilReady();
begin
  // Default no-op — PE target overrides to wait for FActualImageBase
end;

procedure TMyrDebugTarget.UnblockWaitForStop();
begin
  // Default no-op — PE target overrides to signal FStoppedEvent
end;

procedure TMyrDebugTarget.SetBreakOnExceptions(const AEnabled: Boolean);
begin
  FBreakOnExceptions := AEnabled;
end;

function TMyrDebugTarget.GetBreakOnExceptions(): Boolean;
begin
  Result := FBreakOnExceptions;
end;


{ TMyrPEDebugLoopThread }
constructor TMyrPEDebugLoopThread.Create(const ATarget: TMyrPEDebugTarget);
begin
  inherited Create(True);  // Create suspended
  FreeOnTerminate := False;
  FTarget := ATarget;
end;

function TMyrPEDebugLoopThread.IsTargetDll(const AEvent: TMyrDebugEvent): Boolean;
var
  LNamePtr: Pointer;
  LBytesRead: NativeUInt;
  LNameBuf: array[0..519] of Byte;
  LDllName: string;
  LTargetName: string;
begin
  Result := False;

  // lpImageName is a pointer (in debuggee address space) to a pointer
  // to the DLL name string. Read the pointer first.
  if AEvent.LoadDll.lpImageName = nil then
    Exit;

  LNamePtr := nil;
  if not ReadProcessMemory(FTarget.FProcessHandle,
    AEvent.LoadDll.lpImageName, @LNamePtr, SizeOf(Pointer),
    LBytesRead) then
    Exit;

  if LNamePtr = nil then
    Exit;

  // Now read the actual name string from that pointer
  FillChar(LNameBuf, SizeOf(LNameBuf), 0);
  if not ReadProcessMemory(FTarget.FProcessHandle,
    LNamePtr, @LNameBuf[0], 520, LBytesRead) then
    Exit;

  // fUnicode flag indicates whether name is Unicode or ANSI
  if AEvent.LoadDll.fUnicode <> 0 then
    LDllName := PWideChar(@LNameBuf[0])
  else
    LDllName := string(PAnsiChar(@LNameBuf[0]));

  if LDllName = '' then
    Exit;

  // Compare filename portion (case-insensitive)
  LTargetName := ExtractFileName(FTarget.FDllPath);
  Result := SameText(ExtractFileName(LDllName), LTargetName);
end;

procedure TMyrPEDebugLoopThread.Execute();
var
  LEvent: TMyrDebugEvent;
  LContinueStatus: DWORD;
  LExCode: DWORD;
  LExAddr: UInt64;
  LContext: TMyrDebugContext;
  LRepatch: Integer;
  LSI: TStartupInfoW;
  LPI: TProcessInformation;
begin
  // CreateProcessW MUST be called on the same thread as WaitForDebugEvent
  // (Windows Debug API requirement)
  FillChar(LSI, SizeOf(LSI), 0);
  LSI.cb := SizeOf(LSI);
  FillChar(LPI, SizeOf(LPI), 0);

  if not CreateProcessW(
    PWideChar(FTarget.FLaunchPath),
    nil,
    nil, nil,
    False,
    DEBUG_ONLY_THIS_PROCESS or CREATE_UNICODE_ENVIRONMENT,
    nil,
    PWideChar(TPath.GetDirectoryName(FTarget.FLaunchPath)),
    LSI, LPI) then
  begin
    FTarget.FLaunchSucceeded := False;
    FTarget.FLaunchError := SysErrorMessage(GetLastError());
    SetEvent(FTarget.FLaunchDoneEvent);
    Exit;
  end;

  FTarget.FProcessHandle := LPI.hProcess;
  FTarget.FMainThreadHandle := LPI.hThread;
  FTarget.FProcessId := LPI.dwProcessId;
  FTarget.FMainThreadId := LPI.dwThreadId;
  FTarget.FLaunchSucceeded := True;
  SetEvent(FTarget.FLaunchDoneEvent);

  while not Terminated do
  begin
    // Use a timeout so we can check Terminated periodically
    if not WaitForDebugEvent(LEvent, 200) then
      Continue;

    LContinueStatus := DBG_CONTINUE;

    case LEvent.dwDebugEventCode of
      CREATE_PROCESS_DEBUG_EVENT:
      begin
        // Capture actual image base (handles ASLR)
        FTarget.FActualImageBase :=
          UInt64(LEvent.CreateProcessInfo.lpBaseOfImage);
        FTarget.FProcessHandle := LEvent.CreateProcessInfo.hProcess;
        FTarget.FMainThreadHandle := LEvent.CreateProcessInfo.hThread;
        FTarget.FMainThreadId := LEvent.dwThreadId;

        // Close the image file handle (we don't need it)
        if LEvent.CreateProcessInfo.hFile <> 0 then
          CloseHandle(LEvent.CreateProcessInfo.hFile);
      end;

      EXCEPTION_DEBUG_EVENT:
      begin
        LExCode := LEvent.Exception.ExceptionRecord.ExceptionCode;
        LExAddr := UInt64(LEvent.Exception.ExceptionRecord.ExceptionAddress);

        if LExCode = EXCEPTION_BREAKPOINT then
        begin
          // Skip the initial loader breakpoint from ntdll
          if not FTarget.FInitialBreakpointSeen then
          begin
            FTarget.FInitialBreakpointSeen := True;

            // Signal that FActualImageBase is set and we're ready for patching
            SetEvent(FTarget.FReadyEvent);

            // Hold the process here until configurationDone arrives.
            // This gives the DAP client time to send setBreakpoints
            // before the debuggee runs its code.
            WaitForSingleObject(FTarget.FConfigDoneEvent, INFINITE);

            if Terminated then
            begin
              ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
                DBG_CONTINUE);
              Break;
            end;

            ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
              DBG_CONTINUE);
            Continue;
          end;

          // Check if this is within our code
          if FTarget.IsOurCode(LExAddr) then
          begin
            // Capture thread context
            FillChar(LContext, SizeOf(LContext), 0);
            LContext.ContextFlags := CONTEXT_FULL;
            GetThreadContext(FTarget.FMainThreadHandle, LContext);

            // INT3 advances RIP past 0xCC — back up by 1
            Dec(LContext.Rip);
            SetThreadContext(FTarget.FMainThreadHandle, LContext);

            FTarget.FCapturedContext := LContext;
            FTarget.FStoppedReason := dsrBreakpoint;
            FTarget.FStoppedAddress := LContext.Rip;
            FTarget.FStoppedThreadId := LEvent.dwThreadId;

            // Signal DAP thread that we stopped
            SetEvent(FTarget.FStoppedEvent);

            // Block until DAP tells us what to do
            WaitForSingleObject(FTarget.FResumeEvent, INFINITE);

            if Terminated then
            begin
              ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
                DBG_CONTINUE);
              Break;
            end;

            // Apply any context modifications (trap flag, RIP changes)
            SetThreadContext(FTarget.FMainThreadHandle,
              FTarget.FCapturedContext);

            ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
              DBG_CONTINUE);
            Continue;
          end
          else
          begin
            // Not our breakpoint — let the process handle it
            LContinueStatus := DBG_EXCEPTION_NOT_HANDLED;
          end;
        end
        else if LExCode = EXCEPTION_SINGLE_STEP then
        begin
          // Re-patch breakpoint if we were stepping past one
          LRepatch := FTarget.FRepatchOffset;
          if LRepatch >= 0 then
          begin
            FTarget.WriteByte(
              FTarget.CodeOffsetToAddress(Cardinal(LRepatch)), INT3_OPCODE);
            FTarget.FlushCode(
              FTarget.CodeOffsetToAddress(Cardinal(LRepatch)), 1);
            FTarget.FRepatchOffset := -1;

            // This was an internal re-patch step (continue past breakpoint),
            // NOT a user-requested step — clear trap flag and resume silently
            FillChar(LContext, SizeOf(LContext), 0);
            LContext.ContextFlags := CONTEXT_FULL;
            GetThreadContext(FTarget.FMainThreadHandle, LContext);
            LContext.EFlags := LContext.EFlags and (not TRAP_FLAG);
            SetThreadContext(FTarget.FMainThreadHandle, LContext);

            ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
              DBG_CONTINUE);
            Continue;
          end;

          // User-requested single step (step over/in/out) — report to DAP
          FillChar(LContext, SizeOf(LContext), 0);
          LContext.ContextFlags := CONTEXT_FULL;
          GetThreadContext(FTarget.FMainThreadHandle, LContext);

          // Clear trap flag
          LContext.EFlags := LContext.EFlags and (not TRAP_FLAG);
          SetThreadContext(FTarget.FMainThreadHandle, LContext);

          FTarget.FCapturedContext := LContext;
          FTarget.FStoppedReason := dsrSingleStep;
          FTarget.FStoppedAddress := LContext.Rip;
          FTarget.FStoppedThreadId := LEvent.dwThreadId;

          // Signal DAP thread
          SetEvent(FTarget.FStoppedEvent);

          // Block until DAP tells us what to do
          WaitForSingleObject(FTarget.FResumeEvent, INFINITE);

          if Terminated then
          begin
            ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
              DBG_CONTINUE);
            Break;
          end;

          // Apply context
          SetThreadContext(FTarget.FMainThreadHandle,
            FTarget.FCapturedContext);

          ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
            DBG_CONTINUE);
          Continue;
        end
        else
        begin
          // Other exceptions — break into debugger if enabled, else pass through
          if FTarget.FBreakOnExceptions and FTarget.IsOurCode(LExAddr) then
          begin
            FillChar(LContext, SizeOf(LContext), 0);
            LContext.ContextFlags := CONTEXT_FULL;
            GetThreadContext(FTarget.FMainThreadHandle, LContext);

            FTarget.FCapturedContext := LContext;
            FTarget.FStoppedReason := dsrException;
            FTarget.FStoppedAddress := LExAddr;
            FTarget.FStoppedThreadId := LEvent.dwThreadId;
            FTarget.FExceptionCode := LExCode;

            SetEvent(FTarget.FStoppedEvent);
            WaitForSingleObject(FTarget.FResumeEvent, INFINITE);

            if Terminated then
            begin
              ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
                DBG_CONTINUE);
              Break;
            end;

            SetThreadContext(FTarget.FMainThreadHandle,
              FTarget.FCapturedContext);

            ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
              DBG_EXCEPTION_NOT_HANDLED);
            Continue;
          end
          else if LEvent.Exception.dwFirstChance = 1 then
            LContinueStatus := DBG_EXCEPTION_NOT_HANDLED;
        end;
      end;

      LOAD_DLL_DEBUG_EVENT:
      begin
        // Check if this is our target DLL (only in DLL debug mode)
        if FTarget.FIsAttachedToDll and (not FTarget.FDllFound) then
        begin
          if IsTargetDll(LEvent) then
          begin
            FTarget.FDllBaseAddress :=
              UInt64(LEvent.LoadDll.lpBaseOfDll);
            FTarget.FDllFound := True;

            // Signal the runtime so it can apply breakpoints
            FTarget.FStoppedReason := dsrDllLoad;
            FTarget.FStoppedAddress := 0;
            FTarget.FStoppedThreadId := LEvent.dwThreadId;

            SetEvent(FTarget.FStoppedEvent);

            // Block until runtime has applied breakpoints and tells us to go
            WaitForSingleObject(FTarget.FResumeEvent, INFINITE);

            if Terminated then
            begin
              if LEvent.LoadDll.hFile <> 0 then
                CloseHandle(LEvent.LoadDll.hFile);
              ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
                DBG_CONTINUE);
              Break;
            end;
          end;
        end;

        // Close the DLL file handle
        if LEvent.LoadDll.hFile <> 0 then
          CloseHandle(LEvent.LoadDll.hFile);
      end;

      EXIT_PROCESS_DEBUG_EVENT:
      begin
        FTarget.FExitCode := LEvent.ExitProcess.dwExitCode;
        FTarget.FStoppedReason := dsrProcessExit;
        FTarget.FStoppedAddress := 0;
        FTarget.FStarted := False;
        FTarget.FProcessExited := True;

        // Signal DAP thread that the process has exited
        SetEvent(FTarget.FStoppedEvent);

        ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
          DBG_CONTINUE);
        Break;
      end;
    end;

    ContinueDebugEvent(LEvent.dwProcessId, LEvent.dwThreadId,
      LContinueStatus);
  end;
end;

{ TMyrPEDebugTarget }
constructor TMyrPEDebugTarget.Create();
begin
  inherited Create();
  FExePath := '';
  FProcessHandle := 0;
  FMainThreadHandle := 0;
  FProcessId := 0;
  FMainThreadId := 0;
  FActualImageBase := 0;
  FTextSectionRVA := 0;
  FTextSectionSize := 0;
  FDataSectionRVA := 0;
  FStoppedEvent := 0;
  FResumeEvent := 0;
  FillChar(FCapturedContext, SizeOf(FCapturedContext), 0);
  FStoppedReason := dsrNone;
  FStoppedAddress := 0;
  FStoppedThreadId := 0;
  FStarted := False;
  FExitCode := 0;
  FProcessExited := False;
  FExceptionCode := 0;
  FInitialBreakpointSeen := False;
  FRepatchOffset := -1;
  FConfigDoneEvent := 0;
  FReadyEvent := 0;
  FLaunchDoneEvent := 0;
  FLaunchPath := '';
  FLaunchSucceeded := False;
  FDebugLoopThread := nil;
  FDllPath := '';
  FHostExePath := '';
  FIsAttachedToDll := False;
  FDllBaseAddress := 0;
  FDllFound := False;
end;

destructor TMyrPEDebugTarget.Destroy();
begin
  Stop();
  inherited Destroy();
end;

procedure TMyrPEDebugTarget.SetExePath(const APath: string);
begin
  FExePath := APath;
end;

procedure TMyrPEDebugTarget.SetTextSectionRVA(const ARVA: Cardinal);
begin
  FTextSectionRVA := ARVA;
end;

procedure TMyrPEDebugTarget.SetTextSectionSize(const ASize: Cardinal);
begin
  FTextSectionSize := ASize;
end;

procedure TMyrPEDebugTarget.SetDataSectionRVA(const ARVA: Cardinal);
begin
  FDataSectionRVA := ARVA;
end;

procedure TMyrPEDebugTarget.SetDllMode(const ADllPath: string;
  const AHostExePath: string);
begin
  FDllPath := ADllPath;
  FHostExePath := AHostExePath;
  FIsAttachedToDll := True;
  FDllBaseAddress := 0;
  FDllFound := False;
end;

function TMyrPEDebugTarget.Start(): Boolean;
var
  LLaunchPath: string;
begin
  Result := False;

  // In DLL mode, we launch the host EXE (not the DLL itself)
  if FIsAttachedToDll then
  begin
    if FHostExePath = '' then
    begin
      if Assigned(FErrors) then
        FErrors.Add(esFatal, 'DBG010', 'Host EXE path not set for DLL debugging');
      Exit;
    end;
    if not FileExists(FHostExePath) then
    begin
      if Assigned(FErrors) then
        FErrors.Add(esFatal, 'DBG011', 'Host EXE not found: %s', [FHostExePath]);
      Exit;
    end;
    LLaunchPath := FHostExePath;
  end
  else
  begin
    if FExePath = '' then
    begin
      if Assigned(FErrors) then
        FErrors.Add(esFatal, 'DBG010', 'EXE path not set before Start()');
      Exit;
    end;
    if not FileExists(FExePath) then
    begin
      if Assigned(FErrors) then
        FErrors.Add(esFatal, 'DBG011', 'EXE not found: %s', [FExePath]);
      Exit;
    end;
    LLaunchPath := FExePath;
  end;

  // Store launch path for the debug loop thread
  FLaunchPath := LLaunchPath;
  FLaunchSucceeded := False;

  // Create synchronization events
  FStoppedEvent := CreateEvent(nil, False, False, nil);     // Auto-reset
  FResumeEvent := CreateEvent(nil, False, False, nil);      // Auto-reset
  FConfigDoneEvent := CreateEvent(nil, True, False, nil);   // Manual-reset
  FReadyEvent := CreateEvent(nil, True, False, nil);        // Manual-reset
  FLaunchDoneEvent := CreateEvent(nil, True, False, nil);   // Manual-reset

  if (FStoppedEvent = 0) or (FResumeEvent = 0) or
     (FConfigDoneEvent = 0) or (FReadyEvent = 0) or
     (FLaunchDoneEvent = 0) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esFatal, 'DBG012', 'Failed to create synchronization events');
    Exit;
  end;

  FInitialBreakpointSeen := False;

  // Start the debug loop thread — it will call CreateProcessW
  // (Windows requires WaitForDebugEvent on the same thread as CreateProcessW)
  FDebugLoopThread := TMyrPEDebugLoopThread.Create(Self);
  FDebugLoopThread.Start();

  // Wait for the thread to finish launching the process
  WaitForSingleObject(FLaunchDoneEvent, INFINITE);

  if not FLaunchSucceeded then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esFatal, 'DBG013',
        'Debug loop failed to launch process: %s (path: %s)',
        [FLaunchError, FLaunchPath]);
    Exit;
  end;

  FStarted := True;
  Result := True;
end;

procedure TMyrPEDebugTarget.Stop();
begin
  FStarted := False;

  // Terminate the debug loop thread
  if FDebugLoopThread <> nil then
  begin
    FDebugLoopThread.Terminate();
    // Unblock the thread if it's waiting on FResumeEvent or FConfigDoneEvent
    if FConfigDoneEvent <> 0 then
      SetEvent(FConfigDoneEvent);
    if FReadyEvent <> 0 then
      SetEvent(FReadyEvent);
    if FLaunchDoneEvent <> 0 then
      SetEvent(FLaunchDoneEvent);
    if FResumeEvent <> 0 then
      SetEvent(FResumeEvent);
    FDebugLoopThread.WaitFor();
    FreeAndNil(FDebugLoopThread);
  end;

  // Terminate the debuggee process if still running
  if FProcessHandle <> 0 then
  begin
    TerminateProcess(FProcessHandle, 1);
    CloseHandle(FProcessHandle);
    FProcessHandle := 0;
  end;

  if FMainThreadHandle <> 0 then
  begin
    CloseHandle(FMainThreadHandle);
    FMainThreadHandle := 0;
  end;

  // Close events
  if FStoppedEvent <> 0 then
  begin
    CloseHandle(FStoppedEvent);
    FStoppedEvent := 0;
  end;
  if FResumeEvent <> 0 then
  begin
    CloseHandle(FResumeEvent);
    FResumeEvent := 0;
  end;
  if FConfigDoneEvent <> 0 then
  begin
    CloseHandle(FConfigDoneEvent);
    FConfigDoneEvent := 0;
  end;
  if FReadyEvent <> 0 then
  begin
    CloseHandle(FReadyEvent);
    FReadyEvent := 0;
  end;
  if FLaunchDoneEvent <> 0 then
  begin
    CloseHandle(FLaunchDoneEvent);
    FLaunchDoneEvent := 0;
  end;
end;

function TMyrPEDebugTarget.IsRunning(): Boolean;
begin
  Result := FStarted;
end;

function TMyrPEDebugTarget.WaitForStop(out AEvent: TMyrDebugStopEvent): Boolean;
begin
  // Block until the debug loop thread signals a stop
  Result := WaitForSingleObject(FStoppedEvent, INFINITE) = WAIT_OBJECT_0;
  if Result then
  begin
    AEvent.Reason := FStoppedReason;
    AEvent.Address := FStoppedAddress;
    if FStoppedAddress <> 0 then
      AEvent.CodeOffset := AddressToCodeOffset(FStoppedAddress)
    else
      AEvent.CodeOffset := 0;
    AEvent.ThreadId := FStoppedThreadId;
    AEvent.ExitCode := FExitCode;
    AEvent.ExceptionCode := FExceptionCode;
    if FStoppedReason = dsrException then
      AEvent.ExceptionMessage := Format('Exception 0x%x at 0x%x',
        [FExceptionCode, FStoppedAddress])
    else
      AEvent.ExceptionMessage := '';
  end;
end;

procedure TMyrPEDebugTarget.Resume();
begin
  // Signal the debug loop thread to ContinueDebugEvent
  SetEvent(FResumeEvent);
end;

procedure TMyrPEDebugTarget.SetTrapFlag();
begin
  // Set trap flag in captured context — applied when debug loop resumes
  FCapturedContext.EFlags := FCapturedContext.EFlags or TRAP_FLAG;
end;

procedure TMyrPEDebugTarget.ClearTrapFlag();
begin
  FCapturedContext.EFlags := FCapturedContext.EFlags and (not TRAP_FLAG);
end;

function TMyrPEDebugTarget.ReadByte(const AAddress: UInt64): Byte;
var
  LBytesRead: NativeUInt;
begin
  Result := 0;
  if FProcessExited then
    Exit;
  if not ReadProcessMemory(FProcessHandle, Pointer(AAddress),
    @Result, 1, LBytesRead) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, 'DBG020',
        'ReadProcessMemory failed at $%x: %s',
        [AAddress, SysErrorMessage(GetLastError())]);
  end;
end;

procedure TMyrPEDebugTarget.WriteByte(const AAddress: UInt64;
  const AValue: Byte);
var
  LBytesWritten: NativeUInt;
begin
  if FProcessExited then
    Exit;
  if not WriteProcessMemory(FProcessHandle, Pointer(AAddress),
    @AValue, 1, LBytesWritten) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, 'DBG021',
        'WriteProcessMemory failed at $%x: %s',
        [AAddress, SysErrorMessage(GetLastError())]);
  end;
end;

function TMyrPEDebugTarget.ReadUInt64(const AAddress: UInt64): UInt64;
var
  LBytesRead: NativeUInt;
begin
  Result := 0;
  if FProcessExited then
    Exit;
  if not ReadProcessMemory(FProcessHandle, Pointer(AAddress),
    @Result, 8, LBytesRead) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, 'DBG022',
        'ReadProcessMemory (UInt64) failed at $%x: %s',
        [AAddress, SysErrorMessage(GetLastError())]);
  end;
end;

procedure TMyrPEDebugTarget.FlushCode(const AAddress: UInt64;
  const ASize: Cardinal);
begin
  FlushInstructionCache(FProcessHandle, Pointer(AAddress), ASize);
end;

function TMyrPEDebugTarget.GetContext(): TMyrDebugContext;
begin
  Result := FCapturedContext;
end;

procedure TMyrPEDebugTarget.SetContext(const AContext: TMyrDebugContext);
begin
  FCapturedContext := AContext;
end;

function TMyrPEDebugTarget.CodeOffsetToAddress(const AOffset: Cardinal): UInt64;
var
  LBase: UInt64;
begin
  // In DLL mode, offsets are relative to DLL's .text section
  if FIsAttachedToDll then
    LBase := FDllBaseAddress
  else
    LBase := FActualImageBase;

  Result := LBase + UInt64(FTextSectionRVA) + UInt64(AOffset);
end;

function TMyrPEDebugTarget.AddressToCodeOffset(const AAddress: UInt64): Cardinal;
var
  LBase: UInt64;
  LTextStart: UInt64;
begin
  if FIsAttachedToDll then
    LBase := FDllBaseAddress
  else
    LBase := FActualImageBase;

  LTextStart := LBase + UInt64(FTextSectionRVA);

  // Guard against underflow: if address is below .text start, return sentinel
  if (AAddress = 0) or (AAddress < LTextStart) then
  begin
    Result := Cardinal($FFFFFFFF);
    Exit;
  end;

  Result := Cardinal(AAddress - LTextStart);
end;

function TMyrPEDebugTarget.DataOffsetToAddress(const AOffset: Cardinal): UInt64;
var
  LBase: UInt64;
begin
  if FIsAttachedToDll then
    LBase := FDllBaseAddress
  else
    LBase := FActualImageBase;

  Result := LBase + UInt64(FDataSectionRVA) + UInt64(AOffset);
end;

function TMyrPEDebugTarget.IsOurCode(const AAddress: UInt64): Boolean;
var
  LBase: UInt64;
  LTextStart: UInt64;
begin
  if FIsAttachedToDll then
  begin
    // Before DLL is loaded, nothing is "our code"
    if not FDllFound then
      Exit(False);
    LBase := FDllBaseAddress;
  end
  else
    LBase := FActualImageBase;

  LTextStart := LBase + UInt64(FTextSectionRVA);

  // If we know the .text size, use it for precise bounds
  if FTextSectionSize > 0 then
    Result := (AAddress >= LTextStart) and
              (AAddress < LTextStart + UInt64(FTextSectionSize))
  else
    // Without size info, check if address is above .text start
    // and within a reasonable range (16 MB)
    Result := (AAddress >= LTextStart) and
              (AAddress < LTextStart + $1000000);
end;

procedure TMyrPEDebugTarget.SetRepatchOffset(const AOffset: Integer);
begin
  FRepatchOffset := AOffset;
end;

function TMyrPEDebugTarget.GetRepatchOffset(): Integer;
begin
  Result := FRepatchOffset;
end;

procedure TMyrPEDebugTarget.SignalConfigDone();
begin
  // Release the process held at the initial breakpoint
  if FConfigDoneEvent <> 0 then
    SetEvent(FConfigDoneEvent);
end;

procedure TMyrPEDebugTarget.WaitUntilReady();
var
  LWaitMS: Integer;
begin
  // Poll until the debug loop thread has processed CREATE_PROCESS_DEBUG_EVENT
  // and set FActualImageBase, or timeout after 10 seconds
  LWaitMS := 0;
  while (FActualImageBase = 0) and (LWaitMS < 10000) do
  begin
    Sleep(10);
    Inc(LWaitMS, 10);
  end;
end;

procedure TMyrPEDebugTarget.UnblockWaitForStop();
begin
  // Signal FStoppedEvent so the stop watcher thread can wake up and exit
  if FStoppedEvent <> 0 then
    SetEvent(FStoppedEvent);
end;


{ TMyrBreakpointManager }
constructor TMyrBreakpointManager.Create();
begin
  inherited Create();
  FTarget := nil;
  FSourceMap := nil;
  FBreakpoints := TList<TMyrBreakpointInfo>.Create();
  FNextID := 1;
end;

destructor TMyrBreakpointManager.Destroy();
begin
  RemoveAll();
  FBreakpoints.Free();
  inherited Destroy();
end;

procedure TMyrBreakpointManager.SetTarget(const ATarget: TMyrDebugTarget);
begin
  FTarget := ATarget;
end;

procedure TMyrBreakpointManager.SetSourceMap(const ASourceMap: TMyrSourceMap);
begin
  FSourceMap := ASourceMap;
end;

function TMyrBreakpointManager.SetBreakpoint(const AFile: string;
  const ALine: Integer; const ACondition: string;
  const AHitCondition: Integer): Integer;
var
  LInfo: TMyrBreakpointInfo;
  LOffset: Cardinal;
begin
  Result := -1;

  if (FTarget = nil) or (FSourceMap = nil) then
    Exit;

  // Resolve source line to code offset
  LOffset := FSourceMap.SourceLineToOffset(AFile, ALine);
  if LOffset = Cardinal($FFFFFFFF) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esWarning, 'DBG010',
        'No code at %s:%d', [AFile, ALine]);
    Exit;
  end;

  // Create breakpoint record (don't read memory yet — FActualImageBase
  // may not be set during initial config phase; PatchBreakpoint reads
  // the original byte when ApplyAll runs)
  LInfo.ID := FNextID;
  Inc(FNextID);
  LInfo.SourceFile := AFile;
  LInfo.SourceLine := ALine;
  LInfo.CodeOffset := LOffset;
  LInfo.OriginalByte := 0;
  LInfo.IsTemporary := False;
  LInfo.IsEnabled := True;
  LInfo.IsPatched := False;
  LInfo.HitCount := 0;
  LInfo.Condition := ACondition;
  LInfo.HitCondition := AHitCondition;

  FBreakpoints.Add(LInfo);

  // Don't patch here — ApplyAll() handles patching at the right time:
  //   - Initial breakpoints: patched during ConfigurationDone (process is
  //     suspended at loader breakpoint, FActualImageBase is guaranteed set)
  //   - Runtime breakpoints: patched via ApplyAll after the stop is processed

  Result := LInfo.ID;
end;

function TMyrBreakpointManager.RemoveBreakpoint(const AID: Integer): Boolean;
var
  LI: Integer;
begin
  Result := False;
  for LI := 0 to FBreakpoints.Count - 1 do
  begin
    if FBreakpoints[LI].ID = AID then
    begin
      // Restore original byte if patched
      if FBreakpoints[LI].IsPatched then
        UnpatchBreakpoint(LI);
      FBreakpoints.Delete(LI);
      Result := True;
      Exit;
    end;
  end;
end;

function TMyrBreakpointManager.SetTempBreakpoint(const AOffset: Cardinal): Integer;
var
  LInfo: TMyrBreakpointInfo;
  LAddr: UInt64;
begin
  if FTarget = nil then
    Exit(-1);

  LAddr := FTarget.CodeOffsetToAddress(AOffset);

  LInfo.ID := FNextID;
  Inc(FNextID);
  LInfo.SourceFile := '';
  LInfo.SourceLine := 0;
  LInfo.CodeOffset := AOffset;
  LInfo.OriginalByte := FTarget.ReadByte(LAddr);
  LInfo.IsTemporary := True;
  LInfo.IsEnabled := True;
  LInfo.IsPatched := False;
  LInfo.HitCount := 0;
  LInfo.Condition := '';
  LInfo.HitCondition := 0;

  FBreakpoints.Add(LInfo);
  PatchBreakpoint(FBreakpoints.Count - 1);

  Result := LInfo.ID;
end;

procedure TMyrBreakpointManager.RemoveAllTemp();
var
  LI: Integer;
begin
  for LI := FBreakpoints.Count - 1 downto 0 do
  begin
    if FBreakpoints[LI].IsTemporary then
    begin
      if FBreakpoints[LI].IsPatched then
        UnpatchBreakpoint(LI);
      FBreakpoints.Delete(LI);
    end;
  end;
end;

procedure TMyrBreakpointManager.RemoveAll();
var
  LI: Integer;
begin
  for LI := FBreakpoints.Count - 1 downto 0 do
  begin
    if FBreakpoints[LI].IsPatched then
      UnpatchBreakpoint(LI);
  end;
  FBreakpoints.Clear();
end;

function TMyrBreakpointManager.IsOurBreakpoint(const AOffset: Cardinal): Boolean;
var
  LI: Integer;
begin
  Result := False;
  for LI := 0 to FBreakpoints.Count - 1 do
  begin
    if FBreakpoints[LI].IsEnabled and (FBreakpoints[LI].CodeOffset = AOffset) then
      Exit(True);
  end;
end;

function TMyrBreakpointManager.GetBreakpointAt(const AOffset: Cardinal;
  out AInfo: TMyrBreakpointInfo): Boolean;
var
  LI: Integer;
begin
  Result := False;
  for LI := 0 to FBreakpoints.Count - 1 do
  begin
    if FBreakpoints[LI].CodeOffset = AOffset then
    begin
      AInfo := FBreakpoints[LI];
      Result := True;
      Exit;
    end;
  end;
end;

function TMyrBreakpointManager.GetBreakpointByID(const AID: Integer;
  out AInfo: TMyrBreakpointInfo): Boolean;
var
  LI: Integer;
begin
  Result := False;
  for LI := 0 to FBreakpoints.Count - 1 do
  begin
    if FBreakpoints[LI].ID = AID then
    begin
      AInfo := FBreakpoints[LI];
      Result := True;
      Exit;
    end;
  end;
end;

function TMyrBreakpointManager.GetBreakpointCount(): Integer;
begin
  Result := FBreakpoints.Count;
end;

function TMyrBreakpointManager.GetBreakpoint(const AIndex: Integer): TMyrBreakpointInfo;
begin
  Result := FBreakpoints[AIndex];
end;

procedure TMyrBreakpointManager.ApplyAll();
var
  LI: Integer;
begin
  for LI := 0 to FBreakpoints.Count - 1 do
  begin
    if FBreakpoints[LI].IsEnabled and (not FBreakpoints[LI].IsPatched) then
      PatchBreakpoint(LI);
  end;
end;

procedure TMyrBreakpointManager.PatchBreakpoint(const AIndex: Integer);
var
  LInfo: TMyrBreakpointInfo;
  LAddr: UInt64;
begin
  LInfo := FBreakpoints[AIndex];
  if LInfo.IsPatched then
    Exit;

  LAddr := FTarget.CodeOffsetToAddress(LInfo.CodeOffset);

  // Save original byte and write INT3
  LInfo.OriginalByte := FTarget.ReadByte(LAddr);
  FTarget.WriteByte(LAddr, INT3_OPCODE);
  FTarget.FlushCode(LAddr, 1);
  LInfo.IsPatched := True;

  FBreakpoints[AIndex] := LInfo;
end;

procedure TMyrBreakpointManager.UnpatchBreakpoint(const AIndex: Integer);
var
  LInfo: TMyrBreakpointInfo;
  LAddr: UInt64;
begin
  LInfo := FBreakpoints[AIndex];
  if not LInfo.IsPatched then
    Exit;

  LAddr := FTarget.CodeOffsetToAddress(LInfo.CodeOffset);

  // Restore original byte
  FTarget.WriteByte(LAddr, LInfo.OriginalByte);
  FTarget.FlushCode(LAddr, 1);
  LInfo.IsPatched := False;

  FBreakpoints[AIndex] := LInfo;
end;

{ TMyrStackWalker }
function TMyrStackWalker.WalkStack(const ATarget: TMyrDebugTarget;
  const ASourceMap: TMyrSourceMap;
  const AContext: TMyrDebugContext): TArray<TMyrDebugStackFrame>;
var
  LFrame: TMyrDebugStackFrame;
  LFrameID: Integer;
  LRIP: UInt64;
  LRBP: UInt64;
  LOffset: Cardinal;
  LEntry: TMyrSourceMapEntry;
  LFound: Boolean;
begin
  SetLength(Result, 0);
  LFrameID := 0;
  LRIP := AContext.Rip;
  LRBP := AContext.Rbp;

  while ATarget.IsOurCode(LRIP) do
  begin
    LOffset := ATarget.AddressToCodeOffset(LRIP);
    LFound := ASourceMap.OffsetToEntry(LOffset, LEntry);

    LFrame.FrameID := LFrameID;
    LFrame.CodeOffset := LOffset;
    LFrame.RBP := LRBP;
    LFrame.RIP := LRIP;

    if LFound then
    begin
      LFrame.FunctionName := ASourceMap.GetFunctionAtOffset(LOffset);
      LFrame.SourceFile := ASourceMap.GetSourceFile(LEntry.SourceFileIndex);
      LFrame.SourceLine := LEntry.SourceLine;
      LFrame.SourceColumn := LEntry.SourceColumn;
    end
    else
    begin
      LFrame.FunctionName := Format('0x%x', [LRIP]);
      LFrame.SourceFile := '';
      LFrame.SourceLine := 0;
      LFrame.SourceColumn := 0;
    end;

    Result := Result + [LFrame];
    Inc(LFrameID);

    // Walk up one frame via RBP chain
    // Standard x64 frame: [RBP] = saved RBP, [RBP+8] = return address
    if LRBP = 0 then
      Break;

    try
      LRIP := ATarget.ReadUInt64(LRBP + 8);  // Saved return address
      LRBP := ATarget.ReadUInt64(LRBP);       // Saved RBP
    except
      // Memory read failed — end of valid stack
      Break;
    end;

    // Safety: stop if we've gone too deep or RBP is zero/invalid
    if (LRBP = 0) or (LFrameID > 256) then
      Break;
  end;
end;

{ TMyrDebugRuntime }
constructor TMyrDebugRuntime.Create();
begin
  inherited Create();
  FTarget := nil;
  FSourceMap := nil;
  FBreakpoints := TMyrBreakpointManager.Create();
  FStackWalker := TMyrStackWalker.Create();
  FillChar(FLastStopEvent, SizeOf(FLastStopEvent), 0);
end;

destructor TMyrDebugRuntime.Destroy();
begin
  FStackWalker.Free();
  FBreakpoints.Free();
  inherited Destroy();
end;

procedure TMyrDebugRuntime.SetTarget(const ATarget: TMyrDebugTarget);
begin
  FTarget := ATarget;
  FBreakpoints.SetTarget(ATarget);
end;

procedure TMyrDebugRuntime.SetSourceMap(const ASourceMap: TMyrSourceMap);
var
  LBreakpoints: TArray<TMyrSourceMapBreakpoint>;
  LI: Integer;
  LFile: string;
begin
  FSourceMap := ASourceMap;
  FBreakpoints.SetSourceMap(ASourceMap);

  // Auto-apply embedded @breakpoint directives
  if ASourceMap <> nil then
  begin
    LBreakpoints := ASourceMap.GetBreakpoints();
    for LI := 0 to Length(LBreakpoints) - 1 do
    begin
      LFile := ASourceMap.GetSourceFile(LBreakpoints[LI].SourceFileIndex);
      if not LFile.IsEmpty() then
        FBreakpoints.SetBreakpoint(LFile, LBreakpoints[LI].SourceLine);
    end;
  end;
end;

function TMyrDebugRuntime.SetBreakpoint(const AFile: string;
  const ALine: Integer; const ACondition: string;
  const AHitCondition: Integer): Integer;
begin
  Result := FBreakpoints.SetBreakpoint(AFile, ALine, ACondition, AHitCondition);
end;

function TMyrDebugRuntime.RemoveBreakpoint(const AID: Integer): Boolean;
begin
  Result := FBreakpoints.RemoveBreakpoint(AID);
end;

procedure TMyrDebugRuntime.ConfigurationDone();
begin
  // Wait until the debug loop thread has reached the initial breakpoint
  // (FActualImageBase is set, process memory is accessible)
  if FTarget <> nil then
    FTarget.WaitUntilReady();

  // Apply all breakpoints while the process is still held at the loader breakpoint
  FBreakpoints.ApplyAll();

  // Activate VEH interception — breakpoints are patched, safe to intercept now
  if FTarget <> nil then
    FTarget.SetDebugActive(True);

  // Signal the target to release the process
  if FTarget <> nil then
    FTarget.SignalConfigDone();
end;

function TMyrDebugRuntime.Continue(): Boolean;
var
  LBPInfo: TMyrBreakpointInfo;
  LOffset: Cardinal;
  LContext: TMyrDebugContext;
begin
  Result := False;
  if FTarget = nil then
    Exit;

  LContext := FTarget.GetContext();

  // Guard: if no valid stop context yet (Rip=0), just resume without
  // trying to step past a breakpoint — there's nothing to step past
  if LContext.Rip = 0 then
  begin
    FTarget.Resume();
    Result := True;
    Exit;
  end;

  LOffset := FTarget.AddressToCodeOffset(LContext.Rip);

  // If we're stopped at a breakpoint, we need to step past it first:
  // 1. Restore original byte
  // 2. Set trap flag for single-step
  // 3. Tell target to re-patch after the single-step
  if FBreakpoints.GetBreakpointAt(LOffset, LBPInfo) and LBPInfo.IsPatched then
  begin
    // Restore original byte so we can execute the real instruction
    FTarget.WriteByte(FTarget.CodeOffsetToAddress(LOffset), LBPInfo.OriginalByte);
    FTarget.FlushCode(FTarget.CodeOffsetToAddress(LOffset), 1);

    // Set trap flag — after executing one instruction, the single-step
    // exception fires and the VEH handler re-patches the INT3
    FTarget.SetTrapFlag();

    // Tell the target to re-patch at this offset after single-step
    FTarget.SetRepatchOffset(Integer(LOffset));
  end;

  // Resume execution
  FTarget.Resume();
  Result := True;
end;

function TMyrDebugRuntime.StepOver(): Boolean;
var
  LContext: TMyrDebugContext;
  LCurrentOffset: Cardinal;
  LNextOffset: Cardinal;
begin
  Result := False;
  if (FTarget = nil) or (FSourceMap = nil) then
    Exit;

  LContext := FTarget.GetContext();
  LCurrentOffset := FTarget.AddressToCodeOffset(LContext.Rip);

  // Find the next source line offset within the same function
  LNextOffset := FSourceMap.GetNextLineOffset(LCurrentOffset);
  if LNextOffset = Cardinal($FFFFFFFF) then
  begin
    // No next line in this function — do a step-out instead
    Result := StepOut();
    Exit;
  end;

  // Set a temporary breakpoint at the next line
  FBreakpoints.SetTempBreakpoint(LNextOffset);

  // Continue execution (handles stepping past current breakpoint)
  Result := Continue();
end;

function TMyrDebugRuntime.StepIn(): Boolean;
var
  LContext: TMyrDebugContext;
  LAddr: UInt64;
  LOpcode: Byte;
  LRel32: Int32;
  LCallTarget: UInt64;
  LTargetOffset: Cardinal;
begin
  Result := False;
  if (FTarget = nil) or (FSourceMap = nil) then
    Exit;

  LContext := FTarget.GetContext();
  LAddr := LContext.Rip;

  // Check if current instruction is a CALL rel32 (opcode E8)
  // This is the most common call form in Myrissa-generated code
  LOpcode := FTarget.ReadByte(LAddr);
  if LOpcode = $E8 then
  begin
    // Read the 32-bit relative displacement
    LRel32 := Int32(FTarget.ReadByte(LAddr + 1)) or
              (Int32(FTarget.ReadByte(LAddr + 2)) shl 8) or
              (Int32(FTarget.ReadByte(LAddr + 3)) shl 16) or
              (Int32(FTarget.ReadByte(LAddr + 4)) shl 24);

    // CALL rel32: target = RIP + 5 + rel32
    LCallTarget := LAddr + 5 + UInt64(LRel32);

    // Only step into if the target is within our code
    if FTarget.IsOurCode(LCallTarget) then
    begin
      LTargetOffset := FTarget.AddressToCodeOffset(LCallTarget);
      FBreakpoints.SetTempBreakpoint(LTargetOffset);
      Result := Continue();
      Exit;
    end;
  end;

  // Not a CALL we can decode, or target is external — fall back to StepOver
  Result := StepOver();
end;

function TMyrDebugRuntime.StepOut(): Boolean;
var
  LContext: TMyrDebugContext;
  LReturnAddr: UInt64;
  LReturnOffset: Cardinal;
begin
  Result := False;
  if FTarget = nil then
    Exit;

  LContext := FTarget.GetContext();

  // Read return address from [RBP+8] (standard x64 frame)
  if LContext.Rbp = 0 then
    Exit;  // No valid frame pointer

  try
    LReturnAddr := FTarget.ReadUInt64(LContext.Rbp + 8);
  except
    Exit;  // Memory read failed
  end;

  // Only set breakpoint if return address is in our code
  if not FTarget.IsOurCode(LReturnAddr) then
  begin
    // Returning to non-Myrissa code — just continue
    Result := Continue();
    Exit;
  end;

  LReturnOffset := FTarget.AddressToCodeOffset(LReturnAddr);
  FBreakpoints.SetTempBreakpoint(LReturnOffset);
  Result := Continue();
end;

function TMyrDebugRuntime.WaitForStop(): Boolean;
var
  LEvent: TMyrDebugStopEvent;
  LBPInfo: TMyrBreakpointInfo;
  LI: Integer;
  LFound: Boolean;
  LShouldBreak: Boolean;
  LCondVar: TMyrDebugVariable;
begin
  Result := False;
  if FTarget = nil then
    Exit;

  while True do
  begin
    if not FTarget.WaitForStop(LEvent) then
      Exit;

    // DLL load event: apply breakpoints and resume transparently
    if LEvent.Reason = dsrDllLoad then
    begin
      FBreakpoints.ApplyAll();
      FTarget.Resume();
      Continue;  // Loop back to wait for the next stop
    end;

    FLastStopEvent := LEvent;

    // If we stopped at a breakpoint, update hit count and check conditions
    if LEvent.Reason = dsrBreakpoint then
    begin
      LFound := False;
      LShouldBreak := True;

      for LI := 0 to FBreakpoints.GetBreakpointCount() - 1 do
      begin
        if FBreakpoints.GetBreakpoint(LI).CodeOffset = LEvent.CodeOffset then
        begin
          LBPInfo := FBreakpoints.GetBreakpoint(LI);
          Inc(LBPInfo.HitCount);
          FBreakpoints.FBreakpoints[LI] := LBPInfo;
          LFound := True;

          // Check hit condition (break only when HitCount >= threshold)
          if (LBPInfo.HitCondition > 0) and
             (LBPInfo.HitCount < LBPInfo.HitCondition) then
            LShouldBreak := False;

          // Check expression condition (evaluate variable, skip if falsy)
          if LShouldBreak and (LBPInfo.Condition <> '') then
          begin
            LCondVar := Evaluate(LBPInfo.Condition);
            if (LCondVar.VarValue = '') or
               (LCondVar.VarValue = '0') or
               SameText(LCondVar.VarValue, 'false') then
              LShouldBreak := False;
          end;

          Break;
        end;
      end;

      // Condition not met — silently resume and wait for next stop
      if LFound and (not LShouldBreak) then
      begin
        FBreakpoints.RemoveAllTemp();
        Self.Continue();
        Continue;  // Loop back to WaitForStop
      end;
    end;

    // All conditions met (or not a conditional breakpoint) — stop here
    Break;
  end;

  // Remove temporary breakpoints (used by stepping)
  FBreakpoints.RemoveAllTemp();

  Result := True;
end;

function TMyrDebugRuntime.GetCallStack(): TArray<TMyrDebugStackFrame>;
var
  LContext: TMyrDebugContext;
begin
  if (FTarget = nil) or (FSourceMap = nil) then
  begin
    SetLength(Result, 0);
    Exit;
  end;

  LContext := FTarget.GetContext();
  Result := FStackWalker.WalkStack(FTarget, FSourceMap, LContext);
end;

function TMyrDebugRuntime.GetLastStopEvent(): TMyrDebugStopEvent;
begin
  Result := FLastStopEvent;
end;

function TMyrDebugRuntime.GetVariables(): TArray<TMyrDebugVariable>;
var
  LFuncIndex: Integer;
  LVars: TArray<TMyrVariableLocation>;
  LI: Integer;
  LContext: TMyrDebugContext;
  LAddress: UInt64;
  LBytes: TBytes;
  LSize: Integer;
  LVar: TMyrVariableLocation;
  LResult: TMyrDebugVariable;
  LResultList: TList<TMyrDebugVariable>;
begin
  Result := nil;
  if (FTarget = nil) or (FSourceMap = nil) then
    Exit;

  // Find which function we stopped in
  LFuncIndex := FSourceMap.GetFunctionIndexAtOffset(FLastStopEvent.CodeOffset);
  if LFuncIndex < 0 then
    Exit;

  // Get variables declared in this function
  LVars := FSourceMap.GetVariablesForFunction(LFuncIndex);
  if Length(LVars) = 0 then
    Exit;

  // Capture thread context for RBP
  LContext := FTarget.GetContext();

  LResultList := TList<TMyrDebugVariable>.Create();
  try
    for LI := 0 to High(LVars) do
    begin
      LVar := LVars[LI];
      LResult.VarName := LVar.VarName;
      LResult.IsParam := LVar.IsParam;

      // Determine byte size from type
      case LVar.VarType of
        cvtInt8, cvtUInt8:   LSize := 1;
        cvtInt16, cvtUInt16: LSize := 2;
        cvtInt32, cvtUInt32, cvtFloat32: LSize := 4;
        cvtInt64, cvtUInt64, cvtFloat64, cvtPointer: LSize := 8;
      else
        LSize := 8;
      end;

      // Type name string for DAP
      case LVar.VarType of
        cvtVoid:    LResult.VarType := 'void';
        cvtInt8:    LResult.VarType := 'i8';
        cvtInt16:   LResult.VarType := 'i16';
        cvtInt32:   LResult.VarType := 'i32';
        cvtInt64:   LResult.VarType := 'i64';
        cvtUInt8:   LResult.VarType := 'u8';
        cvtUInt16:  LResult.VarType := 'u16';
        cvtUInt32:  LResult.VarType := 'u32';
        cvtUInt64:  LResult.VarType := 'u64';
        cvtFloat32: LResult.VarType := 'f32';
        cvtFloat64: LResult.VarType := 'f64';
        cvtPointer: LResult.VarType := 'ptr';
      else
        LResult.VarType := 'unknown';
      end;

      // Read value from memory
      LResult.VarValue := '???';
      if LVar.IsGlobal then
        LAddress := FTarget.DataOffsetToAddress(Cardinal(LVar.StackOffset))
      else if LVar.LocationKind = vlkStack then
        LAddress := UInt64(Int64(LContext.Rbp) + LVar.StackOffset)
      else
        LAddress := 0;

      if LAddress <> 0 then
      begin
        try
          LBytes := FTarget.ReadBytes(LAddress, Cardinal(LSize));
          if Length(LBytes) = LSize then
          begin
            case LVar.VarType of
              cvtInt8:
                LResult.VarValue := IntToStr(ShortInt(LBytes[0]));
              cvtUInt8:
                LResult.VarValue := IntToStr(LBytes[0]);
              cvtInt16:
                LResult.VarValue := IntToStr(SmallInt(PWord(@LBytes[0])^));
              cvtUInt16:
                LResult.VarValue := IntToStr(PWord(@LBytes[0])^);
              cvtInt32:
                LResult.VarValue := IntToStr(PInteger(@LBytes[0])^);
              cvtUInt32:
                LResult.VarValue := IntToStr(PCardinal(@LBytes[0])^);
              cvtInt64:
                LResult.VarValue := IntToStr(PInt64(@LBytes[0])^);
              cvtUInt64:
                LResult.VarValue := UIntToStr(PUInt64(@LBytes[0])^);
              cvtFloat32:
                LResult.VarValue := FormatFloat('0.######', PSingle(@LBytes[0])^);
              cvtFloat64:
                LResult.VarValue := FormatFloat('0.##############', PDouble(@LBytes[0])^);
              cvtPointer:
                LResult.VarValue := Format('0x%x', [PUInt64(@LBytes[0])^]);
            else
              LResult.VarValue := Format('0x%x', [PUInt64(@LBytes[0])^]);
            end;
          end;
        except
          // ReadBytes failed (invalid address, process gone, etc.)
          LResult.VarValue := '<unreadable>';
        end;
      end;

      LResultList.Add(LResult);
    end;

    Result := LResultList.ToArray();
  finally
    LResultList.Free();
  end;
end;

function TMyrDebugRuntime.Evaluate(const AExpression: string): TMyrDebugVariable;
var
  LVars: TArray<TMyrDebugVariable>;
  LI: Integer;
  LExpr: string;
begin
  // Default: not found
  Result.VarName := AExpression;
  Result.VarValue := '';
  Result.VarType := '';
  Result.IsParam := False;

  LExpr := Trim(AExpression);
  if LExpr = '' then
    Exit;

  // Get all variables for the current frame, then filter by name
  LVars := GetVariables();
  for LI := 0 to High(LVars) do
  begin
    if SameText(LVars[LI].VarName, LExpr) then
    begin
      Result := LVars[LI];
      Exit;
    end;
  end;
end;

function TMyrDebugRuntime.GetBreakpoints(): TMyrBreakpointManager;
begin
  Result := FBreakpoints;
end;

function TMyrDebugRuntime.GetTarget(): TMyrDebugTarget;
begin
  Result := FTarget;
end;

function TMyrDebugRuntime.GetSourceMap(): TMyrSourceMap;
begin
  Result := FSourceMap;
end;


{ TMyrDAPServer }
constructor TMyrDAPServer.Create();
begin
  inherited Create();
  FRuntime := nil;
  FSourceMap := nil;
  FPort := 0;
  FState := dsIdle;
  FSeq := 1;
  FListenSocket := INVALID_SOCKET;
  FClientSocket := INVALID_SOCKET;
  FWSAInitialized := False;
  FSourceRoot := '';
  FProgram := '';
  FStopOnEntry := False;
  FVerboseLogging := False;
end;

destructor TMyrDAPServer.Destroy();
begin
  StopServer();
  inherited Destroy();
end;

procedure TMyrDAPServer.SetRuntime(const ARuntime: TMyrDebugRuntime);
begin
  FRuntime := ARuntime;
end;

procedure TMyrDAPServer.SetSourceMap(const ASourceMap: TMyrSourceMap);
begin
  FSourceMap := ASourceMap;
end;

function TMyrDAPServer.GetPort(): Integer;
begin
  Result := FPort;
end;

function TMyrDAPServer.GetState(): TMyrDAPState;
begin
  Result := FState;
end;

function TMyrDAPServer.StartListening(const APort: Integer): Boolean;
var
  LAddr: TSockAddrIn;
  LOptVal: Integer;
begin
  Result := False;
  FPort := APort;

  // Initialize WinSock
  if WSAStartup($0202, FWSAData) <> 0 then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esFatal, 'DAP001', 'WSAStartup failed');
    Exit;
  end;
  FWSAInitialized := True;

  // Create TCP socket
  FListenSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FListenSocket = INVALID_SOCKET then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esFatal, 'DAP002', 'Failed to create socket');
    Exit;
  end;

  // Allow port reuse
  LOptVal := 1;
  setsockopt(FListenSocket, SOL_SOCKET, SO_REUSEADDR,
    PAnsiChar(@LOptVal), SizeOf(LOptVal));

  // Bind to localhost
  FillChar(LAddr, SizeOf(LAddr), 0);
  LAddr.sin_family := AF_INET;
  LAddr.sin_addr.S_addr := inet_addr('127.0.0.1');
  LAddr.sin_port := htons(Word(APort));

  if bind(FListenSocket, TSockAddr(LAddr), SizeOf(LAddr)) = SOCKET_ERROR then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esFatal, 'DAP003', 'Failed to bind to port %d', [APort]);
    Exit;
  end;

  // Listen (backlog of 1 — only one client at a time)
  if listen(FListenSocket, 1) = SOCKET_ERROR then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esFatal, 'DAP004', 'Failed to listen on port %d', [APort]);
    Exit;
  end;

  FState := dsListening;
  Result := True;
end;

function TMyrDAPServer.WaitForConnection(): Boolean;
begin
  Result := False;
  if FState <> dsListening then
    Exit;

  // Blocking accept — waits until VS Code connects
  FClientSocket := accept(FListenSocket, nil, nil);
  if FClientSocket = INVALID_SOCKET then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esFatal, 'DAP005', 'Accept failed');
    Exit;
  end;

  FState := dsConnected;
  Result := True;
end;

procedure TMyrDAPServer.StopServer();
begin
  if FClientSocket <> INVALID_SOCKET then
  begin
    closesocket(FClientSocket);
    FClientSocket := INVALID_SOCKET;
  end;
  if FListenSocket <> INVALID_SOCKET then
  begin
    closesocket(FListenSocket);
    FListenSocket := INVALID_SOCKET;
  end;
  if FWSAInitialized then
  begin
    WSACleanup();
    FWSAInitialized := False;
  end;
  FState := dsIdle;
end;

function TMyrDAPServer.ReadMessage(): TJSON;
var
  LBuf: AnsiChar;
  LHeader: AnsiString;
  LContentLength: Integer;
  LBody: TBytes;
  LBodyStr: string;
  LRead: Integer;
  LTotal: Integer;
  LRecv: Integer;
begin
  Result := nil;
  LContentLength := 0;

  // Read headers line by line until empty line (\r\n\r\n)
  LHeader := '';
  while True do
  begin
    LRecv := recv(FClientSocket, LBuf, 1, 0);
    if LRecv <= 0 then
      Exit;  // Connection closed or error

    LHeader := LHeader + LBuf;

    // Check for end of headers
    if (Length(LHeader) >= 4) and
       (LHeader[Length(LHeader) - 3] = #13) and
       (LHeader[Length(LHeader) - 2] = #10) and
       (LHeader[Length(LHeader) - 1] = #13) and
       (LHeader[Length(LHeader)] = #10) then
      Break;
  end;

  // Parse Content-Length from headers
  LRead := Pos('Content-Length:', string(LHeader));
  if LRead > 0 then
  begin
    LBodyStr := Trim(Copy(string(LHeader), LRead + 15,
      Pos(#13, string(LHeader), LRead + 15) - LRead - 15));
    LContentLength := StrToIntDef(LBodyStr, 0);
  end;

  if LContentLength <= 0 then
    Exit;

  // Read exactly LContentLength bytes of body
  SetLength(LBody, LContentLength);
  LTotal := 0;
  while LTotal < LContentLength do
  begin
    LRecv := recv(FClientSocket, LBody[LTotal],
      LContentLength - LTotal, 0);
    if LRecv <= 0 then
      Exit;
    Inc(LTotal, LRecv);
  end;

  // Parse JSON
  LBodyStr := TEncoding.UTF8.GetString(LBody);
  try
    Result := TJSON.FromString(LBodyStr);
  except
    Result := nil;
  end;
end;

procedure TMyrDAPServer.SendMessage(const AMsg: TJSON);
var
  LBody: TBytes;
  LHeader: AnsiString;
begin
  LBody := TEncoding.UTF8.GetBytes(AMsg.ToString());
  LHeader := AnsiString(Format('Content-Length: %d'#13#10#13#10, [Length(LBody)]));

  send(FClientSocket, LHeader[1], Length(LHeader), 0);
  send(FClientSocket, LBody[0], Length(LBody), 0);
end;

procedure TMyrDAPServer.SendResponse(const ARequestSeq: Integer;
  const ACommand: string; const ASuccess: Boolean;
  const ABody: TJSON; const AMessage: string);
var
  LMsg: TJSON;
begin
  LMsg := TJSON.Create();
  try
    LMsg.Add('seq', FSeq);
    Inc(FSeq);
    LMsg.Add('type', 'response');
    LMsg.Add('request_seq', ARequestSeq);
    LMsg.Add('command', ACommand);
    LMsg.Add('success', ASuccess);

    if Assigned(ABody) and (not ABody.IsNull()) then
      LMsg.Add('body', ABody)
    else
      LMsg.BeginObject('body').EndObject();

    if AMessage <> '' then
      LMsg.Add('message', AMessage);

    SendMessage(LMsg);
  finally
    LMsg.Free();
    ABody.Free();
  end;
end;

procedure TMyrDAPServer.SendEvent(const AEventName: string;
  const ABody: TJSON);
var
  LMsg: TJSON;
begin
  LMsg := TJSON.Create();
  try
    LMsg.Add('seq', FSeq);
    Inc(FSeq);
    LMsg.Add('type', 'event');
    LMsg.Add('event', AEventName);

    if Assigned(ABody) and (not ABody.IsNull()) then
      LMsg.Add('body', ABody)
    else
      LMsg.BeginObject('body').EndObject();

    SendMessage(LMsg);
  finally
    LMsg.Free();
    ABody.Free();
  end;
end;

procedure TMyrDAPServer.RunMessageLoop();
var
  LMsg: TJSON;
  LCommand: string;
  LSeq: Integer;
  LSavedRaiseOnError: Boolean;
begin
  // Suppress exception raising in the message loop thread —
  // errors are logged but must not kill the background thread
  LSavedRaiseOnError := False;
  if Assigned(FErrors) then
  begin
    LSavedRaiseOnError := FErrors.RaiseOnError;
    FErrors.RaiseOnError := False;
  end;

  try
  while FState <> dsTerminated do
  begin
    Status(FVerboseLogging, '[DAP-S] waiting for message...', []);
    LMsg := ReadMessage();
    if LMsg.IsNull() then
    begin
      Status(FVerboseLogging, '[DAP-S] ReadMessage returned null - connection closed', []);
      FState := dsTerminated;
      LMsg.Free();
      Break;
    end;

    try
      try
        LCommand := LMsg.Get('command').AsString('');
        Status(FVerboseLogging, '[DAP-S] << %s (seq %d)', [LCommand, LMsg.Get('seq').AsInt32()]);
        DispatchRequest(LMsg);
        Status(FVerboseLogging, '[DAP-S] >> %s handled', [LCommand]);
      except
        on E: Exception do
        begin
          // Extract request info for error response
          LCommand := LMsg.Get('command').AsString();
          LSeq := LMsg.Get('seq').AsInt32();

          // Send DAP error response so the client doesn't time out
          if (LCommand <> '') and (LSeq > 0) then
            SendResponse(LSeq, LCommand, False, nil,
              Format('Internal error: %s', [E.Message]));

          Status('[DAP-S] EXCEPTION in [%s]: %s', [LCommand, E.Message]);

          // Log to FErrors for server-side diagnostics
          if Assigned(FErrors) then
            FErrors.Add(esFatal, 'DAP900',
              'Exception in DAP handler [%s]: %s', [LCommand, E.Message]);
        end;
      end;
    finally
      LMsg.Free();
    end;
  end;

  finally
    // Restore raise-on-error state
    if Assigned(FErrors) then
      FErrors.RaiseOnError := LSavedRaiseOnError;
  end;
end;

procedure TMyrDAPServer.DispatchRequest(const AMsg: TJSON);
var
  LCommand: string;
  LSeq: Integer;
  LArgs: TJSON;
  LType: string;
begin
  LType := AMsg.Get('type').AsString();
  if LType <> 'request' then
    Exit;

  LCommand := AMsg.Get('command').AsString();
  LSeq := AMsg.Get('seq').AsInt32();
  LArgs := AMsg.Get('arguments');

  if LCommand = 'initialize' then
    HandleInitialize(LSeq, LArgs)
  else if LCommand = 'launch' then
    HandleLaunch(LSeq, LArgs)
  else if LCommand = 'setBreakpoints' then
    HandleSetBreakpoints(LSeq, LArgs)
  else if LCommand = 'setExceptionBreakpoints' then
    HandleSetExceptionBreakpoints(LSeq, LArgs)
  else if LCommand = 'configurationDone' then
    HandleConfigurationDone(LSeq)
  else if LCommand = 'threads' then
    HandleThreads(LSeq)
  else if LCommand = 'stackTrace' then
    HandleStackTrace(LSeq, LArgs)

  else if LCommand = 'scopes' then
    HandleScopes(LSeq, LArgs)
  else if LCommand = 'variables' then
    HandleVariables(LSeq, LArgs)
  else if LCommand = 'continue' then
    HandleContinue(LSeq)
  else if LCommand = 'next' then
    HandleNext(LSeq)
  else if LCommand = 'stepIn' then
    HandleStepIn(LSeq)
  else if LCommand = 'stepOut' then
    HandleStepOut(LSeq)
  else if LCommand = 'pause' then
    HandlePause(LSeq)
  else if LCommand = 'evaluate' then
    HandleEvaluate(LSeq, LArgs)
  else if LCommand = 'disconnect' then
    HandleDisconnect(LSeq)
  else
    // Unknown command — send error response
    SendResponse(LSeq, LCommand, False, nil, 'Unknown command: ' + LCommand);
end;

procedure TMyrDAPServer.HandleInitialize(const ASeq: Integer;
  const AArgs: TJSON);
var
  LBody: TJSON;
begin
  // Report capabilities
  LBody := TJSON.Create()
    .Add('supportsConfigurationDoneRequest', True)
    .Add('supportsFunctionBreakpoints', False)
    .Add('supportsConditionalBreakpoints', True)
    .Add('supportsHitConditionalBreakpoints', True)
    .Add('supportsEvaluateForHovers', True)
    .Add('supportsStepBack', False)
    .Add('supportsSetVariable', False)
    .Add('supportsRestartFrame', False)
    .Add('supportsModulesRequest', False)
    .Add('supportsExceptionInfoRequest', False)
    .BeginArray('exceptionBreakpointFilters')
      .BeginObject()
        .Add('filter', 'all')
        .Add('label', 'All Exceptions')
        .Add('default', False)
      .EndObject()
    .EndArray();

  SendResponse(ASeq, 'initialize', True, LBody);

  // Send initialized event (tells client we're ready for breakpoint config)
  SendEvent('initialized');
  FState := dsInitialized;
end;

procedure TMyrDAPServer.HandleLaunch(const ASeq: Integer;
  const AArgs: TJSON);
begin
  // Extract launch configuration fields
  if not AArgs.IsNull() then
  begin
    FSourceRoot := AArgs.Get('sourceRoot').AsString();
    FProgram := AArgs.Get('program').AsString();
    FStopOnEntry := AArgs.Get('stopOnEntry').AsBoolean();
  end;

  FState := dsConfiguring;
  SendResponse(ASeq, 'launch', True);
end;

procedure TMyrDAPServer.HandleSetBreakpoints(const ASeq: Integer;
  const AArgs: TJSON);
var
  LSource: TJSON;
  LSourcePath: string;
  LBreakpointsArr: TJSON;
  LBody: TJSON;
  LBPObj: TJSON;
  LLine: Integer;
  LID: Integer;
  LI: Integer;
  LCondition: string;
  LHitCondition: Integer;
begin
  LBody := TJSON.Create()
    .BeginArray('breakpoints');

  if not AArgs.IsNull() then
  begin
    LSource := AArgs.Get('source');
    if not LSource.IsNull() then
      LSourcePath := LSource.Get('path').AsString()
    else
      LSourcePath := '';

    LBreakpointsArr := AArgs.Get('breakpoints');
    if not LBreakpointsArr.IsNull() then
    begin
      for LI := 0 to LBreakpointsArr.Count() - 1 do
      begin
        LBPObj := LBreakpointsArr.Items()[LI];
        LLine := LBPObj.Get('line').AsInt32();
        LCondition := LBPObj.Get('condition').AsString();
        LHitCondition := StrToIntDef(
          LBPObj.Get('hitCondition').AsString(), 0);

        LID := FRuntime.SetBreakpoint(LSourcePath, LLine,
          LCondition, LHitCondition);

        LBody
          .BeginObject()
            .Add('verified', LID >= 0)
            .Add('line', LLine);
        if LID >= 0 then
          LBody.Add('id', LID);
        LBody.EndObject();
      end;
    end;
  end;

  LBody.EndArray();
  SendResponse(ASeq, 'setBreakpoints', True, LBody);
end;

procedure TMyrDAPServer.HandleSetExceptionBreakpoints(const ASeq: Integer;
  const AArgs: TJSON);
var
  LFilters: TJSON;
  LI: Integer;
  LEnabled: Boolean;
  LTarget: TMyrDebugTarget;
begin
  LEnabled := False;

  // Check if 'all' filter is in the filters array
  if not AArgs.IsNull() then
  begin
    LFilters := AArgs.Get('filters');
    if not LFilters.IsNull() then
    begin
      for LI := 0 to LFilters.Count() - 1 do
      begin
        if LFilters.Items()[LI].AsString() = 'all' then
        begin
          LEnabled := True;
          Break;
        end;
      end;
    end;
  end;

  // Set the flag on the debug target
  if Assigned(FRuntime) then
  begin
    LTarget := FRuntime.GetTarget();
    if Assigned(LTarget) then
      LTarget.SetBreakOnExceptions(LEnabled);
  end;

  SendResponse(ASeq, 'setExceptionBreakpoints', True);
end;

procedure TMyrDAPServer.HandleConfigurationDone(const ASeq: Integer);
begin
  // Client has finished sending initial breakpoints — start the debuggee
  FState := dsRunning;
  SendResponse(ASeq, 'configurationDone', True);

  // Apply breakpoints and release the held process
  FRuntime.ConfigurationDone();
end;

procedure TMyrDAPServer.HandleThreads(const ASeq: Integer);
var
  LBody: TJSON;
begin
  // Myra is single-threaded -- report one thread
  LBody := TJSON.Create()
    .BeginArray('threads')
      .BeginObject()
        .Add('id', 1)
        .Add('name', 'Main Thread')
      .EndObject()
    .EndArray();
  SendResponse(ASeq, 'threads', True, LBody);
end;

procedure TMyrDAPServer.HandleStackTrace(const ASeq: Integer;
  const AArgs: TJSON);
var
  LBody: TJSON;
  LStack: TArray<TMyrDebugStackFrame>;
  LI: Integer;
begin
  LStack := FRuntime.GetCallStack();

  LBody := TJSON.Create()
    .BeginArray('stackFrames');
  for LI := 0 to High(LStack) do
  begin
    LBody
      .BeginObject()
        .Add('id', LStack[LI].FrameID)
        .Add('name', LStack[LI].FunctionName)
        .Add('line', LStack[LI].SourceLine)
        .Add('column', LStack[LI].SourceColumn);

    if LStack[LI].SourceFile <> '' then
      LBody
        .BeginObject('source')
          .Add('name', ExtractFileName(LStack[LI].SourceFile))
          .Add('path', LStack[LI].SourceFile)
        .EndObject();

    LBody.EndObject();
  end;
  LBody
    .EndArray()
    .Add('totalFrames', Length(LStack));
  SendResponse(ASeq, 'stackTrace', True, LBody);
end;

procedure TMyrDAPServer.HandleScopes(const ASeq: Integer;
  const AArgs: TJSON);
var
  LBody: TJSON;
begin
  // Return a single "Locals" scope
  LBody := TJSON.Create()
    .BeginArray('scopes')
      .BeginObject()
        .Add('name', 'Locals')
        .Add('variablesReference', 1)
        .Add('expensive', False)
      .EndObject()
    .EndArray();
  SendResponse(ASeq, 'scopes', True, LBody);
end;

procedure TMyrDAPServer.HandleVariables(const ASeq: Integer;
  const AArgs: TJSON);
var
  LBody: TJSON;
  LVars: TArray<TMyrDebugVariable>;
  LI: Integer;
begin
  // Read variables from the runtime (reads from target memory/registers)
  LVars := FRuntime.GetVariables();

  LBody := TJSON.Create()
    .BeginArray('variables');
  for LI := 0 to High(LVars) do
  begin
    LBody
      .BeginObject()
        .Add('name', LVars[LI].VarName)
        .Add('value', LVars[LI].VarValue)
        .Add('type', LVars[LI].VarType)
        .Add('variablesReference', 0)
      .EndObject();
  end;
  LBody.EndArray();
  SendResponse(ASeq, 'variables', True, LBody);
end;

procedure TMyrDAPServer.HandleContinue(const ASeq: Integer);
var
  LBody: TJSON;
begin
  // Guard: only continue when actually stopped at a breakpoint/step
  if FState <> dsStopped then
  begin
    LBody := TJSON.Create();
    LBody.Add('allThreadsContinued', True);
    SendResponse(ASeq, 'continue', True, LBody);
    Exit;
  end;

  LBody := TJSON.Create();
  LBody.Add('allThreadsContinued', True);
  SendResponse(ASeq, 'continue', True, LBody);

  FState := dsRunning;
  FRuntime.Continue();
end;

procedure TMyrDAPServer.HandleNext(const ASeq: Integer);
begin
  if FState <> dsStopped then
  begin
    SendResponse(ASeq, 'next', True);
    Exit;
  end;
  SendResponse(ASeq, 'next', True);
  FState := dsRunning;
  FRuntime.StepOver();
end;

procedure TMyrDAPServer.HandleStepIn(const ASeq: Integer);
begin
  if FState <> dsStopped then
  begin
    SendResponse(ASeq, 'stepIn', True);
    Exit;
  end;
  SendResponse(ASeq, 'stepIn', True);
  FState := dsRunning;
  FRuntime.StepIn();
end;

procedure TMyrDAPServer.HandleStepOut(const ASeq: Integer);
begin
  if FState <> dsStopped then
  begin
    SendResponse(ASeq, 'stepOut', True);
    Exit;
  end;
  SendResponse(ASeq, 'stepOut', True);
  FState := dsRunning;
  FRuntime.StepOut();
end;

procedure TMyrDAPServer.HandlePause(const ASeq: Integer);
begin
  // Phase 1: Not fully supported — would need to inject INT3 at next instruction
  SendResponse(ASeq, 'pause', True);
end;

procedure TMyrDAPServer.HandleEvaluate(const ASeq: Integer;
  const AArgs: TJSON);
var
  LExpression: string;
  LBody: TJSON;
  LVar: TMyrDebugVariable;
begin
  LExpression := '';
  if not AArgs.IsNull() then
    LExpression := AArgs.Get('expression').AsString();

  if LExpression = '' then
  begin
    SendResponse(ASeq, 'evaluate', False, nil, 'Empty expression');
    Exit;
  end;

  // Look up the variable through the runtime (DAP-clean path)
  LVar := FRuntime.Evaluate(LExpression);

  LBody := TJSON.Create();
  if LVar.VarValue <> '' then
  begin
    LBody.Add('result', LVar.VarValue);
    LBody.Add('type', LVar.VarType);
    LBody.Add('variablesReference', 0);
    SendResponse(ASeq, 'evaluate', True, LBody);
  end
  else
  begin
    LBody.Free();
    SendResponse(ASeq, 'evaluate', False, nil,
      Format('Variable ''%s'' not found in current scope', [LExpression]));
  end;
end;

procedure TMyrDAPServer.HandleDisconnect(const ASeq: Integer);
begin
  SendResponse(ASeq, 'disconnect', True);
  SendEvent('terminated');
  FState := dsTerminated;
end;

procedure TMyrDAPServer.ProcessStopEvent();
var
  LBody: TJSON;
  LEvent: TMyrDebugStopEvent;
begin
  LEvent := FRuntime.GetLastStopEvent();

  LBody := TJSON.Create();
  LBody.Add('threadId', 1);
  LBody.Add('allThreadsStopped', True);

  case LEvent.Reason of
    dsrBreakpoint:
    begin
      LBody.Add('reason', 'breakpoint');
      FState := dsStopped;
    end;
    dsrSingleStep:
    begin
      LBody.Add('reason', 'step');
      FState := dsStopped;
    end;
    dsrException:
    begin
      LBody.Add('reason', 'exception');
      if LEvent.ExceptionMessage <> '' then
        LBody.Add('description', LEvent.ExceptionMessage)
      else
        LBody.Add('description', Format('Exception 0x%x', [LEvent.ExceptionCode]));
      LBody.Add('text', Format('0x%x', [LEvent.ExceptionCode]));
      FState := dsStopped;
    end;
    dsrProcessExit:
    begin
      // DAP spec: send exited (with exit code) then terminated
      LBody.Free();
      LBody := TJSON.Create();
      LBody.Add('exitCode', LEvent.ExitCode);
      SendEvent('exited', LBody);
      SendEvent('terminated');
      FState := dsTerminated;
      Exit;
    end;
    dsrDllLoad:
    begin
      // DLL load is handled internally by the runtime — should not reach here.
      // If it does, just ignore it.
      LBody.Free();
      Exit;
    end;
  else
    LBody.Add('reason', 'pause');
    FState := dsStopped;
  end;

  SendEvent('stopped', LBody);
end;

{ TMyrDebugClient }
constructor TMyrDebugClient.Create();
begin
  inherited Create();
  FSocket := INVALID_SOCKET;
  FState := dcsDisconnected;
  FNextSeq := 1;
  FLastError := '';
  FCurrentThreadId := 0;
  FVerboseLogging := False;
  SetLength(FReadBuffer, 65536);
  FReadBufferLen := 0;
  FOnStopped := nil;
  FOnOutput := nil;
  FOnExited := nil;
end;

destructor TMyrDebugClient.Destroy();
begin
  Disconnect();
  inherited Destroy();
end;

function TMyrDebugClient.GetNextSeq(): Integer;
begin
  Result := FNextSeq;
  Inc(FNextSeq);
end;

procedure TMyrDebugClient.SetError(const AError: string);
begin
  FLastError := AError;
end;

function TMyrDebugClient.HasError(): Boolean;
begin
  Result := FLastError <> '';
end;

function TMyrDebugClient.GetLastError(): string;
begin
  Result := FLastError;
end;

function TMyrDebugClient.GetState(): TMyrDAPClientState;
begin
  Result := FState;
end;

function TMyrDebugClient.GetCurrentThreadId(): Integer;
begin
  Result := FCurrentThreadId;
end;

function TMyrDebugClient.Connect(const AHost: string; const APort: Integer): Boolean;
var
  LWSAData: TWSAData;
  LAddr: TSockAddrIn;
  LHostEnt: PHostEnt;
begin
  Result := False;
  FLastError := '';

  if WSAStartup(MakeWord(2, 2), LWSAData) <> 0 then
  begin
    SetError('WSAStartup failed');
    Exit;
  end;

  FSocket := WinApi.WinSock.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FSocket = INVALID_SOCKET then
  begin
    SetError('Failed to create socket');
    WSACleanup();
    Exit;
  end;

  FillChar(LAddr, SizeOf(LAddr), 0);
  LAddr.sin_family := AF_INET;
  LAddr.sin_port := htons(APort);
  LAddr.sin_addr.S_addr := inet_addr(PAnsiChar(AnsiString(AHost)));

  if LAddr.sin_addr.S_addr = u_long($FFFFFFFF) then
  begin
    LHostEnt := gethostbyname(PAnsiChar(AnsiString(AHost)));
    if LHostEnt = nil then
    begin
      SetError('Cannot resolve host: ' + AHost);
      closesocket(FSocket);
      FSocket := INVALID_SOCKET;
      WSACleanup();
      Exit;
    end;
    LAddr.sin_addr := PInAddr(LHostEnt^.h_addr_list^)^;
  end;

  if WinApi.WinSock.connect(FSocket, LAddr, SizeOf(LAddr)) = SOCKET_ERROR then
  begin
    SetError(Format('Cannot connect to %s:%d', [AHost, APort]));
    closesocket(FSocket);
    FSocket := INVALID_SOCKET;
    WSACleanup();
    Exit;
  end;

  FState := dcsConnected;
  FReadBufferLen := 0;
  Result := True;
end;

procedure TMyrDebugClient.Disconnect();
begin
  if FSocket <> INVALID_SOCKET then
  begin
    closesocket(FSocket);
    FSocket := INVALID_SOCKET;
    WSACleanup();
  end;
  FState := dcsDisconnected;
  FReadBufferLen := 0;
end;

function TMyrDebugClient.SendRaw(const AData: string): Boolean;
var
  LBytes: TBytes;
  LSent: Integer;
  LTotal: Integer;
  LRemaining: Integer;
begin
  Result := False;
  if FSocket = INVALID_SOCKET then Exit;

  LBytes := TEncoding.UTF8.GetBytes(AData);
  LTotal := 0;
  LRemaining := Length(LBytes);

  while LRemaining > 0 do
  begin
    LSent := send(FSocket, LBytes[LTotal], LRemaining, 0);
    if LSent = SOCKET_ERROR then
    begin
      SetError('Send failed');
      Exit;
    end;
    Inc(LTotal, LSent);
    Dec(LRemaining, LSent);
  end;
  Result := True;
end;

procedure TMyrDebugClient.SendDAPMessage(const AJson: string);
var
  LMsg: string;
begin
  LMsg := Format('Content-Length: %d'#13#10#13#10'%s',
    [Length(TEncoding.UTF8.GetBytes(AJson)), AJson]);
  Status(FVerboseLogging, '[DAP-C] >> %s', [AJson]);
  SendRaw(LMsg);
end;

function TMyrDebugClient.ReadDAPMessage(out AJson: string;
  const ATimeoutMS: Integer): Boolean;
var
  LHeaderEnd: Integer;
  LHeader: string;
  LContentLength: Integer;
  LI: Integer;
  LReceived: Integer;
  LNeeded: Integer;
  LFD: TFDSet;
  LTimeout: TTimeVal;
  LSelectResult: Integer;
begin
  Result := False;
  AJson := '';

  if FSocket = INVALID_SOCKET then Exit;

  // Read until we have a complete Content-Length header + body
  while True do
  begin
    // Check if we have a complete header in the buffer
    LHeaderEnd := -1;
    for LI := 0 to FReadBufferLen - 4 do
    begin
      if (FReadBuffer[LI] = 13) and (FReadBuffer[LI+1] = 10) and
         (FReadBuffer[LI+2] = 13) and (FReadBuffer[LI+3] = 10) then
      begin
        LHeaderEnd := LI;
        Break;
      end;
    end;

    if LHeaderEnd >= 0 then
    begin
      // Parse Content-Length from header
      LHeader := TEncoding.UTF8.GetString(FReadBuffer, 0, LHeaderEnd);
      LContentLength := 0;
      if Pos('Content-Length:', LHeader) > 0 then
        LContentLength := StrToIntDef(Trim(Copy(LHeader,
          Pos(':', LHeader) + 1, MaxInt)), 0);

      if LContentLength <= 0 then
      begin
        SetError('Invalid Content-Length in DAP message');
        Exit;
      end;

      // Check if we have the full body
      LNeeded := (LHeaderEnd + 4) + LContentLength;
      if FReadBufferLen >= LNeeded then
      begin
        // Extract JSON body
        AJson := TEncoding.UTF8.GetString(FReadBuffer,
          LHeaderEnd + 4, LContentLength);

        // Shift remaining data to front of buffer
        if FReadBufferLen > LNeeded then
          Move(FReadBuffer[LNeeded], FReadBuffer[0], FReadBufferLen - LNeeded);
        Dec(FReadBufferLen, LNeeded);

        Status(FVerboseLogging, '[DAP-C] << %s', [AJson]);

        Result := True;
        Exit;
      end;
    end;

    // Need more data — use select() with timeout
    FD_ZERO(LFD);
    FD_SET(FSocket, LFD);
    LTimeout.tv_sec := ATimeoutMS div 1000;
    LTimeout.tv_usec := (ATimeoutMS mod 1000) * 1000;

    LSelectResult := select(0, @LFD, nil, nil, @LTimeout);
    if LSelectResult <= 0 then
    begin
      if LSelectResult = 0 then
        SetError('Timeout reading DAP message')
      else
        SetError('Select failed');
      Exit;
    end;

    // Grow buffer if needed
    if FReadBufferLen >= Length(FReadBuffer) - 4096 then
      SetLength(FReadBuffer, Length(FReadBuffer) * 2);

    LReceived := recv(FSocket, FReadBuffer[FReadBufferLen],
      Length(FReadBuffer) - FReadBufferLen, 0);
    if LReceived <= 0 then
    begin
      SetError('Connection closed');
      Exit;
    end;

    Inc(FReadBufferLen, LReceived);
  end;
end;

function TMyrDebugClient.SendRequest(const ACommand: string;
  const AArgs: TJSON): TJSON;
var
  LRequest: TJSON;
  LRequestJson: string;
  LResponseJson: string;
  LResponse: TJSON;
  LMsgType: string;
  LSuccess: Boolean;
  LMessage: string;
begin
  Result := nil;
  FLastError := '';

  if FSocket = INVALID_SOCKET then
  begin
    SetError('Not connected');
    Exit;
  end;

  // Build DAP request
  LRequest := TJSON.Create();
  try
    LRequest.Add('seq', GetNextSeq());
    LRequest.Add('type', 'request');
    LRequest.Add('command', ACommand);
    if Assigned(AArgs) then
      LRequest.Add('arguments', AArgs);
    LRequestJson := LRequest.ToString();
  finally
    LRequest.Free();
  end;

  SendDAPMessage(LRequestJson);

  // Read responses (processing events in between)
  while True do
  begin
    if not ReadDAPMessage(LResponseJson, 10000) then
      Exit;

    LResponse := nil;
    try
      LResponse := TJSON.FromString(LResponseJson);
    except
      SetError('Invalid JSON response');
      Exit;
    end;

    if not Assigned(LResponse) then
    begin
      SetError('Failed to parse DAP response');
      Exit;
    end;

    try
      LMsgType := LResponse.Get('type').AsString();

      if LMsgType = 'event' then
      begin
        // Process event and keep waiting for actual response
        ProcessEvent(LResponse);
        FreeAndNil(LResponse);
        Continue;
      end
      else if LMsgType = 'response' then
      begin
        LSuccess := LResponse.Get('success').AsBoolean();
        if not LSuccess then
        begin
          LMessage := LResponse.Get('message').AsString('Unknown error');
          SetError('DAP error: ' + LMessage);
          LResponse.Free();
          Exit;
        end;

        // Return the full response (caller frees)
        Result := LResponse;
        Exit;
      end;
    except
      on E: Exception do
      begin
        SetError('Error processing response: ' + E.Message);
        LResponse.Free();
        Exit;
      end;
    end;
  end;
end;

procedure TMyrDebugClient.ProcessEvent(const AEvent: TJSON);
var
  LEventName: string;
  LBody: TJSON;
  LReason: string;
  LThreadId: Integer;
  LExitCode: Integer;
  LOutput: string;
begin
  try
    LEventName := AEvent.Get('event').AsString();

    if LEventName = 'stopped' then
    begin
      LBody := AEvent.Get('body');
      if not LBody.IsNull() then
      begin
        LReason := LBody.Get('reason').AsString();
        LThreadId := LBody.Get('threadId').AsInt32();
        FCurrentThreadId := LThreadId;
        FState := dcsStopped;
        if Assigned(FOnStopped) then
          FOnStopped(LReason, LThreadId);
      end;
    end
    else if LEventName = 'exited' then
    begin
      LBody := AEvent.Get('body');
      LExitCode := 0;
      if not LBody.IsNull() then
        LExitCode := LBody.Get('exitCode').AsInt32();
      FState := dcsExited;
      if Assigned(FOnExited) then
        FOnExited(LExitCode);
    end
    else if LEventName = 'terminated' then
    begin
      FState := dcsExited;
    end
    else if LEventName = 'output' then
    begin
      LBody := AEvent.Get('body');
      if not LBody.IsNull() then
      begin
        LOutput := LBody.Get('output').AsString();
        if Assigned(FOnOutput) and (LOutput <> '') then
          FOnOutput(LOutput);
      end;
    end;
  except
    // Silently ignore malformed events
  end;
end;

procedure TMyrDebugClient.ProcessPendingEvents(const ATimeoutMS: Integer);
var
  LJson: string;
  LObj: TJSON;
  LMsgType: string;
begin
  while ReadDAPMessage(LJson, ATimeoutMS) do
  begin
    LObj := nil;
    try
      LObj := TJSON.FromString(LJson);
      if Assigned(LObj) then
      begin
        LMsgType := LObj.Get('type').AsString();
        if LMsgType = 'event' then
          ProcessEvent(LObj);
      end;
    finally
      LObj.Free();
    end;
  end;
end;

function TMyrDebugClient.Initialize(): Boolean;
var
  LArgs: TJSON;
  LResponse: TJSON;
begin
  Result := False;
  LArgs := TJSON.Create();
  LArgs.Add('clientID', 'viper-test');
  LArgs.Add('adapterID', 'viper');
  LArgs.Add('linesStartAt1', True);
  LArgs.Add('columnsStartAt1', True);
  LArgs.Add('pathFormat', 'path');

  LResponse := SendRequest('initialize', LArgs);
  LArgs.Free();
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    FState := dcsInitialized;
    Result := True;
  end;
end;

function TMyrDebugClient.Launch(const AProgram: string;
  const AStopOnEntry: Boolean): Boolean;
var
  LArgs: TJSON;
  LResponse: TJSON;
begin
  Result := False;
  LArgs := TJSON.Create();
  LArgs.Add('program', AProgram);
  LArgs.Add('stopOnEntry', AStopOnEntry);

  LResponse := SendRequest('launch', LArgs);
  LArgs.Free();
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    FState := dcsLaunched;
    Result := True;
  end;
end;

function TMyrDebugClient.ConfigurationDone(): Boolean;
var
  LResponse: TJSON;
begin
  Result := False;
  LResponse := SendRequest('configurationDone', nil);
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    Result := True;
  end;
end;

function TMyrDebugClient.SetBreakpoints(const ASourcePath: string;
  const ALines: array of Integer): Boolean;
var
  LArgs: TJSON;
  LI: Integer;
  LResponse: TJSON;
begin
  Result := False;

  LArgs := TJSON.Create()
    .BeginObject('source')
      .Add('path', ASourcePath)
    .EndObject()
    .BeginArray('breakpoints');
  for LI := 0 to High(ALines) do
    LArgs
      .BeginObject()
        .Add('line', ALines[LI])
      .EndObject();
  LArgs.EndArray();

  LResponse := SendRequest('setBreakpoints', LArgs);
  LArgs.Free();
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    Result := True;
  end;
end;

function TMyrDebugClient.SetBreakpoints(const ASourcePath: string;
  const ALines: array of Integer;
  const AHitConditions: array of Integer): Boolean;
var
  LArgs: TJSON;
  LI: Integer;
  LResponse: TJSON;
begin
  Result := False;

  LArgs := TJSON.Create()
    .BeginObject('source')
      .Add('path', ASourcePath)
    .EndObject()
    .BeginArray('breakpoints');
  for LI := 0 to High(ALines) do
  begin
    LArgs
      .BeginObject()
        .Add('line', ALines[LI]);
    // Add hitCondition if provided for this index
    if (LI <= High(AHitConditions)) and (AHitConditions[LI] > 0) then
      LArgs.Add('hitCondition', IntToStr(AHitConditions[LI]));
    LArgs.EndObject();
  end;
  LArgs.EndArray();

  LResponse := SendRequest('setBreakpoints', LArgs);
  LArgs.Free();
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    Result := True;
  end;
end;

function TMyrDebugClient.Continue(): Boolean;
var
  LArgs: TJSON;
  LResponse: TJSON;
begin
  Result := False;
  LArgs := TJSON.Create();
  LArgs.Add('threadId', FCurrentThreadId);
  LResponse := SendRequest('continue', LArgs);
  LArgs.Free();
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    FState := dcsLaunched;
    Result := True;
  end;
end;

function TMyrDebugClient.StepOver(): Boolean;
var
  LArgs: TJSON;
  LResponse: TJSON;
begin
  Result := False;
  LArgs := TJSON.Create();
  LArgs.Add('threadId', FCurrentThreadId);
  LResponse := SendRequest('next', LArgs);
  LArgs.Free();
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    Result := True;
  end;
end;

function TMyrDebugClient.StepIn(): Boolean;
var
  LArgs: TJSON;
  LResponse: TJSON;
begin
  Result := False;
  LArgs := TJSON.Create();
  LArgs.Add('threadId', FCurrentThreadId);
  LResponse := SendRequest('stepIn', LArgs);
  LArgs.Free();
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    Result := True;
  end;
end;

function TMyrDebugClient.StepOut(): Boolean;
var
  LArgs: TJSON;
  LResponse: TJSON;
begin
  Result := False;
  LArgs := TJSON.Create();
  LArgs.Add('threadId', FCurrentThreadId);
  LResponse := SendRequest('stepOut', LArgs);
  LArgs.Free();
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    Result := True;
  end;
end;

function TMyrDebugClient.GetCallStack(const AThreadId: Integer): TArray<TMyrDAPClientStackFrame>;
var
  LArgs: TJSON;
  LResponse: TJSON;
  LBody: TJSON;
  LFrames: TJSON;
  LFrame: TJSON;
  LSource: TJSON;
  LI: Integer;
  LThreadId: Integer;
begin
  Result := nil;

  LThreadId := AThreadId;
  if LThreadId = 0 then
    LThreadId := FCurrentThreadId;
  if LThreadId = 0 then
    LThreadId := 1;

  LArgs := TJSON.Create();
  LArgs.Add('threadId', LThreadId);
  LArgs.Add('startFrame', 0);
  LArgs.Add('levels', 20);

  LResponse := SendRequest('stackTrace', LArgs);
  LArgs.Free();
  if not Assigned(LResponse) then Exit;

  try
    LBody := LResponse.Get('body');
    if LBody.IsNull() then Exit;

    LFrames := LBody.Get('stackFrames');
    if LFrames.IsNull() then Exit;

    SetLength(Result, LFrames.Count());
    for LI := 0 to LFrames.Count() - 1 do
    begin
      LFrame := LFrames.Items()[LI];
      Result[LI].FrameID := LFrame.Get('id').AsInt32();
      Result[LI].FunctionName := LFrame.Get('name').AsString();
      Result[LI].SourceLine := LFrame.Get('line').AsInt32();

      LSource := LFrame.Get('source');
      if not LSource.IsNull() then
        Result[LI].SourceFile := LSource.Get('path').AsString()
      else
        Result[LI].SourceFile := '';
    end;
  finally
    LResponse.Free();
  end;
end;

function TMyrDebugClient.GetScopes(const AFrameId: Integer): TArray<TMyrDAPClientScope>;
var
  LArgs: TJSON;
  LResponse: TJSON;
  LBody: TJSON;
  LScopes: TJSON;
  LScope: TJSON;
  LI: Integer;
begin
  Result := nil;

  LArgs := TJSON.Create();
  LArgs.Add('frameId', AFrameId);

  LResponse := SendRequest('scopes', LArgs);
  LArgs.Free();
  if not Assigned(LResponse) then Exit;

  try
    LBody := LResponse.Get('body');
    if LBody.IsNull() then Exit;

    LScopes := LBody.Get('scopes');
    if LScopes.IsNull() then Exit;

    SetLength(Result, LScopes.Count());
    for LI := 0 to LScopes.Count() - 1 do
    begin
      LScope := LScopes.Items()[LI];
      Result[LI].ScopeName := LScope.Get('name').AsString();
      Result[LI].VariablesReference := LScope.Get('variablesReference').AsInt32();
      Result[LI].Expensive := LScope.Get('expensive').AsBoolean();
    end;
  finally
    LResponse.Free();
  end;
end;

function TMyrDebugClient.GetVariables(const AVariablesReference: Integer): TArray<TMyrDAPClientVariable>;
var
  LArgs: TJSON;
  LResponse: TJSON;
  LBody: TJSON;
  LVars: TJSON;
  LVar: TJSON;
  LI: Integer;
begin
  Result := nil;

  LArgs := TJSON.Create();
  LArgs.Add('variablesReference', AVariablesReference);

  LResponse := SendRequest('variables', LArgs);
  LArgs.Free();
  if not Assigned(LResponse) then Exit;

  try
    LBody := LResponse.Get('body');
    if LBody.IsNull() then Exit;

    LVars := LBody.Get('variables');
    if LVars.IsNull() then Exit;

    SetLength(Result, LVars.Count());
    for LI := 0 to LVars.Count() - 1 do
    begin
      LVar := LVars.Items()[LI];
      Result[LI].VarName := LVar.Get('name').AsString();
      Result[LI].VarValue := LVar.Get('value').AsString();
      Result[LI].VarType := LVar.Get('type').AsString();
      Result[LI].VariablesReference := LVar.Get('variablesReference').AsInt32();
    end;
  finally
    LResponse.Free();
  end;
end;

function TMyrDebugClient.Evaluate(const AExpression: string;
  const AFrameId: Integer): string;
var
  LArgs: TJSON;
  LResponse: TJSON;
  LBody: TJSON;
begin
  Result := '';
  FLastError := '';

  LArgs := TJSON.Create();
  LArgs.Add('expression', AExpression);
  LArgs.Add('frameId', AFrameId);
  LArgs.Add('context', 'repl');

  LResponse := SendRequest('evaluate', LArgs);
  LArgs.Free();
  if not Assigned(LResponse) then
    Exit;

  try
    LBody := LResponse.Get('body');
    if not LBody.IsNull() then
      Result := LBody.Get('result').AsString();
  finally
    LResponse.Free();
  end;
end;

function TMyrDebugClient.DisconnectDAP(): Boolean;
var
  LArgs: TJSON;
  LResponse: TJSON;
begin
  Result := False;

  LArgs := TJSON.Create();
  LArgs.Add('terminateDebuggee', True);

  LResponse := SendRequest('disconnect', LArgs);
  LArgs.Free();
  if Assigned(LResponse) then
  begin
    LResponse.Free();
    Result := True;
  end;
end;

{ TMyrDAPListenerThread }
constructor TMyrDAPListenerThread.Create(const AServer: TMyrDAPServer);
begin
  inherited Create(True);  // Create suspended
  FreeOnTerminate := False;
  FServer := AServer;
end;

procedure TMyrDAPListenerThread.Execute();
begin
  FServer.RunMessageLoop();
end;


{ TMyrStopWatcherThread }
constructor TMyrStopWatcherThread.Create(const ADebugger: TMyrDebugServer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FDebugger := ADebugger;
end;

procedure TMyrStopWatcherThread.Execute();
begin
  while not Terminated do
  begin
    // Block until the debug runtime reports a stop
    if FDebugger.FRuntime.WaitForStop() then
    begin
      if Terminated then
        Break;
      // Notify the DAP server about the stop
      FDebugger.FDAPServer.ProcessStopEvent();
    end
    else
      Break;  // WaitForStop failed — target gone
  end;
end;


{ TMyrDebugServer }
constructor TMyrDebugServer.Create();
begin
  inherited Create();
  FSourceMap := nil;
  FTarget := nil;
  FRuntime := nil;
  FDAPServer := nil;
  FDAPThread := nil;
  FStopWatcher := nil;
  FPort := 0;
  FMode := dmExe;
  FOwnSourceMap := False;
end;

destructor TMyrDebugServer.Destroy();
begin
  StopDebugging();
  inherited Destroy();
end;

function TMyrDebugServer.DebugExe(const AExePath: string;
  const APort: Integer): Boolean;
var
  LPETarget: TMyrPEDebugTarget;
  LVdbgPath: string;
begin
  Result := False;
  FPort := APort;
  FMode := dmExe;

  // Validate EXE exists
  if not FileExists(AExePath) then
  begin
    FErrors.Add(esError, 'DBG200', 'EXE not found: %s', [AExePath]);
    Exit;
  end;

  // Load .mdbg debug info sidecar file
  LVdbgPath := ChangeFileExt(AExePath, '.mdbg');
  if not FileExists(LVdbgPath) then
  begin
    FErrors.Add(esError, 'DBG202',
      'Debug info file not found: %s — rebuild with debug mode enabled',
      [LVdbgPath]);
    Exit;
  end;

  FSourceMap := TMyrSourceMap.Create();
  FOwnSourceMap := True;
  try
    FSourceMap.LoadFromFile(LVdbgPath);
  except
    on E: Exception do
    begin
      FErrors.Add(esError, 'DBG203',
        'Failed to load debug info: %s', [E.Message]);
      FreeAndNil(FSourceMap);
      FOwnSourceMap := False;
      Exit;
    end;
  end;

  // Create PE debug target
  LPETarget := TMyrPEDebugTarget.Create();
  LPETarget.SetErrors(FErrors);
  LPETarget.SetExePath(AExePath);
  LPETarget.SetTextSectionRVA(FSourceMap.GetTextSectionRVA());
  LPETarget.SetDataSectionRVA(FSourceMap.GetDataSectionRVA());
  FTarget := LPETarget;

  // Create debug runtime (breakpoints, stepping, stack walker)
  FRuntime := TMyrDebugRuntime.Create();
  FRuntime.SetErrors(FErrors);
  FRuntime.SetTarget(FTarget);
  FRuntime.SetSourceMap(FSourceMap);

  // Create DAP server
  FDAPServer := TMyrDAPServer.Create();
  FDAPServer.SetErrors(FErrors);
  FDAPServer.SetRuntime(FRuntime);
  FDAPServer.SetSourceMap(FSourceMap);

  // Start TCP listener
  if not FDAPServer.StartListening(APort) then
  begin
    FErrors.Add(esFatal, 'DBG100',
      'Failed to start DAP server on port %d', [APort]);
    Exit;
  end;

  Status('DAP server listening on port %d — attach your debugger', [APort]);

  // Wait for client connection (blocking)
  if not FDAPServer.WaitForConnection() then
  begin
    FErrors.Add(esFatal, 'DBG101', 'No client connected');
    Exit;
  end;

  Status('Debugger client connected');

  // Start the PE debug target (launches the process with DEBUG_ONLY_THIS_PROCESS)
  try
    if not FTarget.Start() then
    begin
      Status('ERROR: Failed to start debug target');
      Exit;
    end;
  except
    on E: Exception do
    begin
      Status('ERROR: Target.Start() exception: %s', [E.Message]);
      Exit;
    end;
  end;

  Status('Debuggee launched: %s', [AExePath]);

  // Start DAP message loop on background thread (must be running before
  // client completes DAP handshake)
  FDAPThread := TMyrDAPListenerThread.Create(FDAPServer);
  FDAPThread.Start();

  // Start stop watcher thread (bridges runtime stops -> DAP events)
  FStopWatcher := TMyrStopWatcherThread.Create(Self);
  FStopWatcher.Start();

  Status('Debug session active -- waiting for configurationDone');
  Result := True;
end;

function TMyrDebugServer.DebugDll(const ADllPath: string;
  const AHostExe: string; const APort: Integer): Boolean;
var
  LPETarget: TMyrPEDebugTarget;
  LVdbgPath: string;
begin
  Result := False;
  FPort := APort;
  FMode := dmDll;

  // Validate DLL exists
  if not FileExists(ADllPath) then
  begin
    FErrors.Add(esError, 'DBG200', 'DLL not found: %s', [ADllPath]);
    Exit;
  end;

  // Validate host EXE is provided and exists
  if AHostExe = '' then
  begin
    FErrors.Add(esError, 'DBG204',
      'Host EXE required for DLL debugging — specify a host application that loads the DLL');
    Exit;
  end;

  if not FileExists(AHostExe) then
  begin
    FErrors.Add(esError, 'DBG205', 'Host EXE not found: %s', [AHostExe]);
    Exit;
  end;

  // Load .mdbg debug info sidecar file for the DLL
  LVdbgPath := ChangeFileExt(ADllPath, '.mdbg');
  if not FileExists(LVdbgPath) then
  begin
    FErrors.Add(esError, 'DBG202',
      'Debug info file not found: %s — rebuild with debug mode enabled',
      [LVdbgPath]);
    Exit;
  end;

  FSourceMap := TMyrSourceMap.Create();
  FOwnSourceMap := True;
  try
    FSourceMap.LoadFromFile(LVdbgPath);
  except
    on E: Exception do
    begin
      FErrors.Add(esError, 'DBG203',
        'Failed to load debug info: %s', [E.Message]);
      FreeAndNil(FSourceMap);
      FOwnSourceMap := False;
      Exit;
    end;
  end;

  // Create PE debug target in DLL mode
  LPETarget := TMyrPEDebugTarget.Create();
  LPETarget.SetErrors(FErrors);
  LPETarget.SetTextSectionRVA(FSourceMap.GetTextSectionRVA());
  LPETarget.SetDataSectionRVA(FSourceMap.GetDataSectionRVA());
  LPETarget.SetDllMode(ADllPath, AHostExe);
  FTarget := LPETarget;

  // Create debug runtime (breakpoints, stepping, stack walker)
  FRuntime := TMyrDebugRuntime.Create();
  FRuntime.SetErrors(FErrors);
  FRuntime.SetTarget(FTarget);
  FRuntime.SetSourceMap(FSourceMap);

  // Create DAP server
  FDAPServer := TMyrDAPServer.Create();
  FDAPServer.SetErrors(FErrors);
  FDAPServer.SetRuntime(FRuntime);
  FDAPServer.SetSourceMap(FSourceMap);

  // Start TCP listener
  if not FDAPServer.StartListening(APort) then
  begin
    FErrors.Add(esFatal, 'DBG100',
      'Failed to start DAP server on port %d', [APort]);
    Exit;
  end;

  Status('DAP server listening on port %d — attach your debugger', [APort]);

  // Wait for client connection (blocking)
  if not FDAPServer.WaitForConnection() then
  begin
    FErrors.Add(esFatal, 'DBG101', 'No client connected');
    Exit;
  end;

  Status('Debugger client connected');

  // Start the PE debug target (launches the host EXE with DEBUG_ONLY_THIS_PROCESS)
  if not FTarget.Start() then
  begin
    FErrors.Add(esFatal, 'DBG102', 'Failed to start debug target');
    Exit;
  end;

  Status('Host launched: %s — waiting for DLL: %s',
    [AHostExe, ExtractFileName(ADllPath)]);

  // Start DAP message loop on background thread
  FDAPThread := TMyrDAPListenerThread.Create(FDAPServer);
  FDAPThread.Start();

  // Start stop watcher thread (bridges runtime stops → DAP events)
  // The runtime handles dsrDllLoad internally (applies breakpoints + resumes)
  FStopWatcher := TMyrStopWatcherThread.Create(Self);
  FStopWatcher.Start();

  Status('Debug session active — waiting for configurationDone');
  Result := True;
end;

procedure TMyrDebugServer.StopDebugging();
begin
  // Stop watcher thread first (it reads from runtime)
  if FStopWatcher <> nil then
  begin
    FStopWatcher.Terminate();
    // Signal FStoppedEvent so WaitForStop unblocks (not FResumeEvent!)
    if FTarget <> nil then
      FTarget.UnblockWaitForStop();
    FStopWatcher.WaitFor();
    FreeAndNil(FStopWatcher);
  end;

  // Close sockets first — this causes recv() in the DAP thread to return -1,
  // which makes ReadMessage return nil, which exits RunMessageLoop
  if FDAPServer <> nil then
    FDAPServer.StopServer();

  // Now the DAP thread can be safely joined
  if FDAPThread <> nil then
  begin
    FDAPThread.Terminate();
    FDAPThread.WaitFor();
    FreeAndNil(FDAPThread);
  end;

  // Free the DAP server object (sockets already closed above)
  FreeAndNil(FDAPServer);

  // Stop runtime (removes breakpoints)
  FreeAndNil(FRuntime);

  // Stop target (unregisters VEH / terminates process)
  if FTarget <> nil then
  begin
    FTarget.Stop();
    FreeAndNil(FTarget);
  end;

  // Free source map if we created it (EXE/DLL mode)
  if FOwnSourceMap then
  begin
    FreeAndNil(FSourceMap);
    FOwnSourceMap := False;
  end
  else
    FSourceMap := nil;  // not owned by us
end;

function TMyrDebugServer.HasErrors(): Boolean;
begin
  Result := FErrors.HasErrors();
end;

function TMyrDebugServer.HasWarnings(): Boolean;
begin
  Result := FErrors.HasWarnings();
end;

function TMyrDebugServer.HasHints(): Boolean;
begin
  Result := FErrors.HasHints();
end;

function TMyrDebugServer.HasFatal(): Boolean;
begin
  Result := FErrors.HasFatal();
end;

function TMyrDebugServer.ErrorCount(): Integer;
begin
  Result := FErrors.ErrorCount();
end;

function TMyrDebugServer.WarningCount(): Integer;
begin
  Result := FErrors.WarningCount();
end;

function TMyrDebugServer.GetErrorItems(): TList<TError>;
begin
  Result := FErrors.GetItems();
end;

function TMyrDebugServer.GetErrorText(): string;
begin
  Result := FErrors.ToString();
end;

function TMyrDebugServer.GetRuntime(): TMyrDebugRuntime;
begin
  Result := FRuntime;
end;

function TMyrDebugServer.GetDAPServer(): TMyrDAPServer;
begin
  Result := FDAPServer;
end;

function TMyrDebugServer.GetSourceMap(): TMyrSourceMap;
begin
  Result := FSourceMap;
end;

{ TMyrDebugREPL }
constructor TMyrDebugREPL.Create();
begin
  inherited Create();
  FServer := nil;
  FClient := nil;
  FServerThread := nil;
  FBreakpoints := TList<TMyrREPLBreakpoint>.Create();
  FRunning := False;
  FExePath := '';
  FPort := CDefaultDAPPort;
  FPrompt := '(mdbg) ';
  FTimeoutContinueMS := CTimeoutContinueMS;
  FTimeoutStepMS := CTimeoutStepMS;
  FVerboseLogging := False;
end;

destructor TMyrDebugREPL.Destroy();
begin
  StopSession();
  FBreakpoints.Free();
  inherited Destroy();
end;

procedure TMyrDebugREPL.StopSession();
begin
  if Assigned(FClient) then
  begin
    try
      FClient.DisconnectDAP();
    except
      // Ignore errors during shutdown
    end;
    FClient.Disconnect();
    FreeAndNil(FClient);
  end;

  if Assigned(FServer) then
  begin
    FServer.StopDebugging();
    FreeAndNil(FServer);
  end;

  if Assigned(FServerThread) then
  begin
    FServerThread.WaitFor();
    FreeAndNil(FServerThread);
  end;
end;

procedure TMyrDebugREPL.StartSession();
var
  LExePath: string;
  LPort: Integer;
begin
  LExePath := FExePath;
  LPort := FPort;

  FServer := TMyrDebugServer.Create();
  FServer.SetStatusCallback(FStatusCallback.Callback, FStatusCallback.UserData);

  // Start server on background thread (DebugExe blocks on WaitForConnection)
  FServerThread := TThread.CreateAnonymousThread(
    procedure
    begin
      FServer.DebugExe(LExePath, LPort);
    end
  );
  FServerThread.FreeOnTerminate := False;
  FServerThread.Start();

  // Give server time to start listening
  Sleep(500);

  FClient := TMyrDebugClient.Create();
  FClient.VerboseLogging := FVerboseLogging;
end;

function TMyrDebugREPL.DoDAHandshake(): Boolean;
begin
  Result := False;

  if not FClient.Connect('127.0.0.1', FPort) then
  begin
    TConsole.PrintLn(COLOR_RED + 'Connect failed: ' + FClient.GetLastError());
    Exit;
  end;
  TConsole.PrintLn('Connected to debug server on port %d', [FPort]);

  if not FClient.Initialize() then
  begin
    TConsole.PrintLn(COLOR_RED + 'Initialize failed: ' + FClient.GetLastError());
    Exit;
  end;

  if not FClient.Launch(FExePath, False) then
  begin
    TConsole.PrintLn(COLOR_RED + 'Launch failed: ' + FClient.GetLastError());
    Exit;
  end;

  TConsole.PrintLn(COLOR_GREEN + 'DAP handshake complete');
  Result := True;
end;

procedure TMyrDebugREPL.ShowSourceContext();
var
  LFrames: TArray<TMyrDAPClientStackFrame>;
  LSourceFile: string;
  LSourceLine: Integer;
  LLines: TStringList;
  LStart: Integer;
  LEnd: Integer;
  LI: Integer;
  LArrow: string;
begin
  LFrames := FClient.GetCallStack();
  if Length(LFrames) = 0 then
    Exit;

  LSourceFile := LFrames[0].SourceFile;
  LSourceLine := LFrames[0].SourceLine;

  if (LSourceFile = '') or (LSourceLine <= 0) then
    Exit;

  // Try to read the source file from disk
  if not TFile.Exists(LSourceFile) then
  begin
    TConsole.PrintLn('  Stopped at %s:%d (%s)',
      [ExtractFileName(LSourceFile), LSourceLine, LFrames[0].FunctionName]);
    Exit;
  end;

  LLines := TStringList.Create();
  try
    LLines.LoadFromFile(LSourceFile);

    LStart := LSourceLine - 3;
    if LStart < 0 then
      LStart := 0;
    LEnd := LSourceLine + 1;
    if LEnd >= LLines.Count then
      LEnd := LLines.Count - 1;

    TConsole.PrintLn('');
    for LI := LStart to LEnd do
    begin
      // Lines in TStringList are 0-based; source lines are 1-based
      if (LI + 1) = LSourceLine then
        LArrow := COLOR_YELLOW + '>>'
      else
        LArrow := '  ';
      TConsole.PrintLn('%s%4d: %s', [LArrow, LI + 1, LLines[LI]]);
    end;
    TConsole.PrintLn('');
  finally
    LLines.Free();
  end;
end;

procedure TMyrDebugREPL.SendBreakpointsForFile(const ASourceFile: string);
var
  LLines: TList<Integer>;
  LI: Integer;
  LBP: TMyrREPLBreakpoint;
begin
  // Collect all lines for this file
  LLines := TList<Integer>.Create();
  try
    for LI := 0 to FBreakpoints.Count - 1 do
    begin
      LBP := FBreakpoints[LI];
      if SameText(LBP.SourceFile, ASourceFile) then
        LLines.Add(LBP.SourceLine);
    end;

    // Send to server (empty array clears breakpoints for that file)
    FClient.SetBreakpoints(ASourceFile, LLines.ToArray());
  finally
    LLines.Free();
  end;
end;

procedure TMyrDebugREPL.LoadBreakpointsFromMdbg(const APath: string);
var
  LSourceMap: TMyrSourceMap;
  LBreakpoints: TArray<TMyrSourceMapBreakpoint>;
  LBP: TMyrREPLBreakpoint;
  LI: Integer;
begin
  if not TFile.Exists(APath) then
    Exit;

  LSourceMap := TMyrSourceMap.Create();
  try
    LSourceMap.LoadFromFile(APath);
    LBreakpoints := LSourceMap.GetBreakpoints();
    for LI := 0 to Length(LBreakpoints) - 1 do
    begin
      LBP.SourceFile := LSourceMap.GetSourceFile(LBreakpoints[LI].SourceFileIndex);
      LBP.SourceLine := LBreakpoints[LI].SourceLine;
      LBP.Verified := False;
      if (LBP.SourceFile <> '') and (LBP.SourceLine > 0) then
        FBreakpoints.Add(LBP);
    end;

    if FBreakpoints.Count > 0 then
      TConsole.PrintLn('Loaded %d breakpoint(s) from %s',
        [FBreakpoints.Count, TPath.GetFileName(APath)]);
  finally
    LSourceMap.Free();
  end;
end;

procedure TMyrDebugREPL.Run(const AExePath: string; const APort: Integer);
var
  LCommand: string;
  LFiles: TDictionary<string, Boolean>;
  LBP: TMyrREPLBreakpoint;
  LKey: string;
begin
  FExePath := AExePath;
  FPort := APort;

  if not TFile.Exists(FExePath) then
  begin
    TConsole.PrintLn(COLOR_RED + 'Executable not found: ' + FExePath);
    Exit;
  end;

  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_CYAN + '=== Myrissa Debug REPL ===');
  TConsole.PrintLn('Executable: %s', [FExePath]);
  TConsole.PrintLn('');

  // Start server + client
  StartSession();

  // DAP handshake
  if not DoDAHandshake() then
  begin
    StopSession();
    Exit;
  end;

  // Set up callbacks
  FClient.OnStopped :=
    procedure(const AReason: string; const AThreadId: Integer)
    begin
      TConsole.PrintLn('  [stopped] %s (thread %d)', [AReason, AThreadId]);
    end;
  FClient.OnExited :=
    procedure(const AExitCode: Integer)
    begin
      TConsole.PrintLn('  [exited] code %d', [AExitCode]);
    end;
  FClient.OnOutput :=
    procedure(const AOutput: string)
    begin
      TConsole.Print(AOutput);
    end;

  // Load embedded @breakpoint directives from .mdbg source map
  LoadBreakpointsFromMdbg(TPath.ChangeExtension(FExePath, MYR_DBGFILE_EXT));

  // Send all breakpoints to server (grouped by file)
  if FBreakpoints.Count > 0 then
  begin
    LFiles := TDictionary<string, Boolean>.Create();
    try
      for LBP in FBreakpoints do
        LFiles.AddOrSetValue(LBP.SourceFile, True);
      for LKey in LFiles.Keys do
        SendBreakpointsForFile(LKey);
    finally
      LFiles.Free();
    end;
  end;

  // Start execution
  if not FClient.ConfigurationDone() then
  begin
    TConsole.PrintLn(COLOR_RED + 'ConfigurationDone failed: ' +
      FClient.GetLastError());
    StopSession();
    Exit;
  end;

  TConsole.PrintLn(COLOR_GREEN + 'Running...');

  // Wait for first stop (breakpoint or exit)
  FClient.ProcessPendingEvents(FTimeoutContinueMS);

  if FClient.State = dcsStopped then
  begin
    ShowSourceContext();
    TConsole.PrintLn(COLOR_CYAN + '=== INTERACTIVE REPL ===');
    ShowHelp();
    TConsole.PrintLn('');
  end
  else if FClient.State = dcsExited then
  begin
    TConsole.PrintLn(COLOR_YELLOW + 'Program exited without stopping.');
    StopSession();
    Exit;
  end;

  // Main REPL loop
  FRunning := True;
  while FRunning do
  begin
    Write(FPrompt);
    ReadLn(LCommand);
    LCommand := Trim(LCommand);
    ProcessCommand(LCommand);
  end;

  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_GREEN + 'REPL session complete.');
  StopSession();
end;

procedure TMyrDebugREPL.Stop();
begin
  FRunning := False;
end;

procedure TMyrDebugREPL.ProcessCommand(const ACommand: string);
begin
  if ACommand = '' then
    Exit;

  if ACommand = 'quit' then
    FRunning := False
  else if (ACommand = 'h') or (ACommand = 'help') then
    ShowHelp()
  else if ACommand.StartsWith('b ') then
    HandleSetBreakpoint(ACommand)
  else if ACommand = 'bl' then
    HandleListBreakpoints()
  else if ACommand.StartsWith('bd ') then
    HandleDeleteBreakpoint(ACommand)
  else if ACommand = 'bc' then
    HandleClearBreakpoints()
  else if ACommand = 'bt' then
    HandleBacktrace()
  else if ACommand = 'locals' then
    HandleLocals()
  else if ACommand.StartsWith('p ') then
    HandlePrint(ACommand)
  else if ACommand = 'c' then
    HandleContinue()
  else if ACommand = 'n' then
    HandleNext()
  else if ACommand = 's' then
    HandleStepInto()
  else if ACommand = 'finish' then
    HandleStepOut()
  else if ACommand = 'r' then
    HandleRestart()
  else if ACommand.StartsWith('file ') then
    HandleFile(ACommand)
  else if ACommand.StartsWith('verbose ') then
    HandleVerbose(ACommand)
  else if ACommand = 'threads' then
    HandleThreads()
  else if ACommand = 'src' then
    ShowSourceContext()
  else
    TConsole.PrintLn(COLOR_RED + 'Unknown command: ' + ACommand);
end;

procedure TMyrDebugREPL.ShowHelp();
begin
  TConsole.PrintLn('Commands:');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'h, help         - Show this help');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'b <file>:<line> - Set breakpoint');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'bl              - List breakpoints');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'bd <id>         - Delete breakpoint by ID');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'bc              - Clear all breakpoints');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'bt              - Show call stack (backtrace)');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'locals          - Show local variables');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'p <expr>        - Print/evaluate expression');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'c               - Continue execution');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'n               - Next (step over)');
  TConsole.PrintLn('  ' + COLOR_CYAN + 's               - Step into');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'finish          - Step out');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'r               - Restart program');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'file <path>     - Load different executable');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'src             - Show source context');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'threads         - Show threads');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'verbose on/off  - Toggle DAP message logging');
  TConsole.PrintLn('  ' + COLOR_CYAN + 'quit            - Exit REPL');
end;

procedure TMyrDebugREPL.HandleSetBreakpoint(const ACommand: string);
var
  LColonPos: Integer;
  LFile: string;
  LLine: Integer;
  LBP: TMyrREPLBreakpoint;
begin
  // Format: b <file>:<line>
  LColonPos := Pos(':', ACommand);
  if LColonPos > 3 then
  begin
    LFile := Trim(Copy(ACommand, 3, LColonPos - 3));
    LLine := StrToIntDef(Trim(Copy(ACommand, LColonPos + 1, MaxInt)), -1);

    if (LFile <> '') and (LLine > 0) then
    begin
      LBP.SourceFile := LFile;
      LBP.SourceLine := LLine;
      LBP.Verified := False;
      FBreakpoints.Add(LBP);
      SendBreakpointsForFile(LFile);
      TConsole.PrintLn(COLOR_GREEN + 'Breakpoint set at %s:%d',
        [LFile, LLine]);
    end
    else
      TConsole.PrintLn(COLOR_RED + 'Invalid format. Use: b <file>:<line>');
  end
  else
    TConsole.PrintLn(COLOR_RED + 'Invalid format. Use: b <file>:<line>');
end;

procedure TMyrDebugREPL.HandleListBreakpoints();
var
  LI: Integer;
  LBP: TMyrREPLBreakpoint;
begin
  if FBreakpoints.Count = 0 then
  begin
    TConsole.PrintLn('No breakpoints set');
    Exit;
  end;

  TConsole.PrintLn('Breakpoints (%d):', [FBreakpoints.Count]);
  for LI := 0 to FBreakpoints.Count - 1 do
  begin
    LBP := FBreakpoints[LI];
    TConsole.PrintLn('  #%d: %s:%d', [LI + 1, LBP.SourceFile, LBP.SourceLine]);
  end;
end;

procedure TMyrDebugREPL.HandleDeleteBreakpoint(const ACommand: string);
var
  LIndex: Integer;
  LBP: TMyrREPLBreakpoint;
  LFile: string;
begin
  // Format: bd <id> (1-based)
  LIndex := StrToIntDef(Trim(Copy(ACommand, 4, MaxInt)), -1);
  if (LIndex < 1) or (LIndex > FBreakpoints.Count) then
  begin
    TConsole.PrintLn(COLOR_RED + 'Invalid breakpoint ID');
    Exit;
  end;

  LBP := FBreakpoints[LIndex - 1];
  LFile := LBP.SourceFile;
  FBreakpoints.Delete(LIndex - 1);

  // Re-send remaining breakpoints for that file
  SendBreakpointsForFile(LFile);
  TConsole.PrintLn(COLOR_GREEN + 'Breakpoint #%d deleted', [LIndex]);
end;

procedure TMyrDebugREPL.HandleClearBreakpoints();
var
  LFiles: TDictionary<string, Boolean>;
  LBP: TMyrREPLBreakpoint;
  LKey: string;
begin
  // Collect unique files before clearing
  LFiles := TDictionary<string, Boolean>.Create();
  try
    for LBP in FBreakpoints do
      LFiles.AddOrSetValue(LBP.SourceFile, True);

    FBreakpoints.Clear();

    // Send empty breakpoint sets for each file
    for LKey in LFiles.Keys do
      FClient.SetBreakpoints(LKey, []);
  finally
    LFiles.Free();
  end;

  TConsole.PrintLn(COLOR_GREEN + 'All breakpoints cleared');
end;

procedure TMyrDebugREPL.HandleBacktrace();
var
  LFrames: TArray<TMyrDAPClientStackFrame>;
  LI: Integer;
begin
  if FClient.State <> dcsStopped then
  begin
    TConsole.PrintLn(COLOR_RED + 'Not stopped');
    Exit;
  end;

  LFrames := FClient.GetCallStack();
  if Length(LFrames) = 0 then
  begin
    TConsole.PrintLn('No stack frames');
    Exit;
  end;

  TConsole.PrintLn('Call stack (%d frames):', [Length(LFrames)]);
  for LI := 0 to High(LFrames) do
    TConsole.PrintLn('  #%d: %s at %s:%d',
      [LI, LFrames[LI].FunctionName, LFrames[LI].SourceFile, LFrames[LI].SourceLine]);
end;

procedure TMyrDebugREPL.HandleLocals();
var
  LFrames: TArray<TMyrDAPClientStackFrame>;
  LScopes: TArray<TMyrDAPClientScope>;
  LVars: TArray<TMyrDAPClientVariable>;
  LI: Integer;
  LJ: Integer;
begin
  if FClient.State <> dcsStopped then
  begin
    TConsole.PrintLn(COLOR_RED + 'Not stopped');
    Exit;
  end;

  LFrames := FClient.GetCallStack();
  if Length(LFrames) = 0 then
  begin
    TConsole.PrintLn(COLOR_RED + 'No stack frames');
    Exit;
  end;

  // Get scopes for top frame
  LScopes := FClient.GetScopes(LFrames[0].FrameID);
  if Length(LScopes) = 0 then
  begin
    TConsole.PrintLn('No scopes available');
    Exit;
  end;

  // Get variables for each scope
  for LI := 0 to High(LScopes) do
  begin
    TConsole.PrintLn('%s:', [LScopes[LI].ScopeName]);
    LVars := FClient.GetVariables(LScopes[LI].VariablesReference);
    if Length(LVars) = 0 then
      TConsole.PrintLn('  (none)')
    else
    begin
      for LJ := 0 to High(LVars) do
      begin
        if LVars[LJ].VarType <> '' then
          TConsole.PrintLn('  %s (%s) = %s',
            [LVars[LJ].VarName, LVars[LJ].VarType, LVars[LJ].VarValue])
        else
          TConsole.PrintLn('  %s = %s',
            [LVars[LJ].VarName, LVars[LJ].VarValue]);
      end;
    end;
  end;
end;

procedure TMyrDebugREPL.HandlePrint(const ACommand: string);
var
  LExpr: string;
  LResult: string;
begin
  // Extract expression after 'p '
  LExpr := Trim(Copy(ACommand, 3, MaxInt));
  if LExpr = '' then
  begin
    TConsole.PrintLn(COLOR_YELLOW + 'Usage: p <variable>');
    Exit;
  end;

  if FClient.State <> dcsStopped then
  begin
    TConsole.PrintLn(COLOR_RED + 'Not stopped');
    Exit;
  end;

  LResult := FClient.Evaluate(LExpr);
  if LResult <> '' then
    TConsole.PrintLn('%s = %s', [LExpr, LResult])
  else
  begin
    if FClient.HasError() then
      TConsole.PrintLn(COLOR_RED + '%s', [FClient.GetLastError()])
    else
      TConsole.PrintLn(COLOR_YELLOW + 'Variable ''%s'' not found', [LExpr]);
  end;
end;

procedure TMyrDebugREPL.HandleContinue();
begin
  if FClient.State <> dcsStopped then
  begin
    TConsole.PrintLn(COLOR_RED + 'Not stopped');
    Exit;
  end;

  TConsole.PrintLn('Continuing...');
  if FClient.Continue() then
  begin
    FClient.ProcessPendingEvents(FTimeoutContinueMS);
    if FClient.State = dcsStopped then
    begin
      TConsole.PrintLn(COLOR_GREEN + 'Stopped');
      ShowSourceContext();
    end
    else if FClient.State = dcsExited then
      TConsole.PrintLn(COLOR_YELLOW + 'Program exited');
  end
  else
    TConsole.PrintLn(COLOR_RED + 'Continue failed: ' + FClient.GetLastError());
end;

procedure TMyrDebugREPL.HandleNext();
begin
  if FClient.State <> dcsStopped then
  begin
    TConsole.PrintLn(COLOR_RED + 'Not stopped');
    Exit;
  end;

  TConsole.PrintLn('Stepping over...');
  if FClient.StepOver() then
  begin
    FClient.ProcessPendingEvents(FTimeoutStepMS);
    if FClient.State = dcsStopped then
      ShowSourceContext()
    else if FClient.State = dcsExited then
      TConsole.PrintLn(COLOR_YELLOW + 'Program exited');
  end
  else
    TConsole.PrintLn(COLOR_RED + 'Step failed: ' + FClient.GetLastError());
end;

procedure TMyrDebugREPL.HandleStepInto();
begin
  if FClient.State <> dcsStopped then
  begin
    TConsole.PrintLn(COLOR_RED + 'Not stopped');
    Exit;
  end;

  TConsole.PrintLn('Stepping into...');
  if FClient.StepIn() then
  begin
    FClient.ProcessPendingEvents(FTimeoutStepMS);
    if FClient.State = dcsStopped then
      ShowSourceContext()
    else if FClient.State = dcsExited then
      TConsole.PrintLn(COLOR_YELLOW + 'Program exited');
  end
  else
    TConsole.PrintLn(COLOR_RED + 'Step failed: ' + FClient.GetLastError());
end;

procedure TMyrDebugREPL.HandleStepOut();
begin
  if FClient.State <> dcsStopped then
  begin
    TConsole.PrintLn(COLOR_RED + 'Not stopped');
    Exit;
  end;

  TConsole.PrintLn('Stepping out...');
  if FClient.StepOut() then
  begin
    FClient.ProcessPendingEvents(FTimeoutStepMS);
    if FClient.State = dcsStopped then
      ShowSourceContext()
    else if FClient.State = dcsExited then
      TConsole.PrintLn(COLOR_YELLOW + 'Program exited');
  end
  else
    TConsole.PrintLn(COLOR_RED + 'Step failed: ' + FClient.GetLastError());
end;

procedure TMyrDebugREPL.HandleRestart();
var
  LSavedBreakpoints: TList<TMyrREPLBreakpoint>;
  LBP: TMyrREPLBreakpoint;
  LFiles: TDictionary<string, Boolean>;
  LKey: string;
begin
  TConsole.PrintLn('Restarting program...');

  // Save breakpoints before teardown
  LSavedBreakpoints := TList<TMyrREPLBreakpoint>.Create();
  try
    for LBP in FBreakpoints do
      LSavedBreakpoints.Add(LBP);

    // Full teardown
    StopSession();

    // Restore breakpoints
    FBreakpoints.Clear();
    for LBP in LSavedBreakpoints do
      FBreakpoints.Add(LBP);
  finally
    LSavedBreakpoints.Free();
  end;

  // Re-create server + client
  StartSession();

  // Re-do DAP handshake
  if not DoDAHandshake() then
  begin
    TConsole.PrintLn(COLOR_RED + 'Restart failed during handshake');
    StopSession();
    Exit;
  end;

  // Re-set callbacks
  FClient.OnStopped :=
    procedure(const AReason: string; const AThreadId: Integer)
    begin
      TConsole.PrintLn('  [stopped] %s (thread %d)', [AReason, AThreadId]);
    end;
  FClient.OnExited :=
    procedure(const AExitCode: Integer)
    begin
      TConsole.PrintLn('  [exited] code %d', [AExitCode]);
    end;
  FClient.OnOutput :=
    procedure(const AOutput: string)
    begin
      TConsole.Print(AOutput);
    end;

  // Re-send all breakpoints (grouped by file)
  if FBreakpoints.Count > 0 then
  begin
    LFiles := TDictionary<string, Boolean>.Create();
    try
      for LBP in FBreakpoints do
        LFiles.AddOrSetValue(LBP.SourceFile, True);
      for LKey in LFiles.Keys do
        SendBreakpointsForFile(LKey);
    finally
      LFiles.Free();
    end;
    TConsole.PrintLn('Restored %d breakpoint(s)', [FBreakpoints.Count]);
  end;

  // Start execution
  if not FClient.ConfigurationDone() then
  begin
    TConsole.PrintLn(COLOR_RED + 'ConfigurationDone failed: ' +
      FClient.GetLastError());
    Exit;
  end;

  TConsole.PrintLn(COLOR_GREEN + 'Program restarted!');

  // Wait for first stop
  FClient.ProcessPendingEvents(FTimeoutContinueMS);

  if FClient.State = dcsStopped then
    ShowSourceContext()
  else if FClient.State = dcsExited then
    TConsole.PrintLn(COLOR_YELLOW + 'Program exited');
end;

procedure TMyrDebugREPL.HandleFile(const ACommand: string);
var
  LPath: string;
begin
  LPath := Trim(Copy(ACommand, 6, MaxInt));

  if not TFile.Exists(LPath) then
  begin
    TConsole.PrintLn(COLOR_RED + 'File not found: ' + LPath);
    Exit;
  end;

  FExePath := LPath;
  FBreakpoints.Clear();
  TConsole.PrintLn(COLOR_GREEN + 'Loaded: ' + FExePath);
  TConsole.PrintLn('Breakpoints cleared. Use ''r'' to run.');
end;

procedure TMyrDebugREPL.HandleVerbose(const ACommand: string);
begin
  if ACommand = 'verbose on' then
  begin
    FVerboseLogging := True;
    FClient.VerboseLogging := True;
    if FServer.GetDAPServer() <> nil then
      FServer.GetDAPServer().VerboseLogging := True;
    TConsole.PrintLn(COLOR_GREEN + 'Verbose logging enabled');
  end
  else if ACommand = 'verbose off' then
  begin
    FVerboseLogging := False;
    FClient.VerboseLogging := False;
    if FServer.GetDAPServer() <> nil then
      FServer.GetDAPServer().VerboseLogging := False;
    TConsole.PrintLn(COLOR_GREEN + 'Verbose logging disabled');
  end
  else
    TConsole.PrintLn(COLOR_RED + 'Usage: verbose on|off');
end;

procedure TMyrDebugREPL.HandleThreads();
begin
  // Myrissa is single-threaded — hardcode response
  TConsole.PrintLn('Threads (1):');
  TConsole.PrintLn('  Thread 1: main');
end;

end.
