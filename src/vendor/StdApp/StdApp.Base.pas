{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Base - Foundation types and base class

  Defines the core abstractions that every StdApp unit builds on: the
  shared error system (TErrors), source location tracking (TSourceRange),
  the generic callback wrapper (TCallback<T>), and TBaseObject -- the
  mandatory base class for all StdApp and project classes.

  Key types:
  - TCallback<T>: Generic record wrapping a callback reference + user data
  - TSourceRange: File/line/column range for error locations
  - TError / TErrorSeverity: Structured error record with severity levels
  - TErrors: Accumulating error collection with max-error cutoff and
    optional raise-on-error behavior
  - EStdAppException: Exception class carrying a TError payload
  - TBaseObject: Base class providing shared FErrors, FStatusCallback,
    virtual Dump/InitConfig/LoadConfig/SaveConfig hooks

  Dependencies: StdApp.Resources
  Notes: Every class in the library descends from TBaseObject, never TObject.
===============================================================================}

unit StdApp.Base;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Resources;

const
  DEFAULT_MAX_ERRORS = 1;

type

  { TCallback }
  TCallback<T> = record
    Callback: T;
    UserData: Pointer;
    function IsAssigned(): Boolean;
  end;

  { TErrorSeverity }
  TErrorSeverity = (
    esHint,
    esWarning,
    esError,
    esFatal
  );

  { TSourceRange }
  TSourceRange = record
    Filename: string;
    StartLine: UInt64;
    StartColumn: UInt64;
    EndLine: UInt64;
    EndColumn: UInt64;
    StartByteOffset: UInt64;
    EndByteOffset: UInt64;

    procedure Clear();
    function IsEmpty(): Boolean;
    function ToPointString(): string;
    function ToRangeString(): string;
  end;

  { TErrorRelated }
  TErrorRelated = record
    Range: TSourceRange;
    Msg: string;
  end;

  { TError }
  TError = record
    Range: TSourceRange;
    Severity: TErrorSeverity;
    Code: string;
    Message: string;
    Related: TArray<TErrorRelated>;

    function GetSeverityString(): string;
    function ToIDEString(): string;
    function ToFullString(): string;
  end;

  { EStdAppException }
  EStdAppException = class(Exception)
    ErrorInfo: TError;
    constructor Create(const AError: TError); reintroduce;
  end;

  { TErrorNotify }
  TErrorNotify = reference to procedure(const AError: TError; const AUserData: Pointer);

  { TErrors }
  TErrors = class
  private
    FItems: TList<TError>;
    FMaxErrors: Integer;
    FOnAdd: TErrorNotify;
    FRaiseOnError: Boolean;

    function CountErrors(): Integer;

  public
    constructor Create(); virtual;
    destructor Destroy(); override;

    // Full location with range
    procedure Add(
      const ARange: TSourceRange;
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AUserData: Pointer=nil
    ); overload;

    procedure Add(
      const ARange: TSourceRange;
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AArgs: array of const;
      const AUserData: Pointer=nil
    ); overload;

    // Point location (start = end)
    procedure Add(
      const AFilename: string;
      const ALine: UInt64;
      const AColumn: UInt64;
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AUserData: Pointer=nil
    ); overload;

    procedure Add(
      const AFilename: string;
      const ALine: UInt64;
      const AColumn: UInt64;
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AArgs: array of const;
      const AUserData: Pointer=nil
    ); overload;

    // No location
    procedure Add(
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AUserData: Pointer=nil
    ); overload;

    procedure Add(
      const ASeverity: TErrorSeverity;
      const ACode: string;
      const AMessage: string;
      const AArgs: array of const;
      const AUserData: Pointer=nil
    ); overload;

    // Add related info to most recent error
    procedure AddRelated(
      const ARange: TSourceRange;
      const AMessage: string
    ); overload;

    procedure AddRelated(
      const ARange: TSourceRange;
      const AMessage: string;
      const AArgs: array of const
    ); overload;

    function HasHints(): Boolean;
    function HasWarnings(): Boolean;
    function HasErrors(): Boolean;
    function HasFatal(): Boolean;
    function Count(): Integer;
    function ErrorCount(): Integer;
    function WarningCount(): Integer;
    function ReachedMaxErrors(): Boolean;
    procedure Clear();
    procedure TruncateTo(const ACount: Integer);

    function GetItems(): TList<TError>;
    function GetMaxErrors(): Integer;
    procedure SetMaxErrors(const AMaxErrors: Integer);
    function ToString(): string; override;

    property OnAdd: TErrorNotify read FOnAdd write FOnAdd;
    property RaiseOnError: Boolean read FRaiseOnError write FRaiseOnError;
  end;

  { TStatusCallback }
  TStatusCallback = reference to procedure(const AText: string; const AUserData: Pointer);


  { TBaseObject }
  TBaseObject = class
  protected
    FErrors: TErrors;
    FOwnsErrors: Boolean;
    FStatusCallback: TCallback<TStatusCallback>;
  public
    constructor Create(); virtual;
    destructor Destroy(); override;
    function Dump(const AId: Integer = 0): string; virtual;
    procedure InitConfig(); virtual;
    procedure LoadConfig(const AFilename: string); virtual;
    procedure SaveConfig(const AFilename: string); virtual;
    procedure Status(const AText: string); overload;
    procedure Status(const AText: string; const AArgs: array of const); overload;
    procedure Status(const AEnabled: Boolean; const AText: string; const AArgs: array of const); overload;
    function  GetStatusCallback(): TStatusCallback;
    procedure SetStatusCallback(const ACallback: TStatusCallback; const AUserData: Pointer = nil); virtual;
    procedure SetErrors(const AErrors: TErrors); virtual;
    function  GetErrors(): TErrors;
    procedure PrintErrors();
  end;

implementation

uses
  StdApp.Utils,
  StdApp.Console;

{ TCallback<T> }

function TCallback<T>.IsAssigned(): Boolean;
begin
  Result := PPointer(@Callback)^ <> nil;
end;

{ TSourceRange }
procedure TSourceRange.Clear();
begin
  Filename := '';
  StartLine := 0;
  StartColumn := 0;
  EndLine := 0;
  EndColumn := 0;
  StartByteOffset := 0;
  EndByteOffset := 0;
end;

function TSourceRange.IsEmpty(): Boolean;
begin
  Result := (Filename = '') and (StartLine = 0) and (StartColumn = 0);
end;

function TSourceRange.ToPointString(): string;
begin
  if IsEmpty() then
    Result := ''
  else if (StartLine = 0) and (StartColumn = 0) then
    Result := Filename
  else
    Result := Format('%s(%d,%d)', [Filename, StartLine, StartColumn]);
end;

function TSourceRange.ToRangeString(): string;
begin
  if IsEmpty() then
    Result := ''
  else if (StartLine = EndLine) and (StartColumn = EndColumn) then
    Result := Format('%s(%d,%d)', [Filename, StartLine, StartColumn])
  else if StartLine = EndLine then
    Result := Format('%s(%d,%d-%d)', [Filename, StartLine, StartColumn, EndColumn])
  else
    Result := Format('%s(%d,%d)-(%d,%d)', [Filename, StartLine, StartColumn, EndLine, EndColumn]);
end;

{ TError }

function TError.GetSeverityString(): string;
begin
  case Severity of
    esHint:    Result := RSSeverityHint;
    esWarning: Result := RSSeverityWarning;
    esError:   Result := RSSeverityError;
    esFatal:   Result := RSSeverityFatal;
  else
    Result := RSSeverityUnknown;
  end;
end;

function TError.ToIDEString(): string;
begin
  if Range.IsEmpty() then
    Result := Format(RSErrorFormatSimple, [GetSeverityString(), Code, Message])
  else
    Result := Format(RSErrorFormatWithLocation, [Range.ToPointString(), GetSeverityString(), Code, Message]);
end;

function TError.ToFullString(): string;
var
  LBuilder: TStringBuilder;
  LI: Integer;
begin
  LBuilder := TStringBuilder.Create();
  try
    LBuilder.AppendLine(ToIDEString());

    for LI := 0 to High(Related) do
    begin
      if Related[LI].Range.IsEmpty() then
        LBuilder.AppendFormat(RSErrorFormatRelatedSimple, [RSSeverityNote, Related[LI].Msg])
      else
        LBuilder.AppendFormat(RSErrorFormatRelatedWithLocation, [Related[LI].Range.ToPointString(), RSSeverityNote, Related[LI].Msg]);
      LBuilder.AppendLine();
    end;

    Result := LBuilder.ToString().TrimRight();
  finally
    LBuilder.Free();
  end;
end;

{ EStdAppException }

constructor EStdAppException.Create(const AError: TError);
begin
  inherited Create(AError.ToFullString());
  ErrorInfo := AError;
end;

{ TErrors }

constructor TErrors.Create();
begin
  inherited;

  FItems := TList<TError>.Create();
  FMaxErrors := DEFAULT_MAX_ERRORS;
  FRaiseOnError := False;
end;

destructor TErrors.Destroy();
begin
  FItems.Free();

  inherited;
end;

function TErrors.CountErrors(): Integer;
var
  LError: TError;
begin
  Result := 0;
  for LError in FItems do
  begin
    if LError.Severity in [esError, esFatal] then
      Inc(Result);
  end;
end;

procedure TErrors.Add(
  const ARange: TSourceRange;
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AUserData: Pointer
);
var
  LError: TError;
  LRange: TSourceRange;
begin
  // Stop adding errors after limit reached (except fatal)
  if (ASeverity = esError) and (CountErrors() >= FMaxErrors) then
    Exit;

  // Keep filename as provided -- caller is responsible for full paths
  LRange := ARange;
  if LRange.Filename <> '' then
    LRange.Filename := LRange.Filename.Replace('\', '/');

  LError.Range := LRange;
  LError.Severity := ASeverity;
  LError.Code := ACode;
  LError.Message := AMessage;
  SetLength(LError.Related, 0);

  FItems.Add(LError);

  // Notify listener (engine error handler)
  if Assigned(FOnAdd) then
    FOnAdd(LError, AUserData);

  // Raise on error or fatal (unless suppressed)
  if FRaiseOnError and (ASeverity in [esError, esFatal]) then
    raise EStdAppException.Create(LError);
end;

procedure TErrors.Add(
  const ARange: TSourceRange;
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AArgs: array of const;
  const AUserData: Pointer
);
begin
  Add(ARange, ASeverity, ACode, Format(AMessage, AArgs), AUserData);
end;

procedure TErrors.Add(
  const AFilename: string;
  const ALine: UInt64;
  const AColumn: UInt64;
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AUserData: Pointer
);
var
  LRange: TSourceRange;
begin
  LRange.Filename := AFilename;
  LRange.StartLine := ALine;
  LRange.StartColumn := AColumn;
  LRange.EndLine := ALine;
  LRange.EndColumn := AColumn;

  Add(LRange, ASeverity, ACode, AMessage, AUserData);
end;

procedure TErrors.Add(
  const AFilename: string;
  const ALine: UInt64;
  const AColumn: UInt64;
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AArgs: array of const;
  const AUserData: Pointer
);
begin
  Add(AFilename, ALine, AColumn, ASeverity, ACode, Format(AMessage, AArgs), AUserData);
end;

procedure TErrors.Add(
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AUserData: Pointer
);
var
  LRange: TSourceRange;
begin
  LRange.Clear();
  Add(LRange, ASeverity, ACode, AMessage, AUserData);
end;

procedure TErrors.Add(
  const ASeverity: TErrorSeverity;
  const ACode: string;
  const AMessage: string;
  const AArgs: array of const;
  const AUserData: Pointer
);
begin
  Add(ASeverity, ACode, Format(AMessage, AArgs), AUserData);
end;

procedure TErrors.AddRelated(
  const ARange: TSourceRange;
  const AMessage: string
);
var
  LError: TError;
  LRelated: TErrorRelated;
  LLen: Integer;
begin
  if FItems.Count = 0 then
    Exit;

  LError := FItems[FItems.Count - 1];

  LRelated.Range := ARange;
  LRelated.Msg := AMessage;

  LLen := Length(LError.Related);
  SetLength(LError.Related, LLen + 1);
  LError.Related[LLen] := LRelated;

  FItems[FItems.Count - 1] := LError;
end;

procedure TErrors.AddRelated(
  const ARange: TSourceRange;
  const AMessage: string;
  const AArgs: array of const
);
begin
  AddRelated(ARange, Format(AMessage, AArgs));
end;

function TErrors.HasHints(): Boolean;
var
  LError: TError;
begin
  Result := False;
  for LError in FItems do
  begin
    if LError.Severity = esHint then
      Exit(True);
  end;
end;

function TErrors.HasWarnings(): Boolean;
var
  LError: TError;
begin
  Result := False;
  for LError in FItems do
  begin
    if LError.Severity = esWarning then
      Exit(True);
  end;
end;

function TErrors.HasErrors(): Boolean;
var
  LError: TError;
begin
  Result := False;
  for LError in FItems do
  begin
    if LError.Severity in [esError, esFatal] then
      Exit(True);
  end;
end;

function TErrors.HasFatal(): Boolean;
var
  LError: TError;
begin
  Result := False;
  for LError in FItems do
  begin
    if LError.Severity = esFatal then
      Exit(True);
  end;
end;

function TErrors.Count(): Integer;
begin
  Result := FItems.Count;
end;

function TErrors.ErrorCount(): Integer;
begin
  Result := CountErrors();
end;

function TErrors.WarningCount(): Integer;
var
  LError: TError;
begin
  Result := 0;
  for LError in FItems do
  begin
    if LError.Severity = esWarning then
      Inc(Result);
  end;
end;

function TErrors.ReachedMaxErrors(): Boolean;
begin
  Result := CountErrors() >= FMaxErrors;
end;

procedure TErrors.Clear();
begin
  FItems.Clear();
end;

procedure TErrors.TruncateTo(const ACount: Integer);
begin
  while FItems.Count > ACount do
    FItems.Delete(FItems.Count - 1);
end;

function TErrors.GetItems(): TList<TError>;
begin
  Result := FItems;
end;

function TErrors.GetMaxErrors(): Integer;
begin
  Result := FMaxErrors;
end;

procedure TErrors.SetMaxErrors(const AMaxErrors: Integer);
begin
  FMaxErrors := AMaxErrors;
end;

function TErrors.ToString(): string;
var
  LBuilder: TStringBuilder;
  LI: Integer;
begin
  LBuilder := TStringBuilder.Create();
  try
    for LI := 0 to FItems.Count - 1 do
    begin
      if LI > 0 then
        LBuilder.AppendLine();
      LBuilder.Append(FItems[LI].ToFullString());
    end;
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

{ TCbrBaseObject }

constructor TBaseObject.Create();
begin
  inherited;
  FErrors := TErrors.Create();
  FOwnsErrors := True;
end;

destructor TBaseObject.Destroy();
begin
  if FOwnsErrors and (FErrors <> nil) then
    FErrors.Free();
  FErrors := nil;
  inherited;
end;

function TBaseObject.Dump(const AId: Integer): string;
begin
  Result := '';
end;

procedure TBaseObject.InitConfig();
begin
end;

procedure TBaseObject.LoadConfig(const AFilename: string);
begin
end;

procedure TBaseObject.SaveConfig(const AFilename: string);
begin
end;


procedure TBaseObject.Status(const AText: string);
begin
  if FStatusCallback.IsAssigned() then
    FStatusCallback.Callback(AText, FStatusCallback.UserData);
end;

procedure TBaseObject.Status(const AText: string; const AArgs: array of const);
begin
  Status(Format(AText, AArgs));
end;

procedure TBaseObject.Status(const AEnabled: Boolean; const AText: string; const AArgs: array of const);
begin
  if AEnabled then
    Status(Format(AText, AArgs));
end;

function TBaseObject.GetStatusCallback(): TStatusCallback;
begin
  Result := FStatusCallback.Callback;
end;

procedure TBaseObject.SetStatusCallback(const ACallback: TStatusCallback; const AUserData: Pointer);
begin
  FStatusCallback.Callback := ACallback;
  FStatusCallback.UserData := AUserData;
end;

procedure TBaseObject.SetErrors(const AErrors: TErrors);
begin
  // Self-reference guard — prevents double-free if caller does
  // Obj.SetErrors(Obj.GetErrors()).
  if AErrors = FErrors then
    Exit;

  // Release current instance if we own it.
  if FOwnsErrors and (FErrors <> nil) then
    FErrors.Free();

  if AErrors = nil then
  begin
    // Reset to self-owned new instance.
    FErrors := TErrors.Create();
    FOwnsErrors := True;
  end
  else
  begin
    // Borrow external — caller retains ownership.
    FErrors := AErrors;
    FOwnsErrors := False;
  end;
end;

function TBaseObject.GetErrors(): TErrors;
begin
  Result := FErrors;
end;

procedure TBaseObject.PrintErrors();
var
  LItems: TList<TError>;
  LI: Integer;
  LErr: TError;
  LColor: string;
  LLabel: string;
begin
  LItems := FErrors.GetItems();
  if LItems.Count = 0 then
    Exit;

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

end.
