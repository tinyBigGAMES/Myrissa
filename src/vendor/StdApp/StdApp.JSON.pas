{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.JSON - Fluent JSON builder, reader, and writer

  Full-featured JSON manipulation class with fluent API for building,
  navigating, and serializing JSON structures. Supports factory loading
  from files, strings, and streams, dot-path navigation, iteration,
  and pretty-printing. View-based design avoids deep copies during
  navigation.

  Key types:
  - TJSON: Fluent builder (Add, BeginObject/Array, EndObject/Array),
    navigation (Get, Has, Keys, Items), serialization (ToString,
    ToPrettyString, SaveToFile), factory methods (FromFile, FromString)
  - TJSONEnumerator: for..in support over arrays and objects
  - TJSONPair: Name/value pair record for object iteration

  Dependencies: none (System.JSON only)
===============================================================================}

unit StdApp.JSON;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections;

type
  TJSON = class;

  { TJSONCallback }
  TJSONCallback = reference to procedure(const AItem: TJSON; const AUserData: Pointer);

  { TJSONPair }
  TJSONPair = record
    NodeName: string;
    Value: TJSON;
  end;

  { TJSONEnumerator }
  TJSONEnumerator = class
  private
    FJSON: TJSON;
    FIndex: Integer;
    FItems: TArray<TJSON>;
  public
    constructor Create(const AJSON: TJSON);
    function MoveNext(): Boolean;
    function GetCurrent(): TJSON;
    property Current: TJSON read GetCurrent;
  end;

  { TJSON }
  TJSON = class
  private
    FValue: System.JSON.TJSONValue;
    FOwnsValue: Boolean;
    FIsNull: Boolean;
    FViews: TObjectList<TJSON>;
    FRoot: TJSON;
    FStack: TList<System.JSON.TJSONValue>;

    constructor CreateView(const ARoot: TJSON; const AValue: System.JSON.TJSONValue);
    constructor CreateNull(const ARoot: TJSON);

    function RegisterView(const AView: TJSON): TJSON;
    function ResolvePath(const APath: string): System.JSON.TJSONValue;
    function CurrentContainer(): System.JSON.TJSONValue;
    function PrettyPrint(const AValue: System.JSON.TJSONValue; const AIndent: Integer; const ALevel: Integer): string;
  public
    constructor Create(); virtual;
    destructor Destroy(); override;

    // --- Class Factory Methods ---
    class function FromFile(const AFilename: string): TJSON;
    class function FromString(const AText: string): TJSON;
    class function FromStream(const AStream: TStream): TJSON;

    // --- Loading (fluent) ---
    function Parse(const AText: string): TJSON;
    function LoadFromFile(const AFilename: string): TJSON;
    function LoadFromStream(const AStream: TStream): TJSON;

    // --- Saving ---
    function ToString(): string; override;
    function ToPrettyString(const AIndent: Integer = 2): string;
    procedure SaveToFile(const AFilename: string; const APretty: Boolean = True);
    procedure SaveToStream(const AStream: TStream; const APretty: Boolean = True);

    // --- Building (fluent, keyed â€” for objects) ---
    function Add(const AKey: string; const AValue: string): TJSON; overload;
    function Add(const AKey: string; const AValue: Int64): TJSON; overload;
    function Add(const AKey: string; const AValue: Double): TJSON; overload;
    function Add(const AKey: string; const AValue: Boolean): TJSON; overload;
    function Add(const AKey: string; const AValue: TJSON): TJSON; overload;
    function AddNull(const AKey: string): TJSON; overload;
    function AddRaw(const AKey: string; const AJsonText: string): TJSON;

    // --- Building (fluent, keyless â€” for arrays) ---
    function Add(const AValue: string): TJSON; overload;
    function Add(const AValue: Int64): TJSON; overload;
    function Add(const AValue: Double): TJSON; overload;
    function Add(const AValue: Boolean): TJSON; overload;
    function Add(const AValue: TJSON): TJSON; overload;
    function AddNull(): TJSON; overload;

    // --- Building (fluent, array-of-values) ---
    function AddStrings(const AKey: string; const AValues: array of string): TJSON;
    function AddIntegers(const AKey: string; const AValues: array of Int64): TJSON;
    function AddDoubles(const AKey: string; const AValues: array of Double): TJSON;

    // --- Building (nesting) ---
    function BeginObject(const AKey: string): TJSON; overload;
    function BeginObject(): TJSON; overload;
    function EndObject(): TJSON;
    function BeginArray(const AKey: string): TJSON; overload;
    function BeginArray(): TJSON; overload;
    function EndArray(): TJSON;

    // --- Navigation ---
    function Get(const APath: string; const ALiteral: Boolean = False): TJSON;
    function Has(const APath: string; const ALiteral: Boolean = False): Boolean;
    function Count(): Integer;
    function Keys(): TArray<string>;
    function Items(): TArray<TJSON>;
    function First(): TJSON;
    function Last(): TJSON;
    function Contains(const AValue: string): Boolean; overload;
    function Contains(const AValue: Int64): Boolean; overload;
    function Pairs(): TArray<TJSONPair>;

    // --- Value Extraction ---
    function AsString(const ADefault: string = ''): string;
    function AsBoolean(const ADefault: Boolean = False): Boolean;
    function AsInt32(const ADefault: Integer = 0): Integer;
    function AsInt64(const ADefault: Int64 = 0): Int64;
    function AsUInt32(const ADefault: Cardinal = 0): Cardinal;
    function AsUInt64(const ADefault: UInt64 = 0): UInt64;
    function AsSingle(const ADefault: Single = 0.0): Single;
    function AsDouble(const ADefault: Double = 0.0): Double;

    // --- Typed Array Extraction ---
    function AsStringArray(): TArray<string>;
    function AsInt32Array(): TArray<Integer>;
    function AsInt64Array(): TArray<Int64>;
    function AsDoubleArray(): TArray<Double>;

    // --- Type Checking ---
    function IsNull(): Boolean;
    function IsObject(): Boolean;
    function IsArray(): Boolean;
    function IsNumber(): Boolean;
    function IsString(): Boolean;
    function IsBoolean(): Boolean;

    // --- Enumeration ---
    function GetEnumerator(): TJSONEnumerator;
    function ForEach(const ACallback: TJSONCallback; const AUserData: Pointer): TJSON;

    // --- Modification ---
    function Remove(const AKey: string): TJSON;
    function Merge(const AOther: TJSON): TJSON;
    function Clone(): TJSON;
  end;

implementation

{ TJSONEnumerator }

constructor TJSONEnumerator.Create(const AJSON: TJSON);
begin
  inherited Create();
  FJSON := AJSON;
  FIndex := -1;
  FItems := AJSON.Items();
end;

function TJSONEnumerator.MoveNext(): Boolean;
begin
  Inc(FIndex);
  Result := FIndex < Length(FItems);
end;

function TJSONEnumerator.GetCurrent(): TJSON;
begin
  Result := FItems[FIndex];
end;

{ TJSON }

constructor TJSON.Create();
begin
  inherited Create();
  FValue := System.JSON.TJSONObject.Create();
  FOwnsValue := True;
  FIsNull := False;
  FRoot := nil;
  FViews := TObjectList<TJSON>.Create(True);
  FStack := TList<System.JSON.TJSONValue>.Create();
end;

constructor TJSON.CreateView(const ARoot: TJSON; const AValue: System.JSON.TJSONValue);
begin
  inherited Create();
  FValue := AValue;
  FOwnsValue := False;
  FIsNull := False;
  // Resolve to the actual root (not an intermediate view)
  if ARoot.FRoot <> nil then
    FRoot := ARoot.FRoot
  else
    FRoot := ARoot;
  FViews := nil;
  FStack := nil;
end;

constructor TJSON.CreateNull(const ARoot: TJSON);
begin
  inherited Create();
  FValue := nil;
  FOwnsValue := False;
  FIsNull := True;
  // Resolve to the actual root (not an intermediate view)
  if ARoot.FRoot <> nil then
    FRoot := ARoot.FRoot
  else
    FRoot := ARoot;
  FViews := nil;
  FStack := nil;
end;

destructor TJSON.Destroy();
begin
  FStack.Free();
  FViews.Free();
  if FOwnsValue and (FValue <> nil) then
    FValue.Free();
  inherited;
end;

function TJSON.RegisterView(const AView: TJSON): TJSON;
var
  LRoot: TJSON;
begin
  // Always register views on the root object so they live as long as the root
  if FRoot <> nil then
    LRoot := FRoot
  else
    LRoot := Self;
  LRoot.FViews.Add(AView);
  Result := AView;
end;

function TJSON.CurrentContainer(): System.JSON.TJSONValue;
begin
  // Return the top of the nesting stack, or FValue if stack is empty
  if (FStack <> nil) and (FStack.Count > 0) then
    Result := FStack.Last()
  else
    Result := FValue;
end;

function TJSON.ResolvePath(const APath: string): System.JSON.TJSONValue;
var
  LParts: TArray<string>;
  LCurrent: System.JSON.TJSONValue;
  LPart: string;
  LBracketPos: Integer;
  LKey: string;
  LIndex: Integer;
  LI: Integer;
  LObj: System.JSON.TJSONObject;
  LArr: System.JSON.TJSONArray;
begin
  Result := nil;
  if FIsNull or (FValue = nil) then
    Exit;

  LCurrent := FValue;
  LParts := APath.Split(['.']);

  for LI := 0 to Length(LParts) - 1 do
  begin
    LPart := LParts[LI];
    if LPart.IsEmpty() then
      Continue;

    // Check for array index syntax: key[0] or just [0]
    LBracketPos := LPart.IndexOf('[');
    if LBracketPos >= 0 then
    begin
      // Extract key part before bracket (may be empty for bare [0])
      LKey := LPart.Substring(0, LBracketPos);

      // Navigate to the key first if present
      if not LKey.IsEmpty() then
      begin
        if not (LCurrent is System.JSON.TJSONObject) then
          Exit(nil);
        LObj := System.JSON.TJSONObject(LCurrent);
        LCurrent := LObj.GetValue(LKey);
        if LCurrent = nil then
          Exit(nil);
      end;

      // Parse index from [N]
      LKey := LPart.Substring(LBracketPos + 1);
      LKey := LKey.TrimRight([']']);
      if not TryStrToInt(LKey, LIndex) then
        Exit(nil);

      if not (LCurrent is System.JSON.TJSONArray) then
        Exit(nil);
      LArr := System.JSON.TJSONArray(LCurrent);
      if (LIndex < 0) or (LIndex >= LArr.Count) then
        Exit(nil);
      LCurrent := LArr.Items[LIndex];
    end
    else
    begin
      // Simple key navigation
      if not (LCurrent is System.JSON.TJSONObject) then
        Exit(nil);
      LObj := System.JSON.TJSONObject(LCurrent);
      LCurrent := LObj.GetValue(LPart);
      if LCurrent = nil then
        Exit(nil);
    end;
  end;

  Result := LCurrent;
end;

function TJSON.PrettyPrint(const AValue: System.JSON.TJSONValue; const AIndent: Integer;
  const ALevel: Integer): string;
var
  LBuilder: TStringBuilder;
  LObj: System.JSON.TJSONObject;
  LArr: System.JSON.TJSONArray;
  LPad: string;
  LInnerPad: string;
  LI: Integer;
  LPair: System.JSON.TJSONPair;
begin
  if AValue = nil then
    Exit('null');

  LPad := StringOfChar(' ', ALevel * AIndent);
  LInnerPad := StringOfChar(' ', (ALevel + 1) * AIndent);

  if AValue is System.JSON.TJSONObject then
  begin
    LObj := System.JSON.TJSONObject(AValue);
    if LObj.Count = 0 then
      Exit('{}');

    LBuilder := TStringBuilder.Create();
    try
      LBuilder.AppendLine('{');
      for LI := 0 to LObj.Count - 1 do
      begin
        LPair := LObj.Pairs[LI];
        LBuilder.Append(LInnerPad);
        LBuilder.Append('"');
        LBuilder.Append(LPair.JsonString.Value);
        LBuilder.Append('": ');
        LBuilder.Append(PrettyPrint(LPair.JsonValue, AIndent, ALevel + 1));
        if LI < LObj.Count - 1 then
          LBuilder.Append(',');
        LBuilder.AppendLine();
      end;
      LBuilder.Append(LPad);
      LBuilder.Append('}');
      Result := LBuilder.ToString();
    finally
      LBuilder.Free();
    end;
  end
  else if AValue is System.JSON.TJSONArray then
  begin
    LArr := System.JSON.TJSONArray(AValue);
    if LArr.Count = 0 then
      Exit('[]');

    LBuilder := TStringBuilder.Create();
    try
      LBuilder.AppendLine('[');
      for LI := 0 to LArr.Count - 1 do
      begin
        LBuilder.Append(LInnerPad);
        LBuilder.Append(PrettyPrint(LArr.Items[LI], AIndent, ALevel + 1));
        if LI < LArr.Count - 1 then
          LBuilder.Append(',');
        LBuilder.AppendLine();
      end;
      LBuilder.Append(LPad);
      LBuilder.Append(']');
      Result := LBuilder.ToString();
    finally
      LBuilder.Free();
    end;
  end
  else
  begin
    // Scalar value â€” use System.JSON's own serialization
    Result := AValue.ToJSON();
  end;
end;

class function TJSON.FromFile(const AFilename: string): TJSON;
begin
  Result := TJSON.Create();
  Result.LoadFromFile(AFilename);
end;

class function TJSON.FromString(const AText: string): TJSON;
begin
  Result := TJSON.Create();
  Result.Parse(AText);
end;

class function TJSON.FromStream(const AStream: TStream): TJSON;
begin
  Result := TJSON.Create();
  Result.LoadFromStream(AStream);
end;

function TJSON.Parse(const AText: string): TJSON;
var
  LParsed: System.JSON.TJSONValue;
begin
  Result := Self;

  // Free existing value if we own it
  if FOwnsValue and (FValue <> nil) then
    FValue.Free();

  LParsed := System.JSON.TJSONObject.ParseJSONValue(AText);
  if LParsed = nil then
  begin
    FValue := System.JSON.TJSONObject.Create();
    FIsNull := True;
    FOwnsValue := True;
    Exit;
  end;

  FValue := LParsed;
  FOwnsValue := True;
  FIsNull := False;
end;

function TJSON.LoadFromFile(const AFilename: string): TJSON;
var
  LText: string;
begin
  Result := Self;
  try
    LText := TFile.ReadAllText(AFilename, TEncoding.UTF8);
    Parse(LText);
  except
    on E: Exception do
    begin
      FIsNull := True;
    end;
  end;
end;

function TJSON.LoadFromStream(const AStream: TStream): TJSON;
var
  LReader: TStreamReader;
  LText: string;
begin
  Result := Self;
  try
    LReader := TStreamReader.Create(AStream, TEncoding.UTF8);
    try
      LText := LReader.ReadToEnd();
    finally
      LReader.Free();
    end;
    Parse(LText);
  except
    on E: Exception do
    begin
      FIsNull := True;
    end;
  end;
end;

function TJSON.ToString(): string;
begin
  if FIsNull or (FValue = nil) then
    Result := 'null'
  else
    Result := FValue.ToJSON();
end;

function TJSON.ToPrettyString(const AIndent: Integer): string;
begin
  if FIsNull or (FValue = nil) then
    Result := 'null'
  else
    Result := PrettyPrint(FValue, AIndent, 0);
end;

procedure TJSON.SaveToFile(const AFilename: string; const APretty: Boolean);
var
  LText: string;
begin
  if APretty then
    LText := ToPrettyString()
  else
    LText := ToString();
  TFile.WriteAllText(AFilename, LText, TEncoding.UTF8);
end;

procedure TJSON.SaveToStream(const AStream: TStream; const APretty: Boolean);
var
  LWriter: TStreamWriter;
  LText: string;
begin
  if APretty then
    LText := ToPrettyString()
  else
    LText := ToString();
  LWriter := TStreamWriter.Create(AStream, TEncoding.UTF8);
  try
    LWriter.Write(LText);
  finally
    LWriter.Free();
  end;
end;

function TJSON.Add(const AKey: string; const AValue: string): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONObject then
    System.JSON.TJSONObject(LContainer).AddPair(AKey, AValue);
end;

function TJSON.Add(const AKey: string; const AValue: Int64): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONObject then
    System.JSON.TJSONObject(LContainer).AddPair(AKey, System.JSON.TJSONNumber.Create(AValue));
end;

function TJSON.Add(const AKey: string; const AValue: Double): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONObject then
    System.JSON.TJSONObject(LContainer).AddPair(AKey, System.JSON.TJSONNumber.Create(AValue));
end;

function TJSON.Add(const AKey: string; const AValue: Boolean): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONObject then
    if AValue then
      System.JSON.TJSONObject(LContainer).AddPair(AKey, System.JSON.TJSONTrue.Create())
    else
      System.JSON.TJSONObject(LContainer).AddPair(AKey, System.JSON.TJSONFalse.Create());
end;

function TJSON.Add(const AKey: string; const AValue: TJSON): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  if (AValue = nil) or (AValue.IsNull()) then
    Exit;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONObject then
    System.JSON.TJSONObject(LContainer).AddPair(AKey, AValue.FValue.Clone() as System.JSON.TJSONValue);
end;

function TJSON.AddNull(const AKey: string): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONObject then
    System.JSON.TJSONObject(LContainer).AddPair(AKey, System.JSON.TJSONNull.Create());
end;

function TJSON.AddRaw(const AKey: string; const AJsonText: string): TJSON;
var
  LContainer: System.JSON.TJSONValue;
  LParsed: System.JSON.TJSONValue;
begin
  Result := Self;
  LParsed := System.JSON.TJSONObject.ParseJSONValue(AJsonText);
  if LParsed = nil then
    Exit;

  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONObject then
    System.JSON.TJSONObject(LContainer).AddPair(AKey, LParsed)
  else
    LParsed.Free();
end;

function TJSON.Add(const AValue: string): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONArray then
    System.JSON.TJSONArray(LContainer).AddElement(System.JSON.TJSONString.Create(AValue));
end;

function TJSON.Add(const AValue: Int64): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONArray then
    System.JSON.TJSONArray(LContainer).AddElement(System.JSON.TJSONNumber.Create(AValue));
end;

function TJSON.Add(const AValue: Double): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONArray then
    System.JSON.TJSONArray(LContainer).AddElement(System.JSON.TJSONNumber.Create(AValue));
end;

function TJSON.Add(const AValue: Boolean): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONArray then
    if AValue then
      System.JSON.TJSONArray(LContainer).AddElement(System.JSON.TJSONTrue.Create())
    else
      System.JSON.TJSONArray(LContainer).AddElement(System.JSON.TJSONFalse.Create());
end;

function TJSON.Add(const AValue: TJSON): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  if (AValue = nil) or (AValue.IsNull()) then
    Exit;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONArray then
    System.JSON.TJSONArray(LContainer).AddElement(AValue.FValue.Clone() as System.JSON.TJSONValue);
end;

function TJSON.AddNull(): TJSON;
var
  LContainer: System.JSON.TJSONValue;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if LContainer is System.JSON.TJSONArray then
    System.JSON.TJSONArray(LContainer).AddElement(System.JSON.TJSONNull.Create());
end;

function TJSON.AddStrings(const AKey: string; const AValues: array of string): TJSON;
var
  LContainer: System.JSON.TJSONValue;
  LArr: System.JSON.TJSONArray;
  LI: Integer;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if not (LContainer is System.JSON.TJSONObject) then
    Exit;

  LArr := System.JSON.TJSONArray.Create();
  for LI := 0 to Length(AValues) - 1 do
    LArr.AddElement(System.JSON.TJSONString.Create(AValues[LI]));
  System.JSON.TJSONObject(LContainer).AddPair(AKey, LArr);
end;

function TJSON.AddIntegers(const AKey: string; const AValues: array of Int64): TJSON;
var
  LContainer: System.JSON.TJSONValue;
  LArr: System.JSON.TJSONArray;
  LI: Integer;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if not (LContainer is System.JSON.TJSONObject) then
    Exit;

  LArr := System.JSON.TJSONArray.Create();
  for LI := 0 to Length(AValues) - 1 do
    LArr.AddElement(System.JSON.TJSONNumber.Create(AValues[LI]));
  System.JSON.TJSONObject(LContainer).AddPair(AKey, LArr);
end;

function TJSON.AddDoubles(const AKey: string; const AValues: array of Double): TJSON;
var
  LContainer: System.JSON.TJSONValue;
  LArr: System.JSON.TJSONArray;
  LI: Integer;
begin
  Result := Self;
  LContainer := CurrentContainer();
  if not (LContainer is System.JSON.TJSONObject) then
    Exit;

  LArr := System.JSON.TJSONArray.Create();
  for LI := 0 to Length(AValues) - 1 do
    LArr.AddElement(System.JSON.TJSONNumber.Create(AValues[LI]));
  System.JSON.TJSONObject(LContainer).AddPair(AKey, LArr);
end;

function TJSON.BeginObject(const AKey: string): TJSON;
var
  LContainer: System.JSON.TJSONValue;
  LObj: System.JSON.TJSONObject;
begin
  Result := Self;
  LContainer := CurrentContainer();
  LObj := System.JSON.TJSONObject.Create();

  if LContainer is System.JSON.TJSONObject then
    System.JSON.TJSONObject(LContainer).AddPair(AKey, LObj)
  else if LContainer is System.JSON.TJSONArray then
    System.JSON.TJSONArray(LContainer).AddElement(LObj);

  FStack.Add(LObj);
end;

function TJSON.BeginObject(): TJSON;
var
  LContainer: System.JSON.TJSONValue;
  LObj: System.JSON.TJSONObject;
begin
  Result := Self;
  LContainer := CurrentContainer();
  LObj := System.JSON.TJSONObject.Create();

  if LContainer is System.JSON.TJSONArray then
    System.JSON.TJSONArray(LContainer).AddElement(LObj);

  FStack.Add(LObj);
end;

function TJSON.EndObject(): TJSON;
begin
  Result := Self;
  if (FStack <> nil) and (FStack.Count > 0) then
    FStack.Delete(FStack.Count - 1);
end;

function TJSON.BeginArray(const AKey: string): TJSON;
var
  LContainer: System.JSON.TJSONValue;
  LArr: System.JSON.TJSONArray;
begin
  Result := Self;
  LContainer := CurrentContainer();
  LArr := System.JSON.TJSONArray.Create();

  if LContainer is System.JSON.TJSONObject then
    System.JSON.TJSONObject(LContainer).AddPair(AKey, LArr)
  else if LContainer is System.JSON.TJSONArray then
    System.JSON.TJSONArray(LContainer).AddElement(LArr);

  FStack.Add(LArr);
end;

function TJSON.BeginArray(): TJSON;
var
  LContainer: System.JSON.TJSONValue;
  LArr: System.JSON.TJSONArray;
begin
  Result := Self;
  LContainer := CurrentContainer();
  LArr := System.JSON.TJSONArray.Create();

  if LContainer is System.JSON.TJSONArray then
    System.JSON.TJSONArray(LContainer).AddElement(LArr);

  FStack.Add(LArr);
end;

function TJSON.EndArray(): TJSON;
begin
  Result := Self;
  if (FStack <> nil) and (FStack.Count > 0) then
    FStack.Delete(FStack.Count - 1);
end;

function TJSON.Get(const APath: string; const ALiteral: Boolean): TJSON;
var
  LResolved: System.JSON.TJSONValue;
  LObj: System.JSON.TJSONObject;
begin
  if ALiteral then
  begin
    // Direct key lookup -- no dot splitting
    if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONObject) then
      Exit(RegisterView(TJSON.CreateNull(Self)));
    LObj := System.JSON.TJSONObject(FValue);
    LResolved := LObj.GetValue(APath);
    if LResolved = nil then
      Result := RegisterView(TJSON.CreateNull(Self))
    else
      Result := RegisterView(TJSON.CreateView(Self, LResolved));
    Exit;
  end;

  LResolved := ResolvePath(APath);
  if LResolved = nil then
    Result := RegisterView(TJSON.CreateNull(Self))
  else
    Result := RegisterView(TJSON.CreateView(Self, LResolved));
end;

function TJSON.Has(const APath: string; const ALiteral: Boolean): Boolean;
var
  LObj: System.JSON.TJSONObject;
begin
  if ALiteral then
  begin
    if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONObject) then
      Exit(False);
    LObj := System.JSON.TJSONObject(FValue);
    Result := LObj.GetValue(APath) <> nil;
    Exit;
  end;
  Result := ResolvePath(APath) <> nil;
end;

function TJSON.Count(): Integer;
begin
  if FIsNull or (FValue = nil) then
    Exit(0);

  if FValue is System.JSON.TJSONArray then
    Result := System.JSON.TJSONArray(FValue).Count
  else if FValue is System.JSON.TJSONObject then
    Result := System.JSON.TJSONObject(FValue).Count
  else
    Result := 0;
end;

function TJSON.Keys(): TArray<string>;
var
  LObj: System.JSON.TJSONObject;
  LI: Integer;
begin
  SetLength(Result, 0);
  if FIsNull or (FValue = nil) then
    Exit;
  if not (FValue is System.JSON.TJSONObject) then
    Exit;

  LObj := System.JSON.TJSONObject(FValue);
  SetLength(Result, LObj.Count);
  for LI := 0 to LObj.Count - 1 do
    Result[LI] := LObj.Pairs[LI].JsonString.Value;
end;

function TJSON.Items(): TArray<TJSON>;
var
  LArr: System.JSON.TJSONArray;
  LObj: System.JSON.TJSONObject;
  LI: Integer;
begin
  SetLength(Result, 0);
  if FIsNull or (FValue = nil) then
    Exit;

  if FValue is System.JSON.TJSONArray then
  begin
    LArr := System.JSON.TJSONArray(FValue);
    SetLength(Result, LArr.Count);
    for LI := 0 to LArr.Count - 1 do
      Result[LI] := RegisterView(TJSON.CreateView(Self, LArr.Items[LI]));
  end
  else if FValue is System.JSON.TJSONObject then
  begin
    LObj := System.JSON.TJSONObject(FValue);
    SetLength(Result, LObj.Count);
    for LI := 0 to LObj.Count - 1 do
      Result[LI] := RegisterView(TJSON.CreateView(Self, LObj.Pairs[LI].JsonValue));
  end;
end;

function TJSON.First(): TJSON;
var
  LArr: System.JSON.TJSONArray;
begin
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONArray) then
    Exit(RegisterView(TJSON.CreateNull(Self)));

  LArr := System.JSON.TJSONArray(FValue);
  if LArr.Count = 0 then
    Exit(RegisterView(TJSON.CreateNull(Self)));

  Result := RegisterView(TJSON.CreateView(Self, LArr.Items[0]));
end;

function TJSON.Last(): TJSON;
var
  LArr: System.JSON.TJSONArray;
begin
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONArray) then
    Exit(RegisterView(TJSON.CreateNull(Self)));

  LArr := System.JSON.TJSONArray(FValue);
  if LArr.Count = 0 then
    Exit(RegisterView(TJSON.CreateNull(Self)));

  Result := RegisterView(TJSON.CreateView(Self, LArr.Items[LArr.Count - 1]));
end;

function TJSON.Contains(const AValue: string): Boolean;
var
  LArr: System.JSON.TJSONArray;
  LI: Integer;
begin
  Result := False;
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONArray) then
    Exit;

  LArr := System.JSON.TJSONArray(FValue);
  for LI := 0 to LArr.Count - 1 do
  begin
    if (LArr.Items[LI] is System.JSON.TJSONString) and
       (System.JSON.TJSONString(LArr.Items[LI]).Value = AValue) then
      Exit(True);
  end;
end;

function TJSON.Contains(const AValue: Int64): Boolean;
var
  LArr: System.JSON.TJSONArray;
  LI: Integer;
begin
  Result := False;
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONArray) then
    Exit;

  LArr := System.JSON.TJSONArray(FValue);
  for LI := 0 to LArr.Count - 1 do
  begin
    if (LArr.Items[LI] is System.JSON.TJSONNumber) and
       (System.JSON.TJSONNumber(LArr.Items[LI]).AsInt64 = AValue) then
      Exit(True);
  end;
end;

function TJSON.Pairs(): TArray<TJSONPair>;
var
  LObj: System.JSON.TJSONObject;
  LI: Integer;
begin
  SetLength(Result, 0);
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONObject) then
    Exit;

  LObj := System.JSON.TJSONObject(FValue);
  SetLength(Result, LObj.Count);
  for LI := 0 to LObj.Count - 1 do
  begin
    Result[LI].NodeName := LObj.Pairs[LI].JsonString.Value;
    Result[LI].Value := RegisterView(TJSON.CreateView(Self, LObj.Pairs[LI].JsonValue));
  end;
end;

function TJSON.AsString(const ADefault: string): string;
begin
  if FIsNull or (FValue = nil) then
    Exit(ADefault);

  if FValue is System.JSON.TJSONString then
    Result := System.JSON.TJSONString(FValue).Value
  else if FValue is System.JSON.TJSONNumber then
    Result := System.JSON.TJSONNumber(FValue).ToString()
  else if FValue is System.JSON.TJSONBool then
  begin
    if (FValue is System.JSON.TJSONTrue) then
      Result := 'true'
    else
      Result := 'false';
  end
  else if FValue is System.JSON.TJSONNull then
    Result := ADefault
  else
    Result := FValue.ToJSON();
end;

function TJSON.AsBoolean(const ADefault: Boolean): Boolean;
begin
  if FIsNull or (FValue = nil) then
    Exit(ADefault);

  if FValue is System.JSON.TJSONBool then
    Result := (FValue is System.JSON.TJSONTrue)
  else if FValue is System.JSON.TJSONNumber then
    Result := System.JSON.TJSONNumber(FValue).AsInt64 <> 0
  else if FValue is System.JSON.TJSONString then
    Result := SameText(System.JSON.TJSONString(FValue).Value, 'true')
  else
    Result := ADefault;
end;

function TJSON.AsInt32(const ADefault: Integer): Integer;
var
  LVal: Int64;
begin
  if FIsNull or (FValue = nil) then
    Exit(ADefault);

  if FValue is System.JSON.TJSONNumber then
  begin
    LVal := System.JSON.TJSONNumber(FValue).AsInt64;
    if (LVal >= Low(Integer)) and (LVal <= High(Integer)) then
      Result := Integer(LVal)
    else
      Result := ADefault;
  end
  else if FValue is System.JSON.TJSONString then
  begin
    if not TryStrToInt(System.JSON.TJSONString(FValue).Value, Result) then
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

function TJSON.AsInt64(const ADefault: Int64): Int64;
begin
  if FIsNull or (FValue = nil) then
    Exit(ADefault);

  if FValue is System.JSON.TJSONNumber then
    Result := System.JSON.TJSONNumber(FValue).AsInt64
  else if FValue is System.JSON.TJSONString then
  begin
    if not TryStrToInt64(System.JSON.TJSONString(FValue).Value, Result) then
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

function TJSON.AsUInt32(const ADefault: Cardinal): Cardinal;
var
  LVal: Int64;
begin
  if FIsNull or (FValue = nil) then
    Exit(ADefault);

  if FValue is System.JSON.TJSONNumber then
  begin
    LVal := System.JSON.TJSONNumber(FValue).AsInt64;
    if (LVal >= 0) and (LVal <= High(Cardinal)) then
      Result := Cardinal(LVal)
    else
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

function TJSON.AsUInt64(const ADefault: UInt64): UInt64;
var
  LVal: Int64;
begin
  if FIsNull or (FValue = nil) then
    Exit(ADefault);

  if FValue is System.JSON.TJSONNumber then
  begin
    // System.JSON stores as Int64 internally, so large UInt64 values
    // above Int64 max may not round-trip perfectly through System.JSON
    LVal := System.JSON.TJSONNumber(FValue).AsInt64;
    if LVal >= 0 then
      Result := UInt64(LVal)
    else
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

function TJSON.AsSingle(const ADefault: Single): Single;
var
  LVal: Double;
begin
  if FIsNull or (FValue = nil) then
    Exit(ADefault);

  if FValue is System.JSON.TJSONNumber then
  begin
    LVal := System.JSON.TJSONNumber(FValue).AsDouble;
    Result := Single(LVal);
  end
  else if FValue is System.JSON.TJSONString then
  begin
    if not TryStrToFloat(System.JSON.TJSONString(FValue).Value, LVal) then
      Exit(ADefault);
    Result := Single(LVal);
  end
  else
    Result := ADefault;
end;

function TJSON.AsDouble(const ADefault: Double): Double;
begin
  if FIsNull or (FValue = nil) then
    Exit(ADefault);

  if FValue is System.JSON.TJSONNumber then
    Result := System.JSON.TJSONNumber(FValue).AsDouble
  else if FValue is System.JSON.TJSONString then
  begin
    if not TryStrToFloat(System.JSON.TJSONString(FValue).Value, Result) then
      Result := ADefault;
  end
  else
    Result := ADefault;
end;

function TJSON.AsStringArray(): TArray<string>;
var
  LArr: System.JSON.TJSONArray;
  LI: Integer;
begin
  SetLength(Result, 0);
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONArray) then
    Exit;

  LArr := System.JSON.TJSONArray(FValue);
  SetLength(Result, LArr.Count);
  for LI := 0 to LArr.Count - 1 do
  begin
    if LArr.Items[LI] is System.JSON.TJSONString then
      Result[LI] := System.JSON.TJSONString(LArr.Items[LI]).Value
    else
      Result[LI] := LArr.Items[LI].ToJSON();
  end;
end;

function TJSON.AsInt32Array(): TArray<Integer>;
var
  LArr: System.JSON.TJSONArray;
  LI: Integer;
  LVal: Int64;
begin
  SetLength(Result, 0);
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONArray) then
    Exit;

  LArr := System.JSON.TJSONArray(FValue);
  SetLength(Result, LArr.Count);
  for LI := 0 to LArr.Count - 1 do
  begin
    if LArr.Items[LI] is System.JSON.TJSONNumber then
    begin
      LVal := System.JSON.TJSONNumber(LArr.Items[LI]).AsInt64;
      if (LVal >= Low(Integer)) and (LVal <= High(Integer)) then
        Result[LI] := Integer(LVal)
      else
        Result[LI] := 0;
    end
    else
      Result[LI] := 0;
  end;
end;

function TJSON.AsInt64Array(): TArray<Int64>;
var
  LArr: System.JSON.TJSONArray;
  LI: Integer;
begin
  SetLength(Result, 0);
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONArray) then
    Exit;

  LArr := System.JSON.TJSONArray(FValue);
  SetLength(Result, LArr.Count);
  for LI := 0 to LArr.Count - 1 do
  begin
    if LArr.Items[LI] is System.JSON.TJSONNumber then
      Result[LI] := System.JSON.TJSONNumber(LArr.Items[LI]).AsInt64
    else
      Result[LI] := 0;
  end;
end;

function TJSON.AsDoubleArray(): TArray<Double>;
var
  LArr: System.JSON.TJSONArray;
  LI: Integer;
begin
  SetLength(Result, 0);
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONArray) then
    Exit;

  LArr := System.JSON.TJSONArray(FValue);
  SetLength(Result, LArr.Count);
  for LI := 0 to LArr.Count - 1 do
  begin
    if LArr.Items[LI] is System.JSON.TJSONNumber then
      Result[LI] := System.JSON.TJSONNumber(LArr.Items[LI]).AsDouble
    else
      Result[LI] := 0.0;
  end;
end;

function TJSON.IsNull(): Boolean;
begin
  Result := FIsNull or (FValue = nil) or (FValue is System.JSON.TJSONNull);
end;

function TJSON.IsObject(): Boolean;
begin
  Result := (not FIsNull) and (FValue <> nil) and (FValue is System.JSON.TJSONObject);
end;

function TJSON.IsArray(): Boolean;
begin
  Result := (not FIsNull) and (FValue <> nil) and (FValue is System.JSON.TJSONArray);
end;

function TJSON.IsNumber(): Boolean;
begin
  Result := (not FIsNull) and (FValue <> nil) and (FValue is System.JSON.TJSONNumber);
end;

function TJSON.IsString(): Boolean;
begin
  Result := (not FIsNull) and (FValue <> nil) and (FValue is System.JSON.TJSONString);
end;

function TJSON.IsBoolean(): Boolean;
begin
  Result := (not FIsNull) and (FValue <> nil) and (FValue is System.JSON.TJSONBool);
end;

function TJSON.GetEnumerator(): TJSONEnumerator;
begin
  Result := TJSONEnumerator.Create(Self);
end;

function TJSON.ForEach(const ACallback: TJSONCallback; const AUserData: Pointer): TJSON;
var
  LItems: TArray<TJSON>;
  LI: Integer;
begin
  Result := Self;
  LItems := Items();
  for LI := 0 to Length(LItems) - 1 do
    ACallback(LItems[LI], AUserData);
end;

function TJSON.Remove(const AKey: string): TJSON;
var
  LObj: System.JSON.TJSONObject;
  LPair: System.JSON.TJSONPair;
begin
  Result := Self;
  if FIsNull or (FValue = nil) or not (FValue is System.JSON.TJSONObject) then
    Exit;

  LObj := System.JSON.TJSONObject(FValue);
  LPair := LObj.RemovePair(AKey);
  LPair.Free();
end;

function TJSON.Merge(const AOther: TJSON): TJSON;
var
  LOtherObj: System.JSON.TJSONObject;
  LI: Integer;
  LPair: System.JSON.TJSONPair;
  LClonedValue: System.JSON.TJSONValue;
  LExisting: System.JSON.TJSONPair;
begin
  Result := Self;
  if (AOther = nil) or AOther.FIsNull or (AOther.FValue = nil) then
    Exit;
  if not (FValue is System.JSON.TJSONObject) or not (AOther.FValue is System.JSON.TJSONObject) then
    Exit;

  LOtherObj := System.JSON.TJSONObject(AOther.FValue);
  for LI := 0 to LOtherObj.Count - 1 do
  begin
    LPair := LOtherObj.Pairs[LI];
    LClonedValue := LPair.JsonValue.Clone() as System.JSON.TJSONValue;

    // Remove existing key if present (overwrite semantics)
    LExisting := System.JSON.TJSONObject(FValue).RemovePair(LPair.JsonString.Value);
    LExisting.Free();

    System.JSON.TJSONObject(FValue).AddPair(LPair.JsonString.Value, LClonedValue);
  end;
end;

function TJSON.Clone(): TJSON;
var
  LCloned: System.JSON.TJSONValue;
begin
  Result := TJSON.Create();
  if FIsNull or (FValue = nil) then
  begin
    Result.FIsNull := True;
    Exit;
  end;

  // Free the default empty object that Create() made
  if Result.FOwnsValue and (Result.FValue <> nil) then
    Result.FValue.Free();

  LCloned := FValue.Clone() as System.JSON.TJSONValue;
  Result.FValue := LCloned;
  Result.FOwnsValue := True;
  Result.FIsNull := False;
end;

end.
