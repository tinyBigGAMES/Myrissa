{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Myrissa.Script - Script engine and interpreter

  Provides a Myrissa scripting engine that reuses the existing lexer, parser,
  and semantic pipeline via inheritance. Scripts use `module script <name>;`
  syntax and are interpreted via a tree-walking AST interpreter.

  Dependencies: StdApp.Base, Myrissa.Common, Myrissa.AST, Myrissa.Parser
===============================================================================}
unit Myrissa.Script;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Rtti,
  System.Generics.Collections,
  StdApp.Utils,
  StdApp.Base,
  Myrissa.Frontend;

const
  MYR_ERR_SCR_001 = 'SCR001';  // Script file not found
  MYR_ERR_SCR_002 = 'SCR002';  // Invalid routine/data declaration
  MYR_ERR_SCR_003 = 'SCR003';  // Registration not a routine/data node
  MYR_ERR_SCR_004 = 'SCR004';  // Runtime error during execution

type
  // Class forwards
  TMyrScriptInterpreter = class;

  { TMyrScriptSignal }
  TMyrScriptSignal = (
    ssNone,
    ssReturn,
    ssBreak,
    ssContinue
  );

  { TMyrScriptValue }
  TMyrScriptValue = TValue;

  { TMyrScriptArgs }
  TMyrScriptArgs = TArray<TMyrScriptValue>;

  { TMyrScriptRoutineFunc }
  TMyrScriptRoutineFunc = reference to function(
    const AArgs: TMyrScriptArgs;
    const AInterpreter: TMyrScriptInterpreter;
    const AUserData: Pointer): TMyrScriptValue;

  { TMyrScriptPrintCallback }
  TMyrScriptPrintCallback = reference to procedure(
    const AText: string; const ANewLine: Boolean; const AUserData: Pointer);

  { TMyrScriptVarEntry }
  TMyrScriptVarEntry = record
    Value: TMyrScriptValue;
    IsConst: Boolean;
  end;

  { TMyrScriptRecord }
  // Runtime representation of a Myrissa record value.
  // Fields stored by name; TypeName tracks the declared type for identity.
  TMyrScriptRecord = class(TBaseObject)
  private
    FTypeName: string;
    FFields: TDictionary<string, TValue>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    function GetField(const AName: string): TValue;
    procedure SetField(const AName: string; const AValue: TValue);
    function HasField(const AName: string): Boolean;
    function Clone(): TMyrScriptRecord;
    property TypeName: string read FTypeName write FTypeName;
    property Fields: TDictionary<string, TValue> read FFields;
  end;

  { TMyrScriptArray }
  // Runtime representation of a Myrissa array value.
  // Supports both static (fixed bounds) and dynamic (growable) arrays.
  TMyrScriptArray = class(TBaseObject)
  private
    FElements: TList<TValue>;
    FLowBound: Int64;
    FIsDynamic: Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    function GetElement(const AIndex: Int64): TValue;
    procedure SetElement(const AIndex: Int64; const AValue: TValue);
    function GetCount(): Int64;
    procedure Resize(const ANewLength: Int64);
    function Clone(): TMyrScriptArray;
    property Elements: TList<TValue> read FElements;
    property LowBound: Int64 read FLowBound write FLowBound;
    property IsDynamic: Boolean read FIsDynamic write FIsDynamic;
  end;

  { TMyrScriptSet }
  // Runtime representation of a Myrissa set value.
  // Stores members as sorted Int64 for fast membership testing.
  TMyrScriptSet = class(TBaseObject)
  private
    FMembers: TList<Int64>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Add(const AValue: Int64);
    procedure AddRange(const ALow: Int64; const AHigh: Int64);
    function Contains(const AValue: Int64): Boolean;
    function Clone(): TMyrScriptSet;
    property Members: TList<Int64> read FMembers;
  end;

  { TMyrScriptBuffer }
  // Runtime representation of a raw memory buffer for getmem/freemem/resizemem.
  TMyrScriptBuffer = class(TBaseObject)
  private
    FData: TBytes;
    FSize: Int64;
  public
    constructor Create(); override;
    procedure Allocate(const ASize: Int64);
    procedure Resize(const ANewSize: Int64);
    property Data: TBytes read FData;
    property Size: Int64 read FSize;
  end;

  { TMyrScriptScope }
  TMyrScriptScope = class
  private
    FVars: TDictionary<string, TMyrScriptVarEntry>;
    FParent: TMyrScriptScope;
  public
    constructor Create(const AParent: TMyrScriptScope);
    destructor Destroy(); override;
    property Vars: TDictionary<string, TMyrScriptVarEntry> read FVars;
    property Parent: TMyrScriptScope read FParent;
  end;

  { TMyrScriptEnvironment }
  TMyrScriptEnvironment = class(TBaseObject)
  private
    FCurrent: TMyrScriptScope;
    FScopes: TObjectList<TMyrScriptScope>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure PushScope();
    procedure PopScope();
    function DeclareVar(const AName: string; const AValue: TMyrScriptValue;
      const AIsConst: Boolean = False): Boolean;
    function UpdateVar(const AName: string; const AValue: TMyrScriptValue): Boolean;
    function TryGetVar(const AName: string; out AValue: TMyrScriptValue): Boolean;
    property CurrentScope: TMyrScriptScope read FCurrent;
  end;

  { TMyrScriptParser }
  TMyrScriptParser = class(TMyrParser)
  protected
    function DoParseModuleKind(): TMyrModuleKind; override;
  end;

  { TMyrScriptInterpreter }
  TMyrScriptInterpreter = class(TBaseObject)
  private
    FEnvironment: TMyrScriptEnvironment;
    FSignal: TMyrScriptSignal;
    FReturnValue: TMyrScriptValue;
    FFuncs: TDictionary<TMyrRoutineDeclNode, TCallback<TMyrScriptRoutineFunc>>;
    FPrintCallback: TCallback<TMyrScriptPrintCallback>;
    FCurrentExcCode: Int64;
    FCurrentExcMsg: string;

    // Core dispatch
    procedure ExecNode(const ANode: TMyrASTNode);
    procedure ExecStmtList(const AList: TObjectList<TMyrASTNode>);
    function EvalExpr(const ANode: TMyrASTNode): TMyrScriptValue;

    // Statement handlers
    procedure ExecConstDecl(const ANode: TMyrConstDeclNode);
    procedure ExecVarDecl(const ANode: TMyrVarDeclNode);
    procedure ExecRoutineDecl(const ANode: TMyrRoutineDeclNode);
    procedure ExecAssign(const ANode: TMyrAssignNode);
    procedure ExecCallStmt(const ANode: TMyrCallStmtNode);
    procedure ExecIf(const ANode: TMyrIfNode);
    procedure ExecWhile(const ANode: TMyrWhileNode);
    procedure ExecFor(const ANode: TMyrForNode);
    procedure ExecRepeat(const ANode: TMyrRepeatNode);
    procedure ExecMatch(const ANode: TMyrMatchNode);
    procedure ExecReturn(const ANode: TMyrReturnNode);
    procedure ExecGuard(const ANode: TMyrGuardNode);
    procedure ExecThrow(const ANode: TMyrThrowNode);
    procedure ExecThrowCode(const ANode: TMyrThrowCodeNode);
    procedure ExecPrint(const ANode: TMyrPrintNode);
    procedure ExecAssertStmt(const ANode: TMyrAssertStmtNode);
    procedure ExecSetLength(const ANode: TMyrSetLengthNode);
    procedure ExecDirective(const ANode: TMyrDirectiveNode);
    procedure ExecNew(const ANode: TMyrNewNode);
    procedure ExecDispose(const ANode: TMyrDisposeNode);
    procedure ExecGetMem(const ANode: TMyrGetMemNode);
    procedure ExecFreeMem(const ANode: TMyrFreeMemNode);
    procedure ExecResizeMem(const ANode: TMyrResizeMemNode);

    // Expression evaluators
    function EvalBinaryExpr(const ANode: TMyrBinaryExprNode): TMyrScriptValue;
    function EvalUnaryExpr(const ANode: TMyrUnaryExprNode): TMyrScriptValue;
    function EvalCallExpr(const ANode: TMyrCallExprNode): TMyrScriptValue;
    function EvalIdentifier(const ANode: TMyrIdentifierNode): TMyrScriptValue;
    function EvalIntrinsic(const ANode: TMyrIntrinsicExprNode): TMyrScriptValue;
    function EvalTypeCast(const ANode: TMyrTypeCastExprNode): TMyrScriptValue;
    function EvalDotAccess(const ANode: TMyrDotAccessNode): TMyrScriptValue;
    function EvalIndexAccess(const ANode: TMyrIndexAccessNode): TMyrScriptValue;
    function EvalDeref(const ANode: TMyrDerefNode): TMyrScriptValue;
    function EvalSetLiteral(const ANode: TMyrSetLiteralExprNode): TMyrScriptValue;
    function EvalRecordLiteral(const ANode: TMyrRecordLiteralNode): TMyrScriptValue;

    // Helpers
    function DoApplyCompoundOp(const AOp: TMyrAssignOp; const AOld: TMyrScriptValue;
      const ANew: TMyrScriptValue): TMyrScriptValue;
    function ValueToStr(const AValue: TMyrScriptValue): string;
    function ValueToBool(const AValue: TMyrScriptValue): Boolean;
    function ValueToInt(const AValue: TMyrScriptValue): Int64;
    function ValueToFloat(const AValue: TMyrScriptValue): Double;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure RegisterBuiltin(const ANode: TMyrRoutineDeclNode;
      const AFunc: TMyrScriptRoutineFunc; const AUserData: Pointer = nil);
    function IsBuiltin(const ANode: TMyrRoutineDeclNode): Boolean;

    procedure Execute(const AModule: TMyrModuleNode);

    property Environment: TMyrScriptEnvironment read FEnvironment;
    property Signal: TMyrScriptSignal read FSignal;
    property ReturnValue: TMyrScriptValue read FReturnValue;
    property PrintCallback: TCallback<TMyrScriptPrintCallback> read FPrintCallback write FPrintCallback;
  end;

  { TMyrScriptSemantics }
  TMyrScriptSemantics = class(TMyrSemantics)
  protected
    procedure DoAnalyzeModule(const AModule: TMyrModuleNode); override;
  public
    procedure Analyze(const AMasterAST: TMyrMasterAST); override;
  end;

  { TMyrScriptEngine }
  TMyrScriptEngine = class(TBaseObject)
  private
    FExtension: string;
    FParser: TMyrScriptParser;
    FSemantics: TMyrScriptSemantics;
    FInterpreter: TMyrScriptInterpreter;
    FMasterAST: TMyrMasterAST;
    FSyntheticDecls: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetErrors(const AErrors: TErrors); override;
    procedure SetStatusCallback(const ACallback: TStatusCallback;
      const AUserData: Pointer = nil); override;
    procedure SetExtension(const AExt: string);
    procedure SetPrintCallback(const ACallback: TMyrScriptPrintCallback;
      const AUserData: Pointer = nil);
    procedure RegisterGlobalRoutine(const ADeclaration: string;
      const AFunc: TMyrScriptRoutineFunc; const AUserData: Pointer = nil);
    procedure RegisterGlobalData(const ADeclaration: string);
    function ExecuteFile(const AFilename: string): Boolean;
    function ExecuteSource(const ASource: string;
      const AFilename: string): Boolean;
  end;

implementation

{ TMyrScriptRecord }
constructor TMyrScriptRecord.Create();
begin
  inherited;

  FTypeName := '';
  FFields := TDictionary<string, TValue>.Create();
end;

destructor TMyrScriptRecord.Destroy();
begin
  FFields.Free();

  inherited;
end;

function TMyrScriptRecord.GetField(const AName: string): TValue;
begin
  if not FFields.TryGetValue(AName, Result) then
    raise Exception.CreateFmt('Record field "%s" not found in %s', [AName, FTypeName]);
end;

procedure TMyrScriptRecord.SetField(const AName: string; const AValue: TValue);
begin
  FFields.AddOrSetValue(AName, AValue);
end;

function TMyrScriptRecord.HasField(const AName: string): Boolean;
begin
  Result := FFields.ContainsKey(AName);
end;

function TMyrScriptRecord.Clone(): TMyrScriptRecord;
var
  LPair: TPair<string, TValue>;
begin
  Result := TMyrScriptRecord.Create();
  Result.FTypeName := FTypeName;
  for LPair in FFields do
    Result.FFields.Add(LPair.Key, LPair.Value);
end;

{ TMyrScriptArray }
constructor TMyrScriptArray.Create();
begin
  inherited;

  FElements := TList<TValue>.Create();
  FLowBound := 0;
  FIsDynamic := True;
end;

destructor TMyrScriptArray.Destroy();
begin
  FElements.Free();

  inherited;
end;

function TMyrScriptArray.GetElement(const AIndex: Int64): TValue;
var
  LActual: Int64;
begin
  LActual := AIndex - FLowBound;
  if (LActual < 0) or (LActual >= FElements.Count) then
    raise Exception.CreateFmt('Array index %d out of bounds [%d..%d]',
      [AIndex, FLowBound, FLowBound + FElements.Count - 1]);
  Result := FElements[LActual];
end;

procedure TMyrScriptArray.SetElement(const AIndex: Int64; const AValue: TValue);
var
  LActual: Int64;
begin
  LActual := AIndex - FLowBound;
  if (LActual < 0) or (LActual >= FElements.Count) then
    raise Exception.CreateFmt('Array index %d out of bounds [%d..%d]',
      [AIndex, FLowBound, FLowBound + FElements.Count - 1]);
  FElements[LActual] := AValue;
end;

function TMyrScriptArray.GetCount(): Int64;
begin
  Result := FElements.Count;
end;

procedure TMyrScriptArray.Resize(const ANewLength: Int64);
begin
  while FElements.Count < ANewLength do
    FElements.Add(TValue.Empty);
  while FElements.Count > ANewLength do
    FElements.Delete(FElements.Count - 1);
end;

function TMyrScriptArray.Clone(): TMyrScriptArray;
var
  LI: Integer;
begin
  Result := TMyrScriptArray.Create();
  Result.FLowBound := FLowBound;
  Result.FIsDynamic := FIsDynamic;
  for LI := 0 to FElements.Count - 1 do
    Result.FElements.Add(FElements[LI]);
end;

{ TMyrScriptSet }
constructor TMyrScriptSet.Create();
begin
  inherited;

  FMembers := TList<Int64>.Create();
end;

destructor TMyrScriptSet.Destroy();
begin
  FMembers.Free();

  inherited;
end;

procedure TMyrScriptSet.Add(const AValue: Int64);
begin
  if not FMembers.Contains(AValue) then
    FMembers.Add(AValue);
end;

procedure TMyrScriptSet.AddRange(const ALow: Int64; const AHigh: Int64);
var
  LI: Int64;
begin
  for LI := ALow to AHigh do
    Add(LI);
end;

function TMyrScriptSet.Contains(const AValue: Int64): Boolean;
begin
  Result := FMembers.Contains(AValue);
end;

function TMyrScriptSet.Clone(): TMyrScriptSet;
var
  LI: Integer;
begin
  Result := TMyrScriptSet.Create();
  for LI := 0 to FMembers.Count - 1 do
    Result.FMembers.Add(FMembers[LI]);
end;

{ TMyrScriptBuffer }
constructor TMyrScriptBuffer.Create();
begin
  inherited Create();

  FSize := 0;
  SetLength(FData, 0);
end;

procedure TMyrScriptBuffer.Allocate(const ASize: Int64);
begin
  FSize := ASize;
  SetLength(FData, ASize);
  if ASize > 0 then
    FillChar(FData[0], ASize, 0);
end;

procedure TMyrScriptBuffer.Resize(const ANewSize: Int64);
begin
  FSize := ANewSize;
  SetLength(FData, ANewSize);
end;

{ TMyrScriptScope }
constructor TMyrScriptScope.Create(const AParent: TMyrScriptScope);
begin
  inherited Create();

  FVars := TDictionary<string, TMyrScriptVarEntry>.Create();
  FParent := AParent;
end;

destructor TMyrScriptScope.Destroy();
var
  LEntry: TMyrScriptVarEntry;
begin
  // Free any TObject values stored in TValue (composite wrappers)
  for LEntry in FVars.Values do
  begin
    if LEntry.Value.IsObject and (LEntry.Value.AsObject <> nil) and
       not (LEntry.Value.AsObject is TMyrASTNode) then
      LEntry.Value.AsObject.Free();
  end;
  FVars.Free();

  inherited;
end;

{ TMyrScriptEnvironment }
constructor TMyrScriptEnvironment.Create();
begin
  inherited;

  FScopes := TObjectList<TMyrScriptScope>.Create(True);
  FCurrent := TMyrScriptScope.Create(nil);
  FScopes.Add(FCurrent);
end;

destructor TMyrScriptEnvironment.Destroy();
begin
  FScopes.Free();

  inherited;
end;

procedure TMyrScriptEnvironment.PushScope();
begin
  FCurrent := TMyrScriptScope.Create(FCurrent);
  FScopes.Add(FCurrent);
end;

procedure TMyrScriptEnvironment.PopScope();
begin
  if FCurrent.Parent = nil then
    Exit;
  FCurrent := FCurrent.Parent;
end;

function TMyrScriptEnvironment.DeclareVar(const AName: string;
  const AValue: TMyrScriptValue; const AIsConst: Boolean): Boolean;
var
  LEntry: TMyrScriptVarEntry;
begin
  if FCurrent.Vars.ContainsKey(AName) then
    Exit(False);

  LEntry.Value := AValue;
  LEntry.IsConst := AIsConst;
  FCurrent.Vars.Add(AName, LEntry);
  Result := True;
end;

function TMyrScriptEnvironment.UpdateVar(const AName: string;
  const AValue: TMyrScriptValue): Boolean;
var
  LScope: TMyrScriptScope;
  LEntry: TMyrScriptVarEntry;
begin
  LScope := FCurrent;
  while LScope <> nil do
  begin
    if LScope.Vars.TryGetValue(AName, LEntry) then
    begin
      if LEntry.IsConst then
        Exit(False);
      // Free old composite wrapper if being replaced
      if LEntry.Value.IsObject and (LEntry.Value.AsObject <> nil) and
         not (LEntry.Value.AsObject is TMyrASTNode) then
      begin
        if not AValue.IsObject or (LEntry.Value.AsObject <> AValue.AsObject) then
          LEntry.Value.AsObject.Free();
      end;
      LEntry.Value := AValue;
      LScope.Vars.AddOrSetValue(AName, LEntry);
      Result := True;
      Exit;
    end;
    LScope := LScope.Parent;
  end;
  Result := False;
end;

function TMyrScriptEnvironment.TryGetVar(const AName: string;
  out AValue: TMyrScriptValue): Boolean;
var
  LScope: TMyrScriptScope;
  LEntry: TMyrScriptVarEntry;
begin
  LScope := FCurrent;
  while LScope <> nil do
  begin
    if LScope.Vars.TryGetValue(AName, LEntry) then
    begin
      AValue := LEntry.Value;
      Result := True;
      Exit;
    end;
    LScope := LScope.Parent;
  end;
  Result := False;
end;

{ TMyrScriptParser }
function TMyrScriptParser.DoParseModuleKind(): TMyrModuleKind;
var
  LText: string;
begin
  if Current().Kind = tkIdentifier then
  begin
    LText := Current().TokenText;
    if LText = 'script' then
    begin
      Consume();
      Result := mkExe;
      Exit;
    end;
  end;

  Result := inherited;
end;

{ TMyrScriptInterpreter }
constructor TMyrScriptInterpreter.Create();
begin
  inherited;

  FEnvironment := TMyrScriptEnvironment.Create();
  FFuncs := TDictionary<TMyrRoutineDeclNode, TCallback<TMyrScriptRoutineFunc>>.Create();
  FSignal := ssNone;
end;

destructor TMyrScriptInterpreter.Destroy();
begin
  FFuncs.Free();
  FEnvironment.Free();

  inherited;
end;

procedure TMyrScriptInterpreter.RegisterBuiltin(const ANode: TMyrRoutineDeclNode;
  const AFunc: TMyrScriptRoutineFunc; const AUserData: Pointer);
var
  LCB: TCallback<TMyrScriptRoutineFunc>;
begin
  LCB.Callback := AFunc;
  LCB.UserData := AUserData;
  FFuncs.AddOrSetValue(ANode, LCB);
end;

function TMyrScriptInterpreter.IsBuiltin(const ANode: TMyrRoutineDeclNode): Boolean;
begin
  Result := FFuncs.ContainsKey(ANode);
end;

procedure TMyrScriptInterpreter.Execute(const AModule: TMyrModuleNode);
var
  LDecl: TMyrASTNode;
begin
  FSignal := ssNone;
  FReturnValue := TMyrScriptValue.Empty;

  // Process declarations (registers routines and consts/vars in scope)
  for LDecl in AModule.Declarations do
    ExecNode(LDecl);

  // Execute init body if present
  if AModule.InitBody.Count > 0 then
    ExecStmtList(AModule.InitBody);

  // Execute main body
  if AModule.HasMainBody then
    ExecStmtList(AModule.MainBody);
end;

procedure TMyrScriptInterpreter.ExecNode(const ANode: TMyrASTNode);
begin
  if ANode = nil then
    Exit;
  if FSignal <> ssNone then
    Exit;

  if ANode is TMyrConstDeclNode then
    ExecConstDecl(TMyrConstDeclNode(ANode))
  else if ANode is TMyrVarDeclNode then
    ExecVarDecl(TMyrVarDeclNode(ANode))
  else if ANode is TMyrRoutineDeclNode then
    ExecRoutineDecl(TMyrRoutineDeclNode(ANode))
  else if ANode is TMyrAssignNode then
    ExecAssign(TMyrAssignNode(ANode))
  else if ANode is TMyrCallStmtNode then
    ExecCallStmt(TMyrCallStmtNode(ANode))
  else if ANode is TMyrIfNode then
    ExecIf(TMyrIfNode(ANode))
  else if ANode is TMyrWhileNode then
    ExecWhile(TMyrWhileNode(ANode))
  else if ANode is TMyrForNode then
    ExecFor(TMyrForNode(ANode))
  else if ANode is TMyrRepeatNode then
    ExecRepeat(TMyrRepeatNode(ANode))
  else if ANode is TMyrMatchNode then
    ExecMatch(TMyrMatchNode(ANode))
  else if ANode is TMyrReturnNode then
    ExecReturn(TMyrReturnNode(ANode))
  else if ANode is TMyrBreakNode then
    FSignal := ssBreak
  else if ANode is TMyrContinueNode then
    FSignal := ssContinue
  else if ANode is TMyrGuardNode then
    ExecGuard(TMyrGuardNode(ANode))
  else if ANode is TMyrThrowNode then
    ExecThrow(TMyrThrowNode(ANode))
  else if ANode is TMyrThrowCodeNode then
    ExecThrowCode(TMyrThrowCodeNode(ANode))
  else if ANode is TMyrPrintNode then
    ExecPrint(TMyrPrintNode(ANode))
  else if ANode is TMyrAssertStmtNode then
    ExecAssertStmt(TMyrAssertStmtNode(ANode))
  else if ANode is TMyrSetLengthNode then
    ExecSetLength(TMyrSetLengthNode(ANode))
  else if ANode is TMyrDirectiveNode then
    ExecDirective(TMyrDirectiveNode(ANode))
  else if ANode is TMyrNewNode then
    ExecNew(TMyrNewNode(ANode))
  else if ANode is TMyrDisposeNode then
    ExecDispose(TMyrDisposeNode(ANode))
  else if ANode is TMyrGetMemNode then
    ExecGetMem(TMyrGetMemNode(ANode))
  else if ANode is TMyrFreeMemNode then
    ExecFreeMem(TMyrFreeMemNode(ANode))
  else if ANode is TMyrResizeMemNode then
    ExecResizeMem(TMyrResizeMemNode(ANode))
  else if ANode is TMyrCppBlockNode then
    raise Exception.Create('C++ blocks are not supported in script mode')
  else if ANode is TMyrTypeDeclNode then
    // Type declarations are no-ops at runtime
  else if ANode is TMyrForwardTypeDeclNode then
    // Forward type declarations are no-ops at runtime
  else if ANode is TMyrForwardRoutineDeclNode then
    // Forward routine declarations are no-ops at runtime
  ;
end;

procedure TMyrScriptInterpreter.ExecStmtList(const AList: TObjectList<TMyrASTNode>);
var
  LNode: TMyrASTNode;
begin
  for LNode in AList do
  begin
    if FSignal <> ssNone then
      Exit;
    ExecNode(LNode);
  end;
end;

function TMyrScriptInterpreter.EvalExpr(const ANode: TMyrASTNode): TMyrScriptValue;
begin
  Result := TMyrScriptValue.Empty;
  if ANode = nil then
    Exit;

  if ANode is TMyrIntLiteralNode then
    Result := TMyrScriptValue.From<Int64>(TMyrIntLiteralNode(ANode).IntValue)
  else if ANode is TMyrFloatLiteralNode then
    Result := TMyrScriptValue.From<Double>(TMyrFloatLiteralNode(ANode).FloatValue)
  else if ANode is TMyrStringLiteralNode then
    Result := TMyrScriptValue.From<string>(TMyrStringLiteralNode(ANode).StringValue)
  else if ANode is TMyrWStringLiteralNode then
    Result := TMyrScriptValue.From<string>(TMyrWStringLiteralNode(ANode).StringValue)
  else if ANode is TMyrBoolLiteralNode then
    Result := TMyrScriptValue.From<Boolean>(TMyrBoolLiteralNode(ANode).BoolValue)
  else if ANode is TMyrNilLiteralNode then
    Result := TMyrScriptValue.Empty
  else if ANode is TMyrBinaryExprNode then
    Result := EvalBinaryExpr(TMyrBinaryExprNode(ANode))
  else if ANode is TMyrUnaryExprNode then
    Result := EvalUnaryExpr(TMyrUnaryExprNode(ANode))
  else if ANode is TMyrIdentifierNode then
    Result := EvalIdentifier(TMyrIdentifierNode(ANode))
  else if ANode is TMyrCallExprNode then
    Result := EvalCallExpr(TMyrCallExprNode(ANode))
  else if ANode is TMyrIntrinsicExprNode then
    Result := EvalIntrinsic(TMyrIntrinsicExprNode(ANode))
  else if ANode is TMyrTypeCastExprNode then
    Result := EvalTypeCast(TMyrTypeCastExprNode(ANode))
  else if ANode is TMyrDotAccessNode then
    Result := EvalDotAccess(TMyrDotAccessNode(ANode))
  else if ANode is TMyrIndexAccessNode then
    Result := EvalIndexAccess(TMyrIndexAccessNode(ANode))
  else if ANode is TMyrDerefNode then
    Result := EvalDeref(TMyrDerefNode(ANode))
  else if ANode is TMyrSetLiteralExprNode then
    Result := EvalSetLiteral(TMyrSetLiteralExprNode(ANode))
  else if ANode is TMyrRecordLiteralNode then
    Result := EvalRecordLiteral(TMyrRecordLiteralNode(ANode))
  else if ANode is TMyrCppExprNode then
    raise Exception.Create('C++ expressions are not supported in script mode');
end;

procedure TMyrScriptInterpreter.ExecConstDecl(const ANode: TMyrConstDeclNode);
var
  LValue: TMyrScriptValue;
begin
  LValue := EvalExpr(ANode.ValueExpr);
  FEnvironment.DeclareVar(ANode.DeclName, LValue, True);
end;

procedure TMyrScriptInterpreter.ExecVarDecl(const ANode: TMyrVarDeclNode);
var
  LValue: TMyrScriptValue;
  LTypeNode: TMyrASTNode;
  LTypeDef: TMyrASTNode;
  LRec: TMyrScriptRecord;
  LArr: TMyrScriptArray;
  LSet: TMyrScriptSet;
  LFieldNode: TMyrASTNode;
begin
  if ANode.InitExpr <> nil then
    LValue := EvalExpr(ANode.InitExpr)
  else
  begin
    // Default-initialize based on type
    LValue := TMyrScriptValue.Empty;
    LTypeNode := ANode.TypeExpr;

    // Follow TCPTypeRefNode -> ResolvedDecl -> TCPTypeDeclNode -> TypeDef
    if (LTypeNode <> nil) and (LTypeNode is TMyrTypeRefNode) and
       (TMyrTypeRefNode(LTypeNode).ResolvedDecl <> nil) then
      LTypeNode := TMyrTypeRefNode(LTypeNode).ResolvedDecl;

    // Follow TCPTypeDeclNode -> TypeDef
    if (LTypeNode <> nil) and (LTypeNode is TMyrTypeDeclNode) then
      LTypeDef := TMyrTypeDeclNode(LTypeNode).TypeDef
    else
      LTypeDef := LTypeNode;

    if LTypeDef is TMyrArrayTypeNode then
    begin
      LArr := TMyrScriptArray.Create();
      LValue := TMyrScriptValue.From<TObject>(LArr);
    end
    else if LTypeDef is TMyrRecordTypeNode then
    begin
      LRec := TMyrScriptRecord.Create();
      if (LTypeNode <> nil) and (LTypeNode is TMyrTypeDeclNode) then
        LRec.TypeName := TMyrTypeDeclNode(LTypeNode).DeclName;
      for LFieldNode in TMyrRecordTypeNode(LTypeDef).Fields do
      begin
        if LFieldNode is TMyrFieldDeclNode then
          LRec.SetField(TMyrFieldDeclNode(LFieldNode).FieldName, TMyrScriptValue.Empty);
      end;
      LValue := TMyrScriptValue.From<TObject>(LRec);
    end
    else if LTypeDef is TMyrSetTypeNode then
    begin
      LSet := TMyrScriptSet.Create();
      LValue := TMyrScriptValue.From<TObject>(LSet);
    end;
  end;
  FEnvironment.DeclareVar(ANode.DeclName, LValue, False);
end;

procedure TMyrScriptInterpreter.ExecRoutineDecl(const ANode: TMyrRoutineDeclNode);
begin
  // Register routine name in scope so it can be looked up by calls.
  // The TCPRoutineDeclNode itself carries the body -- no separate storage needed.
  FEnvironment.DeclareVar(ANode.DeclName, TMyrScriptValue.From<TObject>(ANode), False);
end;

procedure TMyrScriptInterpreter.ExecAssign(const ANode: TMyrAssignNode);
var
  LName: string;
  LNewValue: TMyrScriptValue;
  LOldValue: TMyrScriptValue;
  LTarget: TMyrASTNode;
  LBaseValue: TMyrScriptValue;
  LRec: TMyrScriptRecord;
  LArr: TMyrScriptArray;
  LIdx: Int64;
  LFieldName: string;
begin
  LNewValue := EvalExpr(ANode.ValueExpr);
  LTarget := ANode.Target;

  // Simple identifier assignment
  if LTarget is TMyrIdentifierNode then
  begin
    LName := TMyrIdentifierNode(LTarget).IdentName;

    if ANode.Op = aoAssign then
    begin
      FEnvironment.UpdateVar(LName, LNewValue);
    end
    else
    begin
      // Compound assignment -- read old value, apply op, write back
      if FEnvironment.TryGetVar(LName, LOldValue) then
      begin
        LNewValue := DoApplyCompoundOp(ANode.Op, LOldValue, LNewValue);
        FEnvironment.UpdateVar(LName, LNewValue);
      end;
    end;
  end
  else if LTarget is TMyrDotAccessNode then
  begin
    // Record field assignment: rec.field := value
    LBaseValue := EvalExpr(TMyrDotAccessNode(LTarget).BaseExpr);
    if LBaseValue.IsObject and (LBaseValue.AsObject is TMyrScriptRecord) then
    begin
      LRec := TMyrScriptRecord(LBaseValue.AsObject);
      LFieldName := TMyrDotAccessNode(LTarget).MemberName;
      if ANode.Op <> aoAssign then
      begin
        LOldValue := LRec.GetField(LFieldName);
        LNewValue := DoApplyCompoundOp(ANode.Op, LOldValue, LNewValue);
      end;
      LRec.SetField(LFieldName, LNewValue);
    end
    else
      raise Exception.Create('Cannot assign to field of non-record value');
  end
  else if LTarget is TMyrIndexAccessNode then
  begin
    // Array/string index assignment: arr[i] := value
    LBaseValue := EvalExpr(TMyrIndexAccessNode(LTarget).BaseExpr);
    LIdx := ValueToInt(EvalExpr(TMyrIndexAccessNode(LTarget).IndexExpr));
    if LBaseValue.IsObject and (LBaseValue.AsObject is TMyrScriptArray) then
    begin
      LArr := TMyrScriptArray(LBaseValue.AsObject);
      if ANode.Op <> aoAssign then
      begin
        LOldValue := LArr.GetElement(LIdx);
        LNewValue := DoApplyCompoundOp(ANode.Op, LOldValue, LNewValue);
      end;
      LArr.SetElement(LIdx, LNewValue);
    end
    else
      raise Exception.Create('Cannot index-assign to non-array value');
  end
  else if LTarget is TMyrDerefNode then
  begin
    // Pointer dereference assignment: p^ := value
    // In the interpreter, deref is identity -- the pointer IS the object
    // So we need to get the variable name from the base expression and update it
    if TMyrDerefNode(LTarget).BaseExpr is TMyrIdentifierNode then
    begin
      LName := TMyrIdentifierNode(TMyrDerefNode(LTarget).BaseExpr).IdentName;
      if ANode.Op <> aoAssign then
      begin
        if FEnvironment.TryGetVar(LName, LOldValue) then
          LNewValue := DoApplyCompoundOp(ANode.Op, LOldValue, LNewValue);
      end;
      FEnvironment.UpdateVar(LName, LNewValue);
    end
    else
      raise Exception.Create('Cannot assign through complex dereference expression');
  end;
end;

procedure TMyrScriptInterpreter.ExecCallStmt(const ANode: TMyrCallStmtNode);
begin
  // Evaluate the call expression and discard the result
  EvalExpr(ANode.CallExpr);
end;

procedure TMyrScriptInterpreter.ExecIf(const ANode: TMyrIfNode);
begin
  if ValueToBool(EvalExpr(ANode.Condition)) then
    ExecStmtList(ANode.ThenBody)
  else if ANode.ElseBody.Count > 0 then
    ExecStmtList(ANode.ElseBody);
end;

procedure TMyrScriptInterpreter.ExecWhile(const ANode: TMyrWhileNode);
begin
  while ValueToBool(EvalExpr(ANode.Condition)) do
  begin
    ExecStmtList(ANode.Body);
    if FSignal = ssBreak then
    begin
      FSignal := ssNone;
      Break;
    end;
    if FSignal = ssContinue then
      FSignal := ssNone;
    if FSignal = ssReturn then
      Exit;
  end;
end;

procedure TMyrScriptInterpreter.ExecFor(const ANode: TMyrForNode);
var
  LStart: Int64;
  LEnd: Int64;
  LI: Int64;
begin
  LStart := ValueToInt(EvalExpr(ANode.StartExpr));
  LEnd := ValueToInt(EvalExpr(ANode.EndExpr));

  // Declare iterator variable in a new scope
  FEnvironment.PushScope();
  try
    FEnvironment.DeclareVar(ANode.IteratorName, TMyrScriptValue.From<Int64>(LStart), False);

    if ANode.IsDownTo then
    begin
      LI := LStart;
      while LI >= LEnd do
      begin
        FEnvironment.UpdateVar(ANode.IteratorName, TMyrScriptValue.From<Int64>(LI));
        ExecStmtList(ANode.Body);
        if FSignal = ssBreak then
        begin
          FSignal := ssNone;
          Break;
        end;
        if FSignal = ssContinue then
          FSignal := ssNone;
        if FSignal = ssReturn then
          Exit;
        Dec(LI);
      end;
    end
    else
    begin
      LI := LStart;
      while LI <= LEnd do
      begin
        FEnvironment.UpdateVar(ANode.IteratorName, TMyrScriptValue.From<Int64>(LI));
        ExecStmtList(ANode.Body);
        if FSignal = ssBreak then
        begin
          FSignal := ssNone;
          Break;
        end;
        if FSignal = ssContinue then
          FSignal := ssNone;
        if FSignal = ssReturn then
          Exit;
        Inc(LI);
      end;
    end;
  finally
    FEnvironment.PopScope();
  end;
end;

procedure TMyrScriptInterpreter.ExecRepeat(const ANode: TMyrRepeatNode);
begin
  repeat
    ExecStmtList(ANode.Body);
    if FSignal = ssBreak then
    begin
      FSignal := ssNone;
      Break;
    end;
    if FSignal = ssContinue then
      FSignal := ssNone;
    if FSignal = ssReturn then
      Exit;
  until ValueToBool(EvalExpr(ANode.Condition));
end;

procedure TMyrScriptInterpreter.ExecMatch(const ANode: TMyrMatchNode);
var
  LExprValue: TMyrScriptValue;
  LArm: TMyrMatchArmNode;
  LLabel: TMyrMatchLabelNode;
  LLow: TMyrScriptValue;
  LHigh: TMyrScriptValue;
  LMatched: Boolean;
begin
  LExprValue := EvalExpr(ANode.Expr);

  for LArm in ANode.Arms do
  begin
    LMatched := False;
    for LLabel in LArm.Labels do
    begin
      LLow := EvalExpr(LLabel.LowExpr);
      if LLabel.HighExpr <> nil then
      begin
        // Range label: check if value is within range
        LHigh := EvalExpr(LLabel.HighExpr);
        if (ValueToInt(LExprValue) >= ValueToInt(LLow)) and
           (ValueToInt(LExprValue) <= ValueToInt(LHigh)) then
        begin
          LMatched := True;
          Break;
        end;
      end
      else
      begin
        // Single value label
        if LExprValue.IsType<Int64>() and LLow.IsType<Int64>() then
          LMatched := LExprValue.AsInt64 = LLow.AsInt64
        else if LExprValue.IsType<string>() and LLow.IsType<string>() then
          LMatched := LExprValue.AsString = LLow.AsString
        else if LExprValue.IsType<Boolean>() and LLow.IsType<Boolean>() then
          LMatched := LExprValue.IsType<Boolean>() = LLow.IsType<Boolean>()
        else
          LMatched := ValueToFloat(LExprValue) = ValueToFloat(LLow);

        if LMatched then
          Break;
      end;
    end;

    if LMatched then
    begin
      ExecStmtList(LArm.Body);
      Exit;
    end;
  end;

  // No arm matched -- execute else body if present
  if ANode.ElseBody.Count > 0 then
    ExecStmtList(ANode.ElseBody);
end;

procedure TMyrScriptInterpreter.ExecReturn(const ANode: TMyrReturnNode);
begin
  if ANode.ValueExpr <> nil then
    FReturnValue := EvalExpr(ANode.ValueExpr)
  else
    FReturnValue := TMyrScriptValue.Empty;
  FSignal := ssReturn;
end;

procedure TMyrScriptInterpreter.ExecGuard(const ANode: TMyrGuardNode);
var
  LSavedExcCode: Int64;
  LSavedExcMsg: string;
  LBracketEnd: Integer;
  LCodeStr: string;
  LCode: Int64;
begin
  // Save outer exception context
  LSavedExcCode := FCurrentExcCode;
  LSavedExcMsg := FCurrentExcMsg;
  try
    ExecStmtList(ANode.GuardBody);
  except
    on E: Exception do
    begin
      // Parse exception code from ThrowCode format: [code] message
      FCurrentExcCode := 0;
      FCurrentExcMsg := E.Message;
      if (Length(E.Message) > 2) and (E.Message[1] = '[') then
      begin
        LBracketEnd := Pos(']', E.Message);
        if LBracketEnd > 2 then
        begin
          LCodeStr := Copy(E.Message, 2, LBracketEnd - 2);
          if TryStrToInt64(LCodeStr, LCode) then
          begin
            FCurrentExcCode := LCode;
            FCurrentExcMsg := Trim(Copy(E.Message, LBracketEnd + 1, MaxInt));
          end;
        end;
      end;
      if ANode.ExceptBody <> nil then
        ExecStmtList(ANode.ExceptBody);
    end;
  end;
  // Restore outer exception context
  FCurrentExcCode := LSavedExcCode;
  FCurrentExcMsg := LSavedExcMsg;
  if ANode.FinallyBody <> nil then
    ExecStmtList(ANode.FinallyBody);
end;

procedure TMyrScriptInterpreter.ExecThrow(const ANode: TMyrThrowNode);
var
  LMsg: string;
begin
  LMsg := ValueToStr(EvalExpr(ANode.MessageExpr));
  raise Exception.Create(LMsg);
end;

procedure TMyrScriptInterpreter.ExecPrint(const ANode: TMyrPrintNode);
var
  LText: string;
  LFmt: string;
  LArgIdx: Integer;
  I: Integer;
begin
  if ANode.Args.Count = 0 then
    LText := ''
  else if ANode.Args.Count = 1 then
    // Single arg: print directly, no format substitution
    LText := ValueToStr(EvalExpr(ANode.Args[0]))
  else
  begin
    // First arg is format string, remaining args replace {} placeholders
    LFmt := ValueToStr(EvalExpr(ANode.Args[0]));
    LText := '';
    LArgIdx := 1;
    I := 1;
    while I <= Length(LFmt) do
    begin
      if (I < Length(LFmt)) and (LFmt[I] = '{') and (LFmt[I + 1] = '}') then
      begin
        if LArgIdx < ANode.Args.Count then
        begin
          LText := LText + ValueToStr(EvalExpr(ANode.Args[LArgIdx]));
          Inc(LArgIdx);
        end
        else
          LText := LText + '{}';
        Inc(I, 2);
      end
      else
      begin
        LText := LText + LFmt[I];
        Inc(I);
      end;
    end;
  end;

  if FPrintCallback.IsAssigned() then
    FPrintCallback.Callback(LText, ANode.IsLn, FPrintCallback.UserData)
  else
  begin
    if ANode.IsLn then
      WriteLn(LText)
    else
      Write(LText);
  end;
end;

procedure TMyrScriptInterpreter.ExecThrowCode(const ANode: TMyrThrowCodeNode);
var
  LCode: Int64;
  LMsg: string;
begin
  LCode := ValueToInt(EvalExpr(ANode.CodeExpr));
  LMsg := ValueToStr(EvalExpr(ANode.MessageExpr));
  raise Exception.CreateFmt('[%d] %s', [LCode, LMsg]);
end;

procedure TMyrScriptInterpreter.ExecAssertStmt(const ANode: TMyrAssertStmtNode);
var
  LArg0: TMyrScriptValue;
  LArg1: TMyrScriptValue;
  LArg2: TMyrScriptValue;
  LPassed: Boolean;
  LMsg: string;
begin
  LPassed := False;
  LMsg := '';

  case ANode.AssertKind of
    akAssert:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := ValueToBool(LArg0);
      if not LPassed then
        LMsg := 'Assertion failed';
    end;
    akTrue:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := ValueToBool(LArg0);
      if not LPassed then
        LMsg := 'Expected true, got false';
    end;
    akFalse:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := not ValueToBool(LArg0);
      if not LPassed then
        LMsg := 'Expected false, got true';
    end;
    akEq:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LArg1 := EvalExpr(ANode.Args[1]);
      LPassed := (ValueToStr(LArg0) = ValueToStr(LArg1));
      if not LPassed then
        LMsg := Format('Expected %s, got %s', [ValueToStr(LArg0), ValueToStr(LArg1)]);
    end;
    akEqF:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LArg1 := EvalExpr(ANode.Args[1]);
      LArg2 := EvalExpr(ANode.Args[2]);
      LPassed := Abs(ValueToFloat(LArg0) - ValueToFloat(LArg1)) <= ValueToFloat(LArg2);
      if not LPassed then
        LMsg := Format('Expected %s within %s of %s',
          [ValueToStr(LArg0), ValueToStr(LArg2), ValueToStr(LArg1)]);
    end;
    akNil:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := LArg0.IsEmpty;
      if not LPassed then
        LMsg := Format('Expected nil, got %s', [ValueToStr(LArg0)]);
    end;
    akNotNil:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := not LArg0.IsEmpty;
      if not LPassed then
        LMsg := 'Expected non-nil, got nil';
    end;
    akFail:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := False;
      LMsg := ValueToStr(LArg0);
    end;
  end;

  if not LPassed then
    raise Exception.Create('Assertion failed: ' + LMsg);
end;

procedure TMyrScriptInterpreter.ExecSetLength(const ANode: TMyrSetLengthNode);
var
  LTarget: TMyrScriptValue;
  LLength: Int64;
  LArr: TMyrScriptArray;
begin
  LTarget := EvalExpr(ANode.TargetExpr);
  LLength := ValueToInt(EvalExpr(ANode.LengthExpr));
  if LTarget.IsObject and (LTarget.AsObject is TMyrScriptArray) then
  begin
    LArr := TMyrScriptArray(LTarget.AsObject);
    LArr.Resize(LLength);
  end
  else
    raise Exception.Create('setlength target must be an array');
end;

procedure TMyrScriptInterpreter.ExecDirective(const ANode: TMyrDirectiveNode);
begin
  // Statement-level directives: @breakpoint and @message
  // @message is handled at parse time (compiler message). No runtime action.
  // @breakpoint has no effect in the interpreter.
end;

procedure TMyrScriptInterpreter.ExecNew(const ANode: TMyrNewNode);
var
  LRec: TMyrScriptRecord;
  LTypeDecl: TMyrASTNode;
  LTypeDef: TMyrASTNode;
  LPointerType: TMyrPointerTypeNode;
  LTargetTypeDecl: TMyrTypeDeclNode;
  LRecordType: TMyrRecordTypeNode;
  LFieldNode: TMyrASTNode;
  LName: string;
begin
  // new(p) -- allocate a default-initialized record for the pointer's target type
  // The argument is an identifier (the pointer variable)
  if not (ANode.ArgExpr is TMyrIdentifierNode) then
    raise Exception.Create('new() argument must be an identifier');

  LName := TMyrIdentifierNode(ANode.ArgExpr).IdentName;

  // Resolve the pointer's target type from the enriched AST
  LRec := TMyrScriptRecord.Create();
  LRec.TypeName := 'heap';

  // Try to resolve the pointed-to type and default-initialize fields
  LTypeDecl := TMyrExprNode(ANode.ArgExpr).ResolvedType;
  if LTypeDecl <> nil then
  begin
    // Follow type declaration chain to get the pointer's target type
    if (LTypeDecl is TMyrTypeDeclNode) and
       (TMyrTypeDeclNode(LTypeDecl).TypeDef is TMyrPointerTypeNode) then
    begin
      LPointerType := TMyrPointerTypeNode(TMyrTypeDeclNode(LTypeDecl).TypeDef);
      if (LPointerType.TargetType <> nil) and
         (LPointerType.TargetType is TMyrTypeDeclNode) then
      begin
        LTargetTypeDecl := TMyrTypeDeclNode(LPointerType.TargetType);
        LRec.TypeName := LTargetTypeDecl.DeclName;
        LTypeDef := LTargetTypeDecl.TypeDef;
        if LTypeDef is TMyrRecordTypeNode then
        begin
          LRecordType := TMyrRecordTypeNode(LTypeDef);
          for LFieldNode in LRecordType.Fields do
          begin
            if LFieldNode is TMyrFieldDeclNode then
              LRec.SetField(TMyrFieldDeclNode(LFieldNode).FieldName, TMyrScriptValue.Empty);
          end;
        end;
      end;
    end;
  end;

  FEnvironment.UpdateVar(LName, TMyrScriptValue.From<TObject>(LRec));
end;

procedure TMyrScriptInterpreter.ExecDispose(const ANode: TMyrDisposeNode);
var
  LName: string;
begin
  if not (ANode.ArgExpr is TMyrIdentifierNode) then
    raise Exception.Create('dispose() argument must be an identifier');

  LName := TMyrIdentifierNode(ANode.ArgExpr).IdentName;
  // UpdateVar frees the old composite wrapper when replacing with Empty
  FEnvironment.UpdateVar(LName, TMyrScriptValue.Empty);
end;

procedure TMyrScriptInterpreter.ExecGetMem(const ANode: TMyrGetMemNode);
var
  LName: string;
  LBuf: TMyrScriptBuffer;
begin
  if not (ANode.ArgExpr is TMyrIdentifierNode) then
    raise Exception.Create('getmem() argument must be an identifier');

  LName := TMyrIdentifierNode(ANode.ArgExpr).IdentName;

  // Allocate a buffer -- size comes from the type info
  LBuf := TMyrScriptBuffer.Create();
  LBuf.Allocate(1); // Default 1 byte; real size determined by type
  FEnvironment.UpdateVar(LName, TMyrScriptValue.From<TObject>(LBuf));
end;

procedure TMyrScriptInterpreter.ExecFreeMem(const ANode: TMyrFreeMemNode);
var
  LName: string;
begin
  if not (ANode.ArgExpr is TMyrIdentifierNode) then
    raise Exception.Create('freemem() argument must be an identifier');

  LName := TMyrIdentifierNode(ANode.ArgExpr).IdentName;
  // UpdateVar frees the old composite wrapper when replacing with Empty
  FEnvironment.UpdateVar(LName, TMyrScriptValue.Empty);
end;

procedure TMyrScriptInterpreter.ExecResizeMem(const ANode: TMyrResizeMemNode);
var
  LPtrValue: TMyrScriptValue;
  LNewSize: Int64;
  LBuf: TMyrScriptBuffer;
begin
  LPtrValue := EvalExpr(ANode.PtrExpr);
  LNewSize := ValueToInt(EvalExpr(ANode.SizeExpr));

  if LPtrValue.IsObject and (LPtrValue.AsObject is TMyrScriptBuffer) then
  begin
    LBuf := TMyrScriptBuffer(LPtrValue.AsObject);
    LBuf.Resize(LNewSize);
  end
  else
    raise Exception.Create('resizemem target must be a memory buffer');
end;

function TMyrScriptInterpreter.DoApplyCompoundOp(const AOp: TMyrAssignOp;
  const AOld: TMyrScriptValue; const ANew: TMyrScriptValue): TMyrScriptValue;
begin
  if AOp = aoPlusAssign then
  begin
    if AOld.IsType<Int64>() and ANew.IsType<Int64>() then
      Result := TMyrScriptValue.From<Int64>(AOld.AsInt64 + ANew.AsInt64)
    else
      Result := TMyrScriptValue.From<Double>(ValueToFloat(AOld) + ValueToFloat(ANew));
  end
  else if AOp = aoMinusAssign then
  begin
    if AOld.IsType<Int64>() and ANew.IsType<Int64>() then
      Result := TMyrScriptValue.From<Int64>(AOld.AsInt64 - ANew.AsInt64)
    else
      Result := TMyrScriptValue.From<Double>(ValueToFloat(AOld) - ValueToFloat(ANew));
  end
  else if AOp = aoMulAssign then
  begin
    if AOld.IsType<Int64>() and ANew.IsType<Int64>() then
      Result := TMyrScriptValue.From<Int64>(AOld.AsInt64 * ANew.AsInt64)
    else
      Result := TMyrScriptValue.From<Double>(ValueToFloat(AOld) * ValueToFloat(ANew));
  end
  else if AOp = aoDivAssign then
    Result := TMyrScriptValue.From<Double>(ValueToFloat(AOld) / ValueToFloat(ANew))
  else
    Result := ANew;
end;

function TMyrScriptInterpreter.EvalBinaryExpr(const ANode: TMyrBinaryExprNode): TMyrScriptValue;
var
  LLeft: TMyrScriptValue;
  LRight: TMyrScriptValue;
  LLI: Int64;
  LRI: Int64;
  LLF: Double;
  LRF: Double;
  LBothInt: Boolean;
begin
  LLeft := EvalExpr(ANode.Left);
  LRight := EvalExpr(ANode.Right);

  // String concatenation
  if (ANode.Op = boAdd) and (LLeft.IsType<string>() or LRight.IsType<string>()) then
    Exit(TMyrScriptValue.From<string>(ValueToStr(LLeft) + ValueToStr(LRight)));

  // String comparison
  if LLeft.IsType<string>() and LRight.IsType<string>() then
  begin
    case ANode.Op of
      boEq:        Exit(TMyrScriptValue.From<Boolean>(LLeft.AsString = LRight.AsString));
      boNotEq:     Exit(TMyrScriptValue.From<Boolean>(LLeft.AsString <> LRight.AsString));
      boLess:      Exit(TMyrScriptValue.From<Boolean>(LLeft.AsString < LRight.AsString));
      boGreater:   Exit(TMyrScriptValue.From<Boolean>(LLeft.AsString > LRight.AsString));
      boLessEq:    Exit(TMyrScriptValue.From<Boolean>(LLeft.AsString <= LRight.AsString));
      boGreaterEq: Exit(TMyrScriptValue.From<Boolean>(LLeft.AsString >= LRight.AsString));
    end;
  end;

  // Boolean operations
  if LLeft.IsType<Boolean>() and LRight.IsType<Boolean>() then
  begin
    case ANode.Op of
      boLogicalAnd, boAnd: Exit(TMyrScriptValue.From<Boolean>(LLeft.AsBoolean and LRight.AsBoolean));
      boLogicalOr, boOr:   Exit(TMyrScriptValue.From<Boolean>(LLeft.AsBoolean or LRight.AsBoolean));
      boXor:               Exit(TMyrScriptValue.From<Boolean>(LLeft.AsBoolean xor LRight.AsBoolean));
      boEq:                Exit(TMyrScriptValue.From<Boolean>(LLeft.AsBoolean = LRight.AsBoolean));
      boNotEq:             Exit(TMyrScriptValue.From<Boolean>(LLeft.AsBoolean <> LRight.AsBoolean));
    end;
  end;

  // Numeric operations
  LBothInt := LLeft.IsType<Int64>() and LRight.IsType<Int64>();

  if LBothInt then
  begin
    LLI := LLeft.AsInt64;
    LRI := LRight.AsInt64;
    case ANode.Op of
      boAdd:      Exit(TMyrScriptValue.From<Int64>(LLI + LRI));
      boSub:      Exit(TMyrScriptValue.From<Int64>(LLI - LRI));
      boMul:      Exit(TMyrScriptValue.From<Int64>(LLI * LRI));
      boIntDiv:   Exit(TMyrScriptValue.From<Int64>(LLI div LRI));
      boMod:      Exit(TMyrScriptValue.From<Int64>(LLI mod LRI));
      boDiv:      Exit(TMyrScriptValue.From<Double>(LLI / LRI));
      boAnd:      Exit(TMyrScriptValue.From<Int64>(LLI and LRI));
      boOr:       Exit(TMyrScriptValue.From<Int64>(LLI or LRI));
      boXor:      Exit(TMyrScriptValue.From<Int64>(LLI xor LRI));
      boShl:      Exit(TMyrScriptValue.From<Int64>(LLI shl LRI));
      boShr:      Exit(TMyrScriptValue.From<Int64>(LLI shr LRI));
      boEq:       Exit(TMyrScriptValue.From<Boolean>(LLI = LRI));
      boNotEq:    Exit(TMyrScriptValue.From<Boolean>(LLI <> LRI));
      boLess:     Exit(TMyrScriptValue.From<Boolean>(LLI < LRI));
      boGreater:  Exit(TMyrScriptValue.From<Boolean>(LLI > LRI));
      boLessEq:   Exit(TMyrScriptValue.From<Boolean>(LLI <= LRI));
      boGreaterEq:Exit(TMyrScriptValue.From<Boolean>(LLI >= LRI));
    end;
  end
  else
  begin
    // Float arithmetic
    LLF := ValueToFloat(LLeft);
    LRF := ValueToFloat(LRight);
    case ANode.Op of
      boAdd:      Exit(TMyrScriptValue.From<Double>(LLF + LRF));
      boSub:      Exit(TMyrScriptValue.From<Double>(LLF - LRF));
      boMul:      Exit(TMyrScriptValue.From<Double>(LLF * LRF));
      boDiv:      Exit(TMyrScriptValue.From<Double>(LLF / LRF));
      boEq:       Exit(TMyrScriptValue.From<Boolean>(LLF = LRF));
      boNotEq:    Exit(TMyrScriptValue.From<Boolean>(LLF <> LRF));
      boLess:     Exit(TMyrScriptValue.From<Boolean>(LLF < LRF));
      boGreater:  Exit(TMyrScriptValue.From<Boolean>(LLF > LRF));
      boLessEq:   Exit(TMyrScriptValue.From<Boolean>(LLF <= LRF));
      boGreaterEq:Exit(TMyrScriptValue.From<Boolean>(LLF >= LRF));
    end;
  end;

  // Set membership: value in set
  if (ANode.Op = boIn) and LRight.IsObject and (LRight.AsObject is TMyrScriptSet) then
    Exit(TMyrScriptValue.From<Boolean>(
      TMyrScriptSet(LRight.AsObject).Contains(ValueToInt(LLeft))));

  Result := TMyrScriptValue.Empty;
end;

function TMyrScriptInterpreter.EvalUnaryExpr(const ANode: TMyrUnaryExprNode): TMyrScriptValue;
var
  LValue: TMyrScriptValue;
begin
  LValue := EvalExpr(ANode.Operand);
  case ANode.Op of
    uoNegate:
      begin
        if LValue.IsType<Int64>() then
          Result := TMyrScriptValue.From<Int64>(-LValue.AsInt64)
        else
          Result := TMyrScriptValue.From<Double>(-ValueToFloat(LValue));
      end;
    uoPositive:
      Result := LValue;
    uoNot:
      begin
        if LValue.IsType<Boolean>() then
          Result := TMyrScriptValue.From<Boolean>(not LValue.AsBoolean)
        else if LValue.IsType<Int64>() then
          Result := TMyrScriptValue.From<Int64>(not LValue.AsInt64)
        else
          Result := TMyrScriptValue.From<Boolean>(not ValueToBool(LValue));
      end;
  else
    Result := TMyrScriptValue.Empty;
  end;
end;

function TMyrScriptInterpreter.EvalCallExpr(const ANode: TMyrCallExprNode): TMyrScriptValue;
var
  LRoutine: TMyrRoutineDeclNode;
  LArgs: TArray<TMyrScriptValue>;
  LBuiltinFunc: TCallback<TMyrScriptRoutineFunc>;
  LI: Integer;
  LParam: TMyrParamDeclNode;
begin
  Result := TMyrScriptValue.Empty;

  // Resolve the routine from the semantic pass
  if not (ANode.ResolvedRoutine is TMyrRoutineDeclNode) then
    Exit;

  LRoutine := TMyrRoutineDeclNode(ANode.ResolvedRoutine);

  // Evaluate arguments
  SetLength(LArgs, ANode.Args.Count);
  for LI := 0 to ANode.Args.Count - 1 do
    LArgs[LI] := EvalExpr(ANode.Args[LI]);

  // Check if this is a builtin
  if FFuncs.TryGetValue(LRoutine, LBuiltinFunc) then
    Exit(LBuiltinFunc.Callback(LArgs, Self, LBuiltinFunc.UserData));

  // User-defined routine -- execute body in a new scope
  FEnvironment.PushScope();
  try
    // Bind parameters
    for LI := 0 to LRoutine.Params.Count - 1 do
    begin
      LParam := LRoutine.Params[LI];
      if LI < Length(LArgs) then
        FEnvironment.DeclareVar(LParam.ParamName, LArgs[LI], False)
      else
        FEnvironment.DeclareVar(LParam.ParamName, TMyrScriptValue.Empty, False);
    end;

    // Declare local consts
    for LI := 0 to LRoutine.LocalConsts.Count - 1 do
      ExecConstDecl(LRoutine.LocalConsts[LI]);

    // Declare local vars
    for LI := 0 to LRoutine.LocalVars.Count - 1 do
      ExecVarDecl(LRoutine.LocalVars[LI]);

    // Execute body
    ExecStmtList(LRoutine.Body);

    // Capture return value
    if FSignal = ssReturn then
    begin
      FSignal := ssNone;
      Result := FReturnValue;
      FReturnValue := TMyrScriptValue.Empty;
    end;
  finally
    FEnvironment.PopScope();
  end;
end;

function TMyrScriptInterpreter.EvalIdentifier(const ANode: TMyrIdentifierNode): TMyrScriptValue;
begin
  if not FEnvironment.TryGetVar(ANode.IdentName, Result) then
    Result := TMyrScriptValue.Empty;
end;

function TMyrScriptInterpreter.EvalIntrinsic(const ANode: TMyrIntrinsicExprNode): TMyrScriptValue;
var
  LArg: TMyrScriptValue;
begin
  Result := TMyrScriptValue.Empty;

  case ANode.IntrinsicKind of
    ikLen:
    begin
      if ANode.Args.Count > 0 then
      begin
        LArg := EvalExpr(ANode.Args[0]);
        if LArg.IsType<string>() then
          Result := TMyrScriptValue.From<Int64>(Length(LArg.AsString))
        else if LArg.IsObject and (LArg.AsObject is TMyrScriptArray) then
          Result := TMyrScriptValue.From<Int64>(TMyrScriptArray(LArg.AsObject).GetCount());
      end;
    end;
    ikSize:
    begin
      // size() returns compile-time size -- in interpreter, return a reasonable default
      // based on the resolved type
      Result := TMyrScriptValue.From<Int64>(0);
    end;
    ikExcCode:
      Result := TMyrScriptValue.From<Int64>(FCurrentExcCode);
    ikExcMsg:
      Result := TMyrScriptValue.From<string>(FCurrentExcMsg);
    ikUtf8, ikCStr, ikWStr:
    begin
      // String conversion intrinsics -- in the interpreter, strings are all Delphi strings
      // so these are pass-through
      if ANode.Args.Count > 0 then
        Result := EvalExpr(ANode.Args[0]);
    end;
    ikParamCount:
      Result := TMyrScriptValue.From<Int64>(ParamCount());
    ikParamStr:
    begin
      if ANode.Args.Count > 0 then
      begin
        LArg := EvalExpr(ANode.Args[0]);
        Result := TMyrScriptValue.From<string>(ParamStr(ValueToInt(LArg)));
      end;
    end;
  end;
end;

function TMyrScriptInterpreter.EvalTypeCast(const ANode: TMyrTypeCastExprNode): TMyrScriptValue;
var
  LValue: TMyrScriptValue;
  LTargetType: TMyrTypeDeclNode;
begin
  LValue := EvalExpr(ANode.Expr);
  Result := LValue;

  // Resolve target type
  if not (ANode.TargetType is TMyrTypeDeclNode) then
    Exit;

  LTargetType := TMyrTypeDeclNode(ANode.TargetType);

  case LTargetType.PrimitiveKind of
    tkInt8, tkInt16, tkInt32, tkInt64:
      Result := TMyrScriptValue.From<Int64>(ValueToInt(LValue));
    tkUInt8, tkUInt16, tkUInt32, tkUInt64:
      Result := TMyrScriptValue.From<Int64>(ValueToInt(LValue));
    tkFloat32, tkFloat64:
      Result := TMyrScriptValue.From<Double>(ValueToFloat(LValue));
    tkBoolean:
      Result := TMyrScriptValue.From<Boolean>(ValueToBool(LValue));
    tkString:
      Result := TMyrScriptValue.From<string>(ValueToStr(LValue));
  end;
end;

function TMyrScriptInterpreter.EvalDotAccess(const ANode: TMyrDotAccessNode): TMyrScriptValue;
var
  LBaseValue: TMyrScriptValue;
  LRec: TMyrScriptRecord;
  LTypeDecl: TMyrTypeDeclNode;
  LChoicesType: TMyrChoicesTypeNode;
  LMember: TMyrChoicesValueNode;
  LI: Integer;
begin
  Result := TMyrScriptValue.Empty;

  case ANode.AccessKind of
    dakField:
    begin
      // Record field access: base.member
      LBaseValue := EvalExpr(ANode.BaseExpr);
      if LBaseValue.IsObject and (LBaseValue.AsObject is TMyrScriptRecord) then
      begin
        LRec := TMyrScriptRecord(LBaseValue.AsObject);
        Result := LRec.GetField(ANode.MemberName);
      end
      else
        raise Exception.CreateFmt('Cannot access field "%s" on non-record value',
          [ANode.MemberName]);
    end;
    dakModule:
    begin
      // Module-qualified access: Module.Symbol
      // The symbol should resolve to a constant or variable in the imported module
      // For the interpreter, the semantic pass resolved this -- look up by member name
      if (ANode.ResolvedDecl <> nil) and (ANode.ResolvedDecl is TMyrConstDeclNode) then
        Result := EvalExpr(TMyrConstDeclNode(ANode.ResolvedDecl).ValueExpr)
      else if (ANode.ResolvedDecl <> nil) and (ANode.ResolvedDecl is TMyrVarDeclNode) then
      begin
        if not FEnvironment.TryGetVar(ANode.MemberName, Result) then
          Result := TMyrScriptValue.Empty;
      end
      else
        raise Exception.CreateFmt('Cannot resolve module member "%s"', [ANode.MemberName]);
    end;
    dakChoices:
    begin
      // Choices (enum) member: MyEnum.Value -- resolve to ordinal
      if (ANode.ResolvedType <> nil) and (ANode.ResolvedType is TMyrTypeDeclNode) then
      begin
        LTypeDecl := TMyrTypeDeclNode(ANode.ResolvedType);
        if LTypeDecl.TypeDef is TMyrChoicesTypeNode then
        begin
          LChoicesType := TMyrChoicesTypeNode(LTypeDecl.TypeDef);
          for LI := 0 to LChoicesType.Members.Count - 1 do
          begin
            LMember := LChoicesType.Members[LI];
            if LMember.MemberName = ANode.MemberName then
            begin
              // If member has an explicit value, evaluate it; otherwise use ordinal index
              if LMember.ValueExpr <> nil then
                Result := EvalExpr(LMember.ValueExpr)
              else
                Result := TMyrScriptValue.From<Int64>(LI);
              Exit;
            end;
          end;
          raise Exception.CreateFmt('Choices member "%s" not found', [ANode.MemberName]);
        end;
      end;
    end;
  end;
end;

function TMyrScriptInterpreter.EvalIndexAccess(const ANode: TMyrIndexAccessNode): TMyrScriptValue;
var
  LBaseValue: TMyrScriptValue;
  LIndex: Int64;
  LArr: TMyrScriptArray;
  LStr: string;
begin
  LBaseValue := EvalExpr(ANode.BaseExpr);
  LIndex := ValueToInt(EvalExpr(ANode.IndexExpr));

  if LBaseValue.IsObject and (LBaseValue.AsObject is TMyrScriptArray) then
  begin
    LArr := TMyrScriptArray(LBaseValue.AsObject);
    Result := LArr.GetElement(LIndex);
  end
  else if LBaseValue.IsType<string>() then
  begin
    // String character access (1-based in Myrissa)
    LStr := LBaseValue.AsString;
    if (LIndex >= 1) and (LIndex <= Length(LStr)) then
      Result := TMyrScriptValue.From<string>(LStr[LIndex])
    else
      raise Exception.CreateFmt('String index %d out of bounds [1..%d]',
        [LIndex, Length(LStr)]);
  end
  else
    raise Exception.Create('Cannot index into non-array/non-string value');
end;

function TMyrScriptInterpreter.EvalDeref(const ANode: TMyrDerefNode): TMyrScriptValue;
begin
  // In the interpreter, a pointer is just a TValue holding a TObject reference.
  // Dereferencing returns the same TValue -- the object IS the pointed-to value.
  Result := EvalExpr(ANode.BaseExpr);
  if Result.IsEmpty then
    raise Exception.Create('Nil pointer dereference');
end;

function TMyrScriptInterpreter.EvalSetLiteral(const ANode: TMyrSetLiteralExprNode): TMyrScriptValue;
var
  LSet: TMyrScriptSet;
  LElem: TMyrSetElementNode;
  LLow: Int64;
  LHigh: Int64;
begin
  LSet := TMyrScriptSet.Create();
  for LElem in ANode.Elements do
  begin
    LLow := ValueToInt(EvalExpr(LElem.LowExpr));
    if LElem.HighExpr <> nil then
    begin
      LHigh := ValueToInt(EvalExpr(LElem.HighExpr));
      LSet.AddRange(LLow, LHigh);
    end
    else
      LSet.Add(LLow);
  end;
  Result := TMyrScriptValue.From<TObject>(LSet);
end;

function TMyrScriptInterpreter.EvalRecordLiteral(const ANode: TMyrRecordLiteralNode): TMyrScriptValue;
var
  LRec: TMyrScriptRecord;
  LFieldInit: TMyrFieldInitNode;
begin
  LRec := TMyrScriptRecord.Create();
  LRec.TypeName := ANode.TypeName;
  for LFieldInit in ANode.FieldInits do
    LRec.SetField(LFieldInit.FieldName, EvalExpr(LFieldInit.ValueExpr));
  Result := TMyrScriptValue.From<TObject>(LRec);
end;

function TMyrScriptInterpreter.ValueToStr(const AValue: TMyrScriptValue): string;
begin
  if AValue.IsEmpty then
    Result := 'nil'
  else if AValue.IsType<string>() then
    Result := AValue.AsString
  else if AValue.IsType<Int64>() then
    Result := IntToStr(AValue.AsInt64)
  else if AValue.IsType<Double>() then
    Result := FloatToStr(AValue.AsType<Double>())
  else if AValue.IsType<Boolean>() then
  begin
    if AValue.AsBoolean then
      Result := 'true'
    else
      Result := 'false';
  end
  else
    Result := AValue.ToString();
end;

function TMyrScriptInterpreter.ValueToBool(const AValue: TMyrScriptValue): Boolean;
begin
  if AValue.IsEmpty then
    Result := False
  else if AValue.IsType<Boolean>() then
    Result := AValue.AsBoolean
  else if AValue.IsType<Int64>() then
    Result := AValue.AsInt64 <> 0
  else if AValue.IsType<Double>() then
    Result := AValue.AsType<Double>() <> 0.0
  else if AValue.IsType<string>() then
    Result := AValue.AsString <> ''
  else
    Result := True;
end;

function TMyrScriptInterpreter.ValueToInt(const AValue: TMyrScriptValue): Int64;
begin
  if AValue.IsEmpty then
    Result := 0
  else if AValue.IsType<Int64>() then
    Result := AValue.AsInt64
  else if AValue.IsType<Double>() then
    Result := Round(AValue.AsType<Double>())
  else if AValue.IsType<Boolean>() then
  begin
    if AValue.AsBoolean then
      Result := 1
    else
      Result := 0;
  end
  else
    Result := 0;
end;

function TMyrScriptInterpreter.ValueToFloat(const AValue: TMyrScriptValue): Double;
begin
  if AValue.IsEmpty then
    Result := 0.0
  else if AValue.IsType<Double>() then
    Result := AValue.AsType<Double>()
  else if AValue.IsType<Int64>() then
    Result := AValue.AsInt64
  else if AValue.IsType<Boolean>() then
  begin
    if AValue.AsBoolean then
      Result := 1.0
    else
      Result := 0.0;
  end
  else
    Result := 0.0;
end;

{ TMyrScriptSemantics }
procedure TMyrScriptSemantics.Analyze(const AMasterAST: TMyrMasterAST);
begin
  FMasterAST := AMasterAST;

  // Scripts are single-module -- skip topological sort, analyze directly
  if FMasterAST.ModuleCount() > 0 then
    DoAnalyzeModule(FMasterAST.GetModuleAt(0));
end;

procedure TMyrScriptSemantics.DoAnalyzeModule(const AModule: TMyrModuleNode);
begin
  // Scripts use mkExe internally, so inherited validation passes.
  // Imports list is empty for scripts, so import resolution is a no-op.
  inherited;
end;

{ TMyrScriptEngine }
constructor TMyrScriptEngine.Create();
begin
  inherited;

  FExtension := 'mys';
  FParser := TMyrScriptParser.Create();
  FParser.SetErrors(FErrors);
  FSemantics := TMyrScriptSemantics.Create();
  FSemantics.SetErrors(FErrors);
  FInterpreter := TMyrScriptInterpreter.Create();
  FInterpreter.SetErrors(FErrors);
  FMasterAST := TMyrMasterAST.Create();
  FSyntheticDecls := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrScriptEngine.Destroy();
begin
  FSyntheticDecls.Free();
  FMasterAST.Free();
  FInterpreter.Free();
  FSemantics.Free();
  FParser.Free();

  inherited;
end;

procedure TMyrScriptEngine.SetErrors(const AErrors: TErrors);
begin
  inherited SetErrors(AErrors);

  if FParser <> nil then
    FParser.SetErrors(AErrors);
  if FSemantics <> nil then
    FSemantics.SetErrors(AErrors);
  if FInterpreter <> nil then
    FInterpreter.SetErrors(AErrors);
end;

procedure TMyrScriptEngine.SetStatusCallback(const ACallback: TStatusCallback;
  const AUserData: Pointer);
begin
  inherited SetStatusCallback(ACallback, AUserData);

  if FParser <> nil then
    FParser.SetStatusCallback(ACallback, AUserData);
  if FSemantics <> nil then
    FSemantics.SetStatusCallback(ACallback, AUserData);
  if FInterpreter <> nil then
    FInterpreter.SetStatusCallback(ACallback, AUserData);
end;

procedure TMyrScriptEngine.SetExtension(const AExt: string);
begin
  FExtension := AExt;
end;

procedure TMyrScriptEngine.SetPrintCallback(const ACallback: TMyrScriptPrintCallback;
  const AUserData: Pointer);
var
  LCB: TCallback<TMyrScriptPrintCallback>;
begin
  LCB.Callback := ACallback;
  LCB.UserData := AUserData;
  FInterpreter.PrintCallback := LCB;
end;

procedure TMyrScriptEngine.RegisterGlobalRoutine(const ADeclaration: string;
  const AFunc: TMyrScriptRoutineFunc; const AUserData: Pointer);
var
  LSource: string;
  LParser: TMyrScriptParser;
  LTempAST: TMyrMasterAST;
  LModule: TMyrModuleNode;
  LDecl: TMyrRoutineDeclNode;
begin
  // Wrap the declaration in a minimal module so the parser can handle it
  LSource := Format('''
    module script _synthetic;
    %s;
    begin
    end;
    begin
    end.
    ''',
    [ADeclaration]
  );

  LModule := nil;
  LParser := TMyrScriptParser.Create();
  try
    LTempAST := TMyrMasterAST.Create();
    try
      LModule := LParser.ParseModuleFromString(LSource, '_synthetic.cps', LTempAST);
      if (LModule = nil) or LParser.GetErrors().HasErrors() then
      begin
        FErrors.Add(esError, MYR_ERR_SCR_002,
          'Invalid routine declaration: %s', [ADeclaration]);
        Exit;
      end;

      // Extract the routine node from the parsed module
      if (LModule.Declarations.Count = 0) or
        not (LModule.Declarations[0] is TMyrRoutineDeclNode) then
      begin
        FErrors.Add(esError, MYR_ERR_SCR_002,
          'Invalid routine declaration: %s', [ADeclaration]);
        Exit;
      end;

      LDecl := TMyrRoutineDeclNode(LModule.Declarations.Extract(LModule.Declarations[0]));
      LDecl.IsExternal := True;
      LDecl.IsPublic := True;
      LDecl.Body.Clear();
      FSyntheticDecls.Add(LDecl);
      FInterpreter.RegisterBuiltin(LDecl, AFunc, AUserData);
    finally
      LModule.Free();
      LTempAST.Free();
    end;
  finally
    LParser.Free();
  end;
end;

procedure TMyrScriptEngine.RegisterGlobalData(const ADeclaration: string);
var
  LSource: string;
  LParser: TMyrScriptParser;
  LTempAST: TMyrMasterAST;
  LModule: TMyrModuleNode;
  LDecl: TMyrASTNode;
  I: Integer;
begin
  // Wrap the declaration in a minimal module so the parser can handle it
  LSource := Format('''
    module script _synthetic;
    %s
    begin
    end.
    ''',
    [ADeclaration]
  );

  LModule := nil;
  LParser := TMyrScriptParser.Create();
  try
    LTempAST := TMyrMasterAST.Create();
    try
      LModule := LParser.ParseModuleFromString(LSource, '_synthetic.cps', LTempAST);
      if (LModule = nil) or LParser.GetErrors().HasErrors() then
      begin
        FErrors.Add(esError, MYR_ERR_SCR_003,
          'Invalid data declaration: %s', [ADeclaration]);
        Exit;
      end;

      // Extract all declarations from the parsed module
      for I := LModule.Declarations.Count - 1 downto 0 do
      begin
        LDecl := LModule.Declarations.Extract(LModule.Declarations[I]);
        FSyntheticDecls.Insert(0, LDecl);
      end;
    finally
      LModule.Free();
      LTempAST.Free();
    end;
  finally
    LParser.Free();
  end;
end;

function TMyrScriptEngine.ExecuteFile(const AFilename: string): Boolean;
var
  LResolved: string;
  LSource: string;
begin
  LResolved := TUtils.ResolvePath(TPath.ChangeExtension(AFilename, FExtension));

  if not TFile.Exists(LResolved) then
  begin
    FErrors.Add(esError, MYR_ERR_SCR_001,
      'Script file not found: %s', [LResolved]);
    Result := False;
    Exit;
  end;

  LSource := TFile.ReadAllText(LResolved, TEncoding.UTF8);
  Result := ExecuteSource(LSource, LResolved);
end;

function TMyrScriptEngine.ExecuteSource(const ASource: string;
  const AFilename: string): Boolean;
var
  LModule: TMyrModuleNode;
  I: Integer;
begin
  // Bail if registration errors exist
  if FErrors.HasErrors() then
  begin
    Result := False;
    Exit;
  end;

  // Clear previous execution state
  FErrors.Clear();
  FMasterAST.Free();
  FMasterAST := TMyrMasterAST.Create();

  // Parse
  LModule := FParser.ParseModuleFromString(ASource, AFilename, FMasterAST);
  if (LModule = nil) or FErrors.HasErrors() then
  begin
    Result := False;
    Exit;
  end;

  // Inject synthetic builtin declarations at the front so semantics sees them
  for I := FSyntheticDecls.Count - 1 downto 0 do
    LModule.Declarations.Insert(0, FSyntheticDecls[I]);

  // Add module to master AST
  FMasterAST.AddModule(LModule);

  // Semantic analysis
  FSemantics.Analyze(FMasterAST);
  if FErrors.HasErrors() then
  begin
    // Remove synthetic decls so they are not freed with the module
    for I := 0 to FSyntheticDecls.Count - 1 do
      LModule.Declarations.Extract(FSyntheticDecls[I]);
    Result := False;
    Exit;
  end;

  // Execute
  try
    FInterpreter.Execute(LModule);
  except
    on E: Exception do
      FErrors.Add(esError, MYR_ERR_SCR_004, '%s', [E.Message]);
  end;

  // Remove synthetic decls so they are not freed with the module
  for I := 0 to FSyntheticDecls.Count - 1 do
    LModule.Declarations.Extract(FSyntheticDecls[I]);

  Result := not FErrors.HasErrors();
end;

end.
