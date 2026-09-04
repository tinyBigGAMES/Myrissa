{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Myrissa.Emitter - AST-to-TMyrNativeBackend code generation

  Walks the parsed and semantically validated AST (from Myrissa.Frontend) and
  emits TMyrNativeBackend fluent API calls to produce native code. Pure visitor --
  all data comes from the AST. No side state, no caches, no dictionaries.
===============================================================================}

unit Myrissa.Emitter;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  Myrissa.Backend,
  Myrissa.Frontend;

const
  MYR_ERR_EMT_001 = 'EMT001';  // Unsupported AST node in statement context
  MYR_ERR_EMT_002 = 'EMT002';  // Unsupported AST node in expression context
  MYR_ERR_EMT_003 = 'EMT003';  // Unsupported type mapping
  MYR_ERR_EMT_004 = 'EMT004';  // Unsupported binary operator
  MYR_ERR_EMT_005 = 'EMT005';  // Unsupported unary operator
  MYR_ERR_EMT_006 = 'EMT006';  // Unsupported assign operator

type

  { TMyrEmitter }
  TMyrEmitter = class(TBaseObject)
  protected
    FBackend: TMyrNativeBackend;
    FModule: TMyrModuleNode;

    // Static libs whose lifecycle routines have already been imported
    FLifecycleInits: TList<string>;   // static libs whose __rt_module_init_<n> was imported
    FLifecycleFinals: TList<string>;  // static libs whose __rt_module_finalize_<n> was imported
    FLifecycleChecked: TList<string>; // static libs already probed for lifecycle symbols
    FStrTempSeq: Integer;             // sequence for emitter-created string temp slots

    // Module-level emission
    procedure DoEmitModule();
    procedure DoEmitTypeDecl(const ATypeDecl: TMyrTypeDeclNode);
    procedure DoEmitGlobalConst(const AConst: TMyrConstDeclNode);
    function DoHasRecordLiteralConsts(): Boolean;
    procedure DoEmitRecordLiteralConsts();
    function DoHasStringLiteralConsts(): Boolean;
    procedure DoEmitStringLiteralConsts();
    procedure DoEmitStringLiteralConstsRelease();
    procedure DoEmitGlobalVar(const AVar: TMyrVarDeclNode);
    procedure DoEnsureLibLifecycle(const ALibName: string);
    procedure DoEmitExternRoutine(const ARoutine: TMyrRoutineDeclNode);
    procedure DoEmitRoutine(const ARoutine: TMyrRoutineDeclNode);
    procedure DoEmitStatementList(const AList: TObjectList<TMyrASTNode>);

    // Statement emission
    procedure DoEmitStatement(const AStmt: TMyrASTNode);
    procedure DoEmitAssign(const ANode: TMyrAssignNode);
    procedure DoEmitReturn(const ANode: TMyrReturnNode);
    procedure DoEmitCallStmt(const ANode: TMyrCallStmtNode);
    procedure DoEmitPrint(const ANode: TMyrPrintNode);
    procedure DoEmitIf(const ANode: TMyrIfNode);
    procedure DoEmitWhile(const ANode: TMyrWhileNode);
    procedure DoEmitFor(const ANode: TMyrForNode);
    procedure DoEmitRepeat(const ANode: TMyrRepeatNode);
    procedure DoEmitMatch(const ANode: TMyrMatchNode);
    procedure DoEmitGuard(const ANode: TMyrGuardNode);
    procedure DoEmitThrow(const ANode: TMyrThrowNode);
    procedure DoEmitThrowCode(const ANode: TMyrThrowCodeNode);
    procedure DoEmitAssert(const ANode: TMyrAssertStmtNode);
    procedure DoEmitNew(const ANode: TMyrNewNode);
    procedure DoEmitDispose(const ANode: TMyrDisposeNode);
    procedure DoEmitGetMem(const ANode: TMyrGetMemNode);
    procedure DoEmitFreeMem(const ANode: TMyrFreeMemNode);
    procedure DoEmitResizeMem(const ANode: TMyrResizeMemNode);
    procedure DoEmitSetLength(const ANode: TMyrSetLengthNode);

    // Module initialize/finalize block emission
    procedure DoEmitModuleInitFinalize();

    // Test block emission
    procedure DoEmitTestBlocks();

    // Expression emission
    function DoEmitExpression(const AExpr: TMyrASTNode): TMyrIRExpr;
    function DoEmitBinaryExpr(const ANode: TMyrBinaryExprNode): TMyrIRExpr;
    function DoEmitUnaryExpr(const ANode: TMyrUnaryExprNode): TMyrIRExpr;
    function DoEmitCallExpr(const ANode: TMyrCallExprNode): TMyrIRExpr;
    function DoEmitDotAccess(const ANode: TMyrDotAccessNode): TMyrIRExpr;
    function DoEmitTypeCast(const ANode: TMyrTypeCastExprNode): TMyrIRExpr;
    function DoEmitIntrinsic(const ANode: TMyrIntrinsicExprNode): TMyrIRExpr;
    function DoEmitRecordLiteral(const ANode: TMyrRecordLiteralNode): TMyrIRExpr;
    procedure DoEmitRecordLiteralInto(const ABase: TMyrIRExpr;
      const ARecLit: TMyrRecordLiteralNode);
    function DoEmitSetLiteral(const ANode: TMyrSetLiteralExprNode): TMyrIRExpr;

    // Type mapping
    function DoMapValueType(const ATypeNode: TMyrASTNode): TMyrValueType;
    function DoMapTokenToValueType(const AKind: TMyrTokenKind): TMyrValueType;
    function DoMapLinkage(const ALinkage: Myrissa.Frontend.TMyrLinkage): Myrissa.Backend.TMyrLinkage;
    function DoGetManagedTypeName(const ATypeExpr: TMyrASTNode): string;
    procedure DoEmitStringCleanup(const AVars: TObjectList<TMyrVarDeclNode>);
    procedure DoEmitLocalVars(const AVars: TObjectList<TMyrVarDeclNode>);
    procedure DoCollectStringVars(const AStmts: TObjectList<TMyrASTNode>;
      const ANames: TList<string>);

    // Helpers
    function DoGetDesignatorName(const AExpr: TMyrASTNode): string;
    procedure DoEmitTypeFields(const AParentName: string; const AFields: TObjectList<TMyrASTNode>);
    function DoResolveChoicesMemberValue(const AChoices: TMyrChoicesTypeNode;
      const AMemberName: string): Int64;
    function DoIsFloatType(const AExpr: TMyrExprNode): Boolean;
    function DoIsUnsignedType(const AExpr: TMyrExprNode): Boolean;
    function DoIsStringType(const AExpr: TMyrExprNode): Boolean;
    function DoAssertCmpRoutine(const AExpected: TMyrExprNode; const AActual: TMyrExprNode): string;
    function DoIsStringTemp(const ANode: TMyrASTNode): Boolean;
    procedure DoReleaseStringTemp(const ANode: TMyrASTNode; const AExpr: TMyrIRExpr);
    function DoNewStringTemp(const AValue: TMyrIRExpr): TMyrIRExpr;
    function DoRoutineReturnsString(const ARoutine: TMyrASTNode): Boolean;
    function DoRoutineParamIsString(const ARoutine: TMyrASTNode; const AIndex: Integer): Boolean;
    function DoIsWStringType(const AExpr: TMyrExprNode): Boolean;
    function DoIsSetType(const AExpr: TMyrExprNode): Boolean;
    function DoGetCompositeTypeName(const ATypeExpr: TMyrASTNode): string;
    function DoGetSmallRecordValueType(const ATypeExpr: TMyrASTNode): TMyrValueType;
    function DoRoutineParamIsSmallRecord(const ARoutine: TMyrASTNode; const AIndex: Integer): Boolean;
    function DoComputeRecordSize(const ARecordType: TMyrRecordTypeNode): Integer;
    function DoFormatArgIsFloat(const AFormat: string;
      const AValueIndex: Integer): Boolean;
    function DoFormatWantsFloatArg(const ANode: TMyrPrintNode;
      const AValueIndex: Integer): Boolean;
    function DoEvalConstExpr(const AExpr: TMyrASTNode; out AIntVal: Int64): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure EmitModule(const AModule: TMyrModuleNode;
      const ABackend: TMyrNativeBackend);
  end;

implementation

{ TMyrEmitter }

constructor TMyrEmitter.Create();
begin
  inherited;

  FBackend := nil;
  FModule := nil;
  FLifecycleInits := TList<string>.Create();
  FLifecycleFinals := TList<string>.Create();
  FLifecycleChecked := TList<string>.Create();
end;

destructor TMyrEmitter.Destroy();
begin
  FLifecycleChecked.Free();
  FLifecycleFinals.Free();
  FLifecycleInits.Free();

  inherited;
end;

procedure TMyrEmitter.EmitModule(const AModule: TMyrModuleNode;
  const ABackend: TMyrNativeBackend);
begin
  FBackend := ABackend;
  FModule := AModule;
  DoEmitModule();
end;

procedure TMyrEmitter.DoEmitModule();
var
  LDecl: TMyrASTNode;
  LRoutine: TMyrRoutineDeclNode;
  LTestBlock: TMyrTestBlockNode;
  LTestFuncName: string;
  LStringVars: TList<string>;
  I: Integer;
begin
  // Set source file for debug info
  FBackend.SetSourceFile(FModule.SourceFile);

  // Pass 1: Register type definitions with backend
  for LDecl in FModule.Declarations do
  begin
    if LDecl is TMyrTypeDeclNode then
      DoEmitTypeDecl(TMyrTypeDeclNode(LDecl));
  end;

  // Register default anonymous set type for bare "set" variables
  FBackend.DefineSet('$set');

  // Pass 2: Emit global constants
  for LDecl in FModule.Declarations do
  begin
    if LDecl is TMyrConstDeclNode then
      DoEmitGlobalConst(TMyrConstDeclNode(LDecl));
  end;

  // Pass 3: Emit global variables
  for LDecl in FModule.Declarations do
  begin
    if LDecl is TMyrVarDeclNode then
      DoEmitGlobalVar(TMyrVarDeclNode(LDecl));
  end;

  // Pass 4: Emit external routine declarations (imports)
  for LDecl in FModule.Declarations do
  begin
    if LDecl is TMyrRoutineDeclNode then
    begin
      LRoutine := TMyrRoutineDeclNode(LDecl);
      if LRoutine.IsExternal then
        DoEmitExternRoutine(LRoutine);
    end;
  end;

  // Pass 5: Emit routine bodies
  for LDecl in FModule.Declarations do
  begin
    if LDecl is TMyrRoutineDeclNode then
    begin
      LRoutine := TMyrRoutineDeclNode(LDecl);
      if not LRoutine.IsExternal then
        DoEmitRoutine(LRoutine);
    end;
  end;

  // Pass 6: Emit module initialize/finalize blocks. Must precede the entry
  // point: the SSA prologue and DllMain both scan the function list by name
  // prefix, so these have to exist in the IR before either is built.
  DoEmitModuleInitFinalize();

  // Pass 7: Emit test block functions (before main, so they exist for FuncAddr)
  if FModule.UnitTestMode and (FModule.TestBlocks.Count > 0) then
    DoEmitTestBlocks();

  // Pass 8: Emit main body (entry point)
  if FModule.UnitTestMode and (FModule.TestBlocks.Count > 0) then
  begin
    // Unit test mode: main registers tests and runs them
    FBackend.Func('main', cvtInt32, True, plC);

    // Initialize global string variables with literal initializers
    for LDecl in FModule.Declarations do
    begin
      if (LDecl is TMyrVarDeclNode) and
         (TMyrVarDeclNode(LDecl).InitExpr is TMyrStringLiteralNode) and
         (TMyrVarDeclNode(LDecl).TypeExpr is TMyrTypeRefNode) and
         (TMyrTypeRefNode(TMyrVarDeclNode(LDecl).TypeExpr).TokenKind = tkString) then
        FBackend.Let(TMyrVarDeclNode(LDecl).DeclName, FBackend.Invoke(RT_StrFromLiteral,
          [FBackend.S(TMyrStringLiteralNode(TMyrVarDeclNode(LDecl).InitExpr).StringValue),
           FBackend.I(Length(TMyrStringLiteralNode(TMyrVarDeclNode(LDecl).InitExpr).StringValue))]));
    end;

    // Register each test block
    for I := 0 to FModule.TestBlocks.Count - 1 do
    begin
      LTestBlock := FModule.TestBlocks[I];
      LTestFuncName := '$test_' + LTestBlock.CppTestName;
      FBackend.Call(RT_TestRegister,
        [FBackend.S(LTestBlock.TestName),
         FBackend.FuncAddr(LTestFuncName),
         FBackend.S(FModule.SourceFile),
         FBackend.I(LTestBlock.Location.StartLine)]);
    end;

    // Run all tests and halt with the result
    FBackend.Call('RT_Halt', [FBackend.Invoke(RT_TestRunAll, [])]);
    FBackend.EndFunc();
  end
  else if FModule.HasMainBody then
  begin
    // Normal mode: standard entry point
    FBackend.Func('main', cvtInt32, True, plC);

    // Initialize global string variables with literal initializers
    for LDecl in FModule.Declarations do
    begin
      if (LDecl is TMyrVarDeclNode) and
         (TMyrVarDeclNode(LDecl).InitExpr is TMyrStringLiteralNode) and
         (TMyrVarDeclNode(LDecl).TypeExpr is TMyrTypeRefNode) and
         (TMyrTypeRefNode(TMyrVarDeclNode(LDecl).TypeExpr).TokenKind = tkString) then
        FBackend.Let(TMyrVarDeclNode(LDecl).DeclName, FBackend.Invoke(RT_StrFromLiteral,
          [FBackend.S(TMyrStringLiteralNode(TMyrVarDeclNode(LDecl).InitExpr).StringValue),
           FBackend.I(Length(TMyrStringLiteralNode(TMyrVarDeclNode(LDecl).InitExpr).StringValue))]));
    end;

    DoEmitStatementList(FModule.MainBody);

    // Release the strings this emitter allocated. Every string variable was
    // created by an emitted RT_StrFromLiteral/RT_StrConcat call, so the
    // emitter owns that reference and must drop it before exit.
    for LDecl in FModule.Declarations do
    begin
      if (LDecl is TMyrVarDeclNode) and
         (TMyrVarDeclNode(LDecl).TypeExpr is TMyrTypeRefNode) and
         (TMyrTypeRefNode(TMyrVarDeclNode(LDecl).TypeExpr).TokenKind = tkString) then
        FBackend.Call(RT_StrRelease,
          [FBackend.Get(TMyrVarDeclNode(LDecl).DeclName)]);
    end;

    LStringVars := TList<string>.Create();
    try
      DoCollectStringVars(FModule.MainBody, LStringVars);
      for I := 0 to LStringVars.Count - 1 do
        FBackend.Call(RT_StrRelease, [FBackend.Get(LStringVars[I])]);
    finally
      LStringVars.Free();
    end;

    // Exit code carries the assertion verdict. RT_TestFailed is a runtime
    // global that starts at zero and is set to 1 by any failing assert.
    // A program with no assertions leaves it at zero and still exits 0.
    FBackend.Call('RT_Halt', [FBackend.Get(RT_TestFailed)]);
    FBackend.EndFunc();
  end;
end;

procedure TMyrEmitter.DoEmitModuleInitFinalize();
var
  I: Integer;
begin
  // Every consumer of these functions already exists in the backend; none of
  // them found anything to call because the emitter never created them, so
  // initialize/finalize blocks were parsed and analyzed and then dropped:
  //   EXE      - SSA entry prologue calls each __rt_module_init_* and
  //              registers each __rt_module_finalize_* via RT_RegisterFinalizer
  //              (Backend.pas:19465, :19478), drained by RT_Halt.
  //   DLL win64  - DllMain ATTACH/DETACH (Backend.pas:36453, :36462)
  //   DLL linux64 - the same twin (Backend.pas:37263, :37274)
  // The scans are name-prefix based, so one emission here serves every target.
  //
  // Static libs referenced by this module were imported with their lifecycle
  // routines (DoEnsureLibLifecycle). Call them from this module's own init /
  // finalize so the backend's existing local-function scan reaches them:
  // lib inits run BEFORE this module's init body; lib finalizes run AFTER this
  // module's finalize body, in reverse import order.
  // A module exports its init/finalize routines only when the source has
  // them -- exactly like any other public routine. Public so a consuming
  // module can import them from a static lib.
  //
  // Record-literal constants are composite globals (see DoEmitGlobalConst)
  // and get their field values here, before the module's own init body,
  // so that body and every routine in the module can read them.
  if (FModule.InitBody.Count > 0) or (FLifecycleInits.Count > 0) or
     DoHasRecordLiteralConsts() or DoHasStringLiteralConsts() then
  begin
    FBackend.Func(RT_ModuleInit + '_' + FModule.ModuleName, cvtVoid, False, plC, True);
    for I := 0 to FLifecycleInits.Count - 1 do
      FBackend.Call(RT_ModuleInit + '_' + FLifecycleInits[I], []);
    DoEmitRecordLiteralConsts();
    DoEmitStringLiteralConsts();
    DoEmitStatementList(FModule.InitBody);
    FBackend.EndFunc();
  end;

  if (FModule.FinalBody.Count > 0) or (FLifecycleFinals.Count > 0) or
     ((FModule.ModuleKind = mkLib) and DoHasStringLiteralConsts()) then
  begin
    FBackend.Func(RT_ModuleFinalize + '_' + FModule.ModuleName, cvtVoid, False, plC, True);
    DoEmitStatementList(FModule.FinalBody);
    if FModule.ModuleKind = mkLib then
      DoEmitStringLiteralConstsRelease();
    for I := FLifecycleFinals.Count - 1 downto 0 do
      FBackend.Call(RT_ModuleFinalize + '_' + FLifecycleFinals[I], []);
    FBackend.EndFunc();
  end;
end;

procedure TMyrEmitter.DoEmitTestBlocks();
var
  LTest: TMyrTestBlockNode;
  LFuncName: string;
  I: Integer;
begin
  for I := 0 to FModule.TestBlocks.Count - 1 do
  begin
    LTest := FModule.TestBlocks[I];
    LFuncName := '$test_' + LTest.CppTestName;

    // Emit test block as a parameterless void function; locals and string
    // cleanup follow the routine path exactly.
    FBackend.Func(LFuncName, cvtVoid, False, plC);
    DoEmitLocalVars(LTest.Locals);
    DoEmitStatementList(LTest.Body);
    DoEmitStringCleanup(LTest.Locals);
    FBackend.EndFunc();
  end;
end;

procedure TMyrEmitter.DoEmitTypeDecl(const ATypeDecl: TMyrTypeDeclNode);
var
  LChoices: TMyrChoicesTypeNode;
  LMember: TMyrChoicesValueNode;
  I: Integer;
  LNextValue: Int64;
  LRecord: TMyrRecordTypeNode;
  LBaseTypeName: string;
begin
  if ATypeDecl.TypeDef is TMyrChoicesTypeNode then
  begin
    // Register enum type with backend
    LChoices := TMyrChoicesTypeNode(ATypeDecl.TypeDef);
    FBackend.DefineEnum(ATypeDecl.DeclName);
    LNextValue := 0;
    for I := 0 to LChoices.Members.Count - 1 do
    begin
      LMember := LChoices.Members[I];
      if (LMember.ValueExpr <> nil) and (LMember.ValueExpr is TMyrIntLiteralNode) then
        LNextValue := TMyrIntLiteralNode(LMember.ValueExpr).IntValue;
      FBackend.EnumValue(LMember.MemberName, LNextValue);
      Inc(LNextValue);
    end;
    FBackend.EndEnum();
  end
  else if ATypeDecl.TypeDef is TMyrRecordTypeNode then
  begin
    // Register record type with backend
    LRecord := TMyrRecordTypeNode(ATypeDecl.TypeDef);
    LBaseTypeName := '';
    if (LRecord.BaseType <> nil) and (LRecord.BaseType is TMyrTypeRefNode) and
       (TMyrTypeRefNode(LRecord.BaseType).ResolvedDecl is TMyrTypeDeclNode) then
      LBaseTypeName := TMyrTypeDeclNode(TMyrTypeRefNode(LRecord.BaseType).ResolvedDecl).DeclName;
    FBackend.DefineRecord(ATypeDecl.DeclName, LRecord.IsPacked,
      LRecord.Alignment, LBaseTypeName);
    DoEmitTypeFields(ATypeDecl.DeclName, LRecord.Fields);
    FBackend.EndRecord();
  end
  else if ATypeDecl.TypeDef is TMyrOverlayTypeNode then
  begin
    // Register overlay (union) type with backend
    FBackend.DefineUnion(ATypeDecl.DeclName);
    DoEmitTypeFields(ATypeDecl.DeclName, TMyrOverlayTypeNode(ATypeDecl.TypeDef).Fields);
    FBackend.EndUnion();
  end
  else if ATypeDecl.TypeDef is TMyrArrayTypeNode then
  begin
    // Register array type with backend
    if TMyrArrayTypeNode(ATypeDecl.TypeDef).ElementType <> nil then
    begin
      if TMyrArrayTypeNode(ATypeDecl.TypeDef).IsDynamic then
        FBackend.DefineDynArray(ATypeDecl.DeclName,
          DoMapValueType(TMyrArrayTypeNode(ATypeDecl.TypeDef).ElementType))
      else
        FBackend.DefineArray(ATypeDecl.DeclName,
          DoMapValueType(TMyrArrayTypeNode(ATypeDecl.TypeDef).ElementType),
          TMyrArrayTypeNode(ATypeDecl.TypeDef).LowBound,
          TMyrArrayTypeNode(ATypeDecl.TypeDef).HighBound);
    end;
  end
  else if ATypeDecl.TypeDef is TMyrPointerTypeNode then
  begin
    // Register pointer type
    if TMyrPointerTypeNode(ATypeDecl.TypeDef).TargetType <> nil then
      FBackend.DefinePointer(ATypeDecl.DeclName, cvtPointer)
    else
      FBackend.DefinePointer(ATypeDecl.DeclName);
  end
  else if ATypeDecl.TypeDef is TMyrSetTypeNode then
  begin
    // Register set type
    FBackend.DefineSet(ATypeDecl.DeclName,
      TMyrSetTypeNode(ATypeDecl.TypeDef).RangeLow,
      TMyrSetTypeNode(ATypeDecl.TypeDef).RangeHigh);
  end
  else if ATypeDecl.TypeDef is TMyrRoutineTypeNode then
  begin
    // Register routine (procedure/function pointer) type
    FBackend.DefineRoutine(ATypeDecl.DeclName,
      DoMapLinkage(TMyrRoutineTypeNode(ATypeDecl.TypeDef).Linkage));
    for I := 0 to TMyrRoutineTypeNode(ATypeDecl.TypeDef).Params.Count - 1 do
      FBackend.RoutineParam(
        DoMapValueType(TMyrRoutineTypeNode(ATypeDecl.TypeDef).Params[I].TypeExpr));
    if TMyrRoutineTypeNode(ATypeDecl.TypeDef).ReturnType <> nil then
      FBackend.RoutineReturns(
        DoMapValueType(TMyrRoutineTypeNode(ATypeDecl.TypeDef).ReturnType));
    if TMyrRoutineTypeNode(ATypeDecl.TypeDef).IsVariadic then
      FBackend.RoutineVarArgs();
    FBackend.EndRoutine();
  end
  else if ATypeDecl.TypeDef is TMyrTypeRefNode then
  begin
    // Type alias
    FBackend.DefineAlias(ATypeDecl.DeclName,
      DoMapValueType(ATypeDecl.TypeDef));
  end;
end;

procedure TMyrEmitter.DoEmitGlobalConst(const AConst: TMyrConstDeclNode);
var
  LType: TMyrValueType;
  LIntVal: Int64;
  LCompositeName: string;
begin
  // Determine type
  if AConst.TypeExpr <> nil then
    LType := DoMapValueType(AConst.TypeExpr)
  else
    LType := cvtInt64;  // default for untyped consts

  // Try to evaluate the constant expression from the AST
  if AConst.ValueExpr is TMyrIntLiteralNode then
    FBackend.Global(AConst.DeclName, LType,
      FBackend.I(TMyrIntLiteralNode(AConst.ValueExpr).IntValue), True)
  else if AConst.ValueExpr is TMyrFloatLiteralNode then
    FBackend.Global(AConst.DeclName, LType,
      FBackend.F(TMyrFloatLiteralNode(AConst.ValueExpr).FloatValue), True)
  else if AConst.ValueExpr is TMyrBoolLiteralNode then
    FBackend.Global(AConst.DeclName, LType,
      FBackend.B(TMyrBoolLiteralNode(AConst.ValueExpr).BoolValue), True)
  else if AConst.ValueExpr is TMyrStringLiteralNode then
  begin
    // A string const whose declared type is string (or untyped, which the
    // analyzer resolves to string) is a MANAGED string: every consumer
    // (RT_StrData, RT_Len, RT_StrAssign, RT_StrConcat, the auto-inserted
    // cstr() for pointer-to-char params) reads a TStringRec header off it.
    // Storing a raw literal pointer here made all of those read garbage:
    // len() returned 0, assignment produced null, cstr() AV'd. The slot is
    // declared with string identity and filled by RT_StrFromLiteral in the
    // module init function (DoEmitStringLiteralConsts). The backend's string
    // cleanup pass releases it at exit like every other string global.
    // A const explicitly typed as a pointer keeps the raw literal pointer.
    if (AConst.TypeExpr = nil) or
       ((AConst.TypeExpr is TMyrTypeRefNode) and
        (TMyrTypeRefNode(AConst.TypeExpr).TokenKind = tkString)) then
      FBackend.Global(AConst.DeclName, 'string', True)
    else
      FBackend.Global(AConst.DeclName, cvtPointer,
        FBackend.S(TMyrStringLiteralNode(AConst.ValueExpr).StringValue), True);
  end
  else if DoEvalConstExpr(AConst.ValueExpr, LIntVal) then
    FBackend.Global(AConst.DeclName, LType, FBackend.I(LIntVal), True)
  else if AConst.ValueExpr is TMyrRecordLiteralNode then
  begin
    // Record literal constants use composite global representation so that
    // Get() returns a pointer to the record's memory, matching local record
    // vars. Field values are initialized in the module init function.
    LCompositeName := DoGetCompositeTypeName(AConst.TypeExpr);
    if LCompositeName <> '' then
      FBackend.Global(AConst.DeclName, LCompositeName, True)
    else
      FBackend.Global(AConst.DeclName, cvtPointer, True);
  end
  else
  begin
    // Cannot evaluate at compile time -- emit zero-initialized
    if AConst.TypeExpr <> nil then
      LType := DoMapValueType(AConst.TypeExpr)
    else
      LType := cvtInt32;
    FBackend.Global(AConst.DeclName, LType, True);
  end;
end;

function TMyrEmitter.DoHasRecordLiteralConsts(): Boolean;
var
  LDecl: TMyrASTNode;
begin
  Result := False;
  for LDecl in FModule.Declarations do
  begin
    if (LDecl is TMyrConstDeclNode) and
       (TMyrConstDeclNode(LDecl).ValueExpr is TMyrRecordLiteralNode) then
      Exit(True);
  end;
end;

// Fill the composite globals created by DoEmitGlobalConst for record-literal
// constants. Runs inside this module's init function, so every module (root
// or imported) initializes its own constants on every target.
procedure TMyrEmitter.DoEmitRecordLiteralConsts();
var
  LDecl: TMyrASTNode;
begin
  for LDecl in FModule.Declarations do
  begin
    if (LDecl is TMyrConstDeclNode) and
       (TMyrConstDeclNode(LDecl).ValueExpr is TMyrRecordLiteralNode) then
      DoEmitRecordLiteralInto(FBackend.Get(TMyrConstDeclNode(LDecl).DeclName),
        TMyrRecordLiteralNode(TMyrConstDeclNode(LDecl).ValueExpr));
  end;
end;

// True when this module declares at least one string-typed (or untyped)
// constant initialized from a string literal. Mirrors DoHasRecordLiteralConsts.
function TMyrEmitter.DoHasStringLiteralConsts(): Boolean;
var
  LDecl: TMyrASTNode;
  LConst: TMyrConstDeclNode;
begin
  Result := False;
  for LDecl in FModule.Declarations do
  begin
    if not (LDecl is TMyrConstDeclNode) then
      Continue;
    LConst := TMyrConstDeclNode(LDecl);
    if not (LConst.ValueExpr is TMyrStringLiteralNode) then
      Continue;
    if (LConst.TypeExpr = nil) or
       ((LConst.TypeExpr is TMyrTypeRefNode) and
        (TMyrTypeRefNode(LConst.TypeExpr).TokenKind = tkString)) then
      Exit(True);
  end;
end;

// Fill the string globals created by DoEmitGlobalConst for string-literal
// constants. Runs inside this module's init function so every module (root
// or imported) initializes its own constants on every target -- the same
// reason record-literal consts live here rather than in main.
procedure TMyrEmitter.DoEmitStringLiteralConsts();
var
  LDecl: TMyrASTNode;
  LConst: TMyrConstDeclNode;
  LText: string;
begin
  for LDecl in FModule.Declarations do
  begin
    if not (LDecl is TMyrConstDeclNode) then
      Continue;
    LConst := TMyrConstDeclNode(LDecl);
    if not (LConst.ValueExpr is TMyrStringLiteralNode) then
      Continue;
    if (LConst.TypeExpr = nil) or
       ((LConst.TypeExpr is TMyrTypeRefNode) and
        (TMyrTypeRefNode(LConst.TypeExpr).TokenKind = tkString)) then
    begin
      LText := TMyrStringLiteralNode(LConst.ValueExpr).StringValue;
      // Release any string already in the slot before storing the new one.
      // Identically-named string consts in different imported modules (e.g.
      // DLL_NAME in SDL3 and SDL3_image) resolve to the same IR global via
      // FindGlobal, so the second module's init would overwrite the first
      // module's RT_StrFromLiteral without freeing it. RT_StrRelease is a
      // no-op on nil, so the first init through this slot is unaffected.
      FBackend.Call(RT_StrRelease, [FBackend.Get(LConst.DeclName)]);
      FBackend.Let(LConst.DeclName, FBackend.Invoke(RT_StrFromLiteral,
        [FBackend.S(LText), FBackend.I(Length(LText))]));
    end;
  end;
end;

// Static-lib modules only. The backend's string cleanup pass releases every
// managed global it can see, but it fires only at an entry point (exe main,
// DllMain) and walks that image's own IR. A static lib has no entry point
// and its globals live in its own object, so nothing ever releases them --
// the consumer exe reported Leaked: 2 per string const. The lib's finalize
// routine IS called by the consumer (FLifecycleFinals), so the release goes
// there. Exe and dll modules must NOT do this: the cleanup pass already
// covers them and a second release is a double free (SIGSEGV on linux64).
procedure TMyrEmitter.DoEmitStringLiteralConstsRelease();
var
  LDecl: TMyrASTNode;
  LConst: TMyrConstDeclNode;
begin
  for LDecl in FModule.Declarations do
  begin
    if not (LDecl is TMyrConstDeclNode) then
      Continue;
    LConst := TMyrConstDeclNode(LDecl);
    if not (LConst.ValueExpr is TMyrStringLiteralNode) then
      Continue;
    if (LConst.TypeExpr = nil) or
       ((LConst.TypeExpr is TMyrTypeRefNode) and
        (TMyrTypeRefNode(LConst.TypeExpr).TokenKind = tkString)) then
      FBackend.Call(RT_StrRelease, [FBackend.Get(LConst.DeclName)]);
  end;
end;

{ TMyrEmitter.DoEmitGlobalVar }
procedure TMyrEmitter.DoEmitGlobalVar(const AVar: TMyrVarDeclNode);
var
  LType: TMyrValueType;
  LCompositeName: string;
  LTypeDecl: TMyrTypeDeclNode;
  LArrayName: string;
  LDllName: string;
  LSharedLibName: string;
begin
  // External variables -- resolve library using same BNF §9 rules as routines.
  // Static libs: variable symbol merged by linker (ImportLib).
  // Dynamic libs: data import via IAT/GOT (ImportGlobal).
  if AVar.IsExternal then
  begin
    LDllName := AVar.ResolvedExternalLib;

    if LDllName.EndsWith('.lib') then
    begin
      DoEnsureLibLifecycle(LDllName.Substring(0, LDllName.Length - 4));
      FBackend.ImportLibGlobal(AVar.DeclName, LDllName.Substring(0, LDllName.Length - 4),
        AVar.DeclName, DoMapValueType(AVar.TypeExpr));
    end
    else if LDllName.EndsWith('.a') then
    begin
      DoEnsureLibLifecycle(LDllName.Substring(0, LDllName.Length - 2));
      FBackend.ImportLibGlobal(AVar.DeclName, LDllName.Substring(0, LDllName.Length - 2),
        AVar.DeclName, DoMapValueType(AVar.TypeExpr));
    end
    else if LDllName.EndsWith('.dll') or LDllName.EndsWith('.so') or
            (LDllName.IndexOf('.so.') >= 0) then
      FBackend.ImportGlobal(AVar.DeclName, LDllName,
        AVar.DeclName, DoMapValueType(AVar.TypeExpr))
    else if FBackend.FindStaticLib(LDllName) then
    begin
      DoEnsureLibLifecycle(LDllName);
      FBackend.ImportLibGlobal(AVar.DeclName, LDllName,
        AVar.DeclName, DoMapValueType(AVar.TypeExpr));
    end
    else
    begin
      LSharedLibName := FBackend.FindSharedLib(LDllName);
      if LSharedLibName = '' then
        LSharedLibName := LDllName + TMyrTargetInfo.FileExt(FBackend.GetTarget(), otDll);
      FBackend.ImportGlobal(AVar.DeclName, LSharedLibName,
        AVar.DeclName, DoMapValueType(AVar.TypeExpr));
    end;
    Exit;
  end;

  // Composite types (record/overlay) must use the string overload
  // to preserve type identity -- DoMapValueType collapses them to
  // cvtPointer, which makes the backend treat them as primitive
  // pointers instead of embedded structs.
  LCompositeName := DoGetCompositeTypeName(AVar.TypeExpr);
  if LCompositeName <> '' then
  begin
    FBackend.Global(AVar.DeclName, LCompositeName, AVar.IsPublic);
    Exit;
  end;

  // Static arrays need their full size allocated, not just cvtPointer (8 bytes).
  // Named static array types are already registered by DoEmitTypeDecl;
  // inline static arrays need a synthesized type registration.
  if (AVar.TypeExpr is TMyrTypeRefNode) and
     (TMyrTypeRefNode(AVar.TypeExpr).ResolvedDecl is TMyrTypeDeclNode) then
  begin
    LTypeDecl := TMyrTypeDeclNode(TMyrTypeRefNode(AVar.TypeExpr).ResolvedDecl);
    if (LTypeDecl.TypeDef is TMyrArrayTypeNode) and
       (not TMyrArrayTypeNode(LTypeDecl.TypeDef).IsDynamic) then
    begin
      FBackend.Global(AVar.DeclName, LTypeDecl.DeclName, AVar.IsPublic);
      Exit;
    end;
  end
  else if (AVar.TypeExpr is TMyrArrayTypeNode) and
          (not TMyrArrayTypeNode(AVar.TypeExpr).IsDynamic) then
  begin
    LArrayName := '__arr_' + AVar.DeclName;
    FBackend.DefineArray(LArrayName,
      DoMapValueType(TMyrArrayTypeNode(AVar.TypeExpr).ElementType),
      TMyrArrayTypeNode(AVar.TypeExpr).LowBound,
      TMyrArrayTypeNode(AVar.TypeExpr).HighBound);
    FBackend.Global(AVar.DeclName, LArrayName, AVar.IsPublic);
    Exit;
  end
  else if (AVar.TypeExpr is TMyrArrayTypeNode) and
          TMyrArrayTypeNode(AVar.TypeExpr).IsDynamic then
  begin
    LArrayName := '__dynarr_' + AVar.DeclName;
    FBackend.DefineDynArray(LArrayName,
      DoMapValueType(TMyrArrayTypeNode(AVar.TypeExpr).ElementType));
    FBackend.Global(AVar.DeclName, LArrayName, AVar.IsPublic);
    Exit;
  end;

  // A record/overlay global lives IN the .data slot, so the slot must be
  // the aggregate's full size. DoMapValueType collapses it to cvtPointer
  // (an 8-byte slot); SDL_PollEvent then wrote 120 bytes past LEvent into
  // the globals after it. Same seam the const path closes above. A record
  // literal initializer on a global var is still not applied (pre-existing).
  LCompositeName := DoGetCompositeTypeName(AVar.TypeExpr);
  if LCompositeName <> '' then
  begin
    FBackend.Global(AVar.DeclName, LCompositeName, AVar.IsPublic);
    Exit;
  end;

  LType := DoMapValueType(AVar.TypeExpr);

  if AVar.InitExpr <> nil then
  begin
    // Simple literal initializers go into .data section
    if AVar.InitExpr is TMyrIntLiteralNode then
      FBackend.Global(AVar.DeclName, LType,
        FBackend.I(TMyrIntLiteralNode(AVar.InitExpr).IntValue), AVar.IsPublic)
    else if AVar.InitExpr is TMyrFloatLiteralNode then
      FBackend.Global(AVar.DeclName, LType,
        FBackend.F(TMyrFloatLiteralNode(AVar.InitExpr).FloatValue), AVar.IsPublic)
    else if AVar.InitExpr is TMyrBoolLiteralNode then
      FBackend.Global(AVar.DeclName, LType,
        FBackend.B(TMyrBoolLiteralNode(AVar.InitExpr).BoolValue), AVar.IsPublic)
    else if (AVar.InitExpr is TMyrStringLiteralNode) and
            (AVar.TypeExpr is TMyrTypeRefNode) and
            (TMyrTypeRefNode(AVar.TypeExpr).TokenKind in [tkChar, tkWChar]) then
    begin
      // char/wchar variable initialized from a string literal -- take first char
      if TMyrStringLiteralNode(AVar.InitExpr).StringValue <> '' then
        FBackend.Global(AVar.DeclName, LType,
          FBackend.I(Ord(TMyrStringLiteralNode(AVar.InitExpr).StringValue[1])), AVar.IsPublic)
      else
        FBackend.Global(AVar.DeclName, LType, FBackend.I(0), AVar.IsPublic);
    end
    else
      // Non-constant init -- zero-init, runtime init deferred
      FBackend.Global(AVar.DeclName, LType, AVar.IsPublic);
  end
  else
    FBackend.Global(AVar.DeclName, LType, AVar.IsPublic);
end;

procedure TMyrEmitter.DoEnsureLibLifecycle(const ALibName: string);
var
  LInitName: string;
  LFinalName: string;
begin
  // A static lib exports its initialize/finalize blocks as ordinary public
  // routines named __rt_module_init_<lib> / __rt_module_finalize_<lib> --
  // only when the source had them. Import exactly what the archive defines
  // (a foreign C archive defines neither). Once per lib.
  if FLifecycleChecked.Contains(ALibName) then
    Exit;
  FLifecycleChecked.Add(ALibName);

  LInitName := RT_ModuleInit + '_' + ALibName;
  LFinalName := RT_ModuleFinalize + '_' + ALibName;

  if FBackend.StaticLibHasSymbol(ALibName, LInitName) then
  begin
    FLifecycleInits.Add(ALibName);
    FBackend.ImportLib(ALibName, LInitName, [], cvtVoid, False, plC);
  end;

  if FBackend.StaticLibHasSymbol(ALibName, LFinalName) then
  begin
    FLifecycleFinals.Add(ALibName);
    FBackend.ImportLib(ALibName, LFinalName, [], cvtVoid, False, plC);
  end;
end;

procedure TMyrEmitter.DoEmitExternRoutine(const ARoutine: TMyrRoutineDeclNode);
var
  LParams: array of TMyrValueType;
  LReturn: TMyrValueType;
  LRecValType: TMyrValueType;
  LIdx: Integer;
  LParam: TMyrParamDeclNode;
  LDllName: string;
  LFuncName: string;
  LExternalName: string;
  LSharedLibName: string;
  LReturnComposite: string;
begin
  // Build parameter type array
  SetLength(LParams, ARoutine.Params.Count);
  for LIdx := 0 to ARoutine.Params.Count - 1 do
  begin
    LParam := ARoutine.Params[LIdx];
    if LParam.ParamMode = pmVar then
      LParams[LIdx] := cvtPointer
    else
    begin
      LParams[LIdx] := DoMapValueType(LParam.TypeExpr);
      // Win64 ABI: small records (<= 8 bytes, power-of-two) are passed by
      // value in a register. DoMapValueType returns cvtPointer for all
      // records; override with the size-appropriate integer type so the
      // codegen places the loaded value in the register, not the address.
      if LParams[LIdx] = cvtPointer then
      begin
        LRecValType := DoGetSmallRecordValueType(LParam.TypeExpr);
        if LRecValType <> cvtVoid then
          LParams[LIdx] := LRecValType;
      end;
    end;
  end;

  // Return type
  if ARoutine.ReturnType <> nil then
    LReturn := DoMapValueType(ARoutine.ReturnType)
  else
    LReturn := cvtVoid;

  // Resolve library: extension-based dispatch matching BNF §9 rules.
  // .lib/.a → static, .dll/.so → dynamic, extensionless → probe static first.
  LDllName := ARoutine.ResolvedExternalLib;
  LFuncName := ARoutine.DeclName;
  LExternalName := ARoutine.ResolvedExternalName;

  if LDllName.EndsWith('.lib') then
  begin
    DoEnsureLibLifecycle(LDllName.Substring(0, LDllName.Length - 4));
    FBackend.ImportLib(LDllName.Substring(0, LDllName.Length - 4),
      LFuncName, LParams, LReturn, ARoutine.IsVariadic, DoMapLinkage(ARoutine.Linkage));
  end
  else if LDllName.EndsWith('.a') then
  begin
    DoEnsureLibLifecycle(LDllName.Substring(0, LDllName.Length - 2));
    FBackend.ImportLib(LDllName.Substring(0, LDllName.Length - 2),
      LFuncName, LParams, LReturn, ARoutine.IsVariadic, DoMapLinkage(ARoutine.Linkage));
  end
  else if LDllName.EndsWith('.dll') or LDllName.EndsWith('.so') or
          (LDllName.IndexOf('.so.') >= 0) then
  begin
    if (LExternalName <> '') and (LExternalName <> LFuncName) then
      FBackend.ImportDll(LDllName, LFuncName, LExternalName, LParams, LReturn,
        ARoutine.IsVariadic, DoMapLinkage(ARoutine.Linkage))
    else
      FBackend.ImportDll(LDllName, LFuncName, LParams, LReturn,
        ARoutine.IsVariadic, DoMapLinkage(ARoutine.Linkage));
  end
  else if FBackend.FindStaticLib(LDllName) then
  begin
    DoEnsureLibLifecycle(LDllName);
    FBackend.ImportLib(LDllName, LFuncName, LParams, LReturn,
      ARoutine.IsVariadic, DoMapLinkage(ARoutine.Linkage));
  end
  else
  begin
    // Extensionless, no static lib: dynamic import. Probe for .so variant,
    // fall back to target's default shared-library extension.
    LSharedLibName := FBackend.FindSharedLib(LDllName);
    if LSharedLibName = '' then
      LSharedLibName := LDllName + TMyrTargetInfo.FileExt(FBackend.GetTarget(), otDll);
    if (LExternalName <> '') and (LExternalName <> LFuncName) then
      FBackend.ImportDll(LSharedLibName, LFuncName, LExternalName, LParams, LReturn,
        ARoutine.IsVariadic, DoMapLinkage(ARoutine.Linkage))
    else
      FBackend.ImportDll(LSharedLibName, LFuncName, LParams, LReturn,
        ARoutine.IsVariadic, DoMapLinkage(ARoutine.Linkage));
  end;

  // LReturn is the storage class (cvtPointer for every record). Carry the
  // record's identity too, so a call result is handled as an aggregate.
  if ARoutine.ReturnType <> nil then
  begin
    LReturnComposite := DoGetCompositeTypeName(ARoutine.ReturnType);
    if LReturnComposite <> '' then
      FBackend.SetImportReturnType(LFuncName, LReturnComposite);
  end;
end;

procedure TMyrEmitter.DoEmitRoutine(const ARoutine: TMyrRoutineDeclNode);
var
  LReturn: TMyrValueType;
  LIdx: Integer;
  LParam: TMyrParamDeclNode;
  LCompositeName: string;
begin
  // Return type
  if ARoutine.ReturnType <> nil then
    LReturn := DoMapValueType(ARoutine.ReturnType)
  else
    LReturn := cvtVoid;

  FBackend.Func(ARoutine.DeclName, LReturn, False,
    DoMapLinkage(ARoutine.Linkage), ARoutine.IsPublic);

  // LReturn is the storage class (cvtPointer for every record). Returns()
  // carries the record's identity, which sets ReturnTypeRef/ReturnSize and
  // selects the aggregate return convention. Same seam the params close
  // below with DoGetCompositeTypeName.
  if ARoutine.ReturnType <> nil then
  begin
    LCompositeName := DoGetCompositeTypeName(ARoutine.ReturnType);
    if LCompositeName <> '' then
      FBackend.Returns(LCompositeName);
  end;

  // Emit parameters
  //
  // Composite params must be declared by NAME, exactly as locals are below.
  // DoMapValueType collapses a record to a generic composite value type, which
  // loses the type index the backend needs to resolve field types. Field reads
  // through such a param then saw a field ResultType that IsStringType could
  // not recognise, so the load after sikFieldAddr was skipped and the field
  // ADDRESS flowed into RT_StrData. Repro: probe_g.myr printed "(null)".
  for LIdx := 0 to ARoutine.Params.Count - 1 do
  begin
    LParam := ARoutine.Params[LIdx];
    LCompositeName := DoGetCompositeTypeName(LParam.TypeExpr);
    if LCompositeName <> '' then
      FBackend.Arg(LParam.ParamName, LCompositeName,
        LParam.ParamMode = pmVar)
    else
      FBackend.Arg(LParam.ParamName,
        DoMapValueType(LParam.TypeExpr),
        LParam.ParamMode = pmVar);
  end;

  // Emit local variables
  DoEmitLocalVars(ARoutine.LocalVars);

  // Emit body
  DoEmitStatementList(ARoutine.Body);

  // Release string locals before function exit
  DoEmitStringCleanup(ARoutine.LocalVars);

  FBackend.EndFunc();
end;

procedure TMyrEmitter.DoEmitLocalVars(const AVars: TObjectList<TMyrVarDeclNode>);
var
  LIdx: Integer;
  LVar: TMyrVarDeclNode;
  LCompositeName: string;
begin
  for LIdx := 0 to AVars.Count - 1 do
  begin
    LVar := AVars[LIdx];
    LCompositeName := DoGetCompositeTypeName(LVar.TypeExpr);
    if LCompositeName <> '' then
      FBackend.VarDecl(LVar.DeclName, LCompositeName)
    else if (LVar.TypeExpr is TMyrArrayTypeNode) and
            TMyrArrayTypeNode(LVar.TypeExpr).IsDynamic then
    begin
      LCompositeName := '__dynarr_' + LVar.DeclName;
      FBackend.DefineDynArray(LCompositeName,
        DoMapValueType(TMyrArrayTypeNode(LVar.TypeExpr).ElementType));
      FBackend.VarDecl(LVar.DeclName, LCompositeName);
    end
    else
      FBackend.VarDecl(LVar.DeclName, DoMapValueType(LVar.TypeExpr));
    if LVar.InitExpr <> nil then
    begin
      if (LVar.InitExpr is TMyrStringLiteralNode) and
         (LVar.TypeExpr is TMyrTypeRefNode) and
         (TMyrTypeRefNode(LVar.TypeExpr).TokenKind = tkString) then
        FBackend.Let(LVar.DeclName, FBackend.Invoke(RT_StrFromLiteral,
          [FBackend.S(TMyrStringLiteralNode(LVar.InitExpr).StringValue),
           FBackend.I(Length(TMyrStringLiteralNode(LVar.InitExpr).StringValue))]))
      else
        FBackend.Let(LVar.DeclName, DoEmitExpression(LVar.InitExpr));
    end
    else if (LVar.TypeExpr is TMyrTypeRefNode) and
            (TMyrTypeRefNode(LVar.TypeExpr).TokenKind = tkString) then
      // A string slot starts as nil so the first assignment can release it
      FBackend.Let(LVar.DeclName, FBackend.Null());
  end;
end;

procedure TMyrEmitter.DoEmitStatementList(const AList: TObjectList<TMyrASTNode>);
var
  LStmt: TMyrASTNode;
begin
  for LStmt in AList do
    DoEmitStatement(LStmt);
end;

procedure TMyrEmitter.DoEmitStatement(const AStmt: TMyrASTNode);
var
  LCompositeName: string;
begin
  // Stamp source position so the backend source map has line entries for .mdbg
  FBackend.SetLine(AStmt.Location.StartLine, AStmt.Location.StartColumn);

  if AStmt is TMyrAssignNode then
    DoEmitAssign(TMyrAssignNode(AStmt))
  else if AStmt is TMyrCallStmtNode then
    DoEmitCallStmt(TMyrCallStmtNode(AStmt))
  else if AStmt is TMyrPrintNode then
    DoEmitPrint(TMyrPrintNode(AStmt))
  else if AStmt is TMyrIfNode then
    DoEmitIf(TMyrIfNode(AStmt))
  else if AStmt is TMyrWhileNode then
    DoEmitWhile(TMyrWhileNode(AStmt))
  else if AStmt is TMyrForNode then
    DoEmitFor(TMyrForNode(AStmt))
  else if AStmt is TMyrRepeatNode then
    DoEmitRepeat(TMyrRepeatNode(AStmt))
  else if AStmt is TMyrReturnNode then
    DoEmitReturn(TMyrReturnNode(AStmt))
  else if AStmt is TMyrBreakNode then
    FBackend.LoopBreak()
  else if AStmt is TMyrContinueNode then
    FBackend.LoopContinue()
  else if AStmt is TMyrMatchNode then
    DoEmitMatch(TMyrMatchNode(AStmt))
  else if AStmt is TMyrGuardNode then
    DoEmitGuard(TMyrGuardNode(AStmt))
  else if AStmt is TMyrThrowNode then
    DoEmitThrow(TMyrThrowNode(AStmt))
  else if AStmt is TMyrThrowCodeNode then
    DoEmitThrowCode(TMyrThrowCodeNode(AStmt))
  else if AStmt is TMyrVarDeclNode then
  begin
    // Inline local variable declaration -- use type name for composite types
    LCompositeName := DoGetCompositeTypeName(TMyrVarDeclNode(AStmt).TypeExpr);
    if LCompositeName <> '' then
      FBackend.VarDecl(TMyrVarDeclNode(AStmt).DeclName, LCompositeName)
    else if (TMyrVarDeclNode(AStmt).TypeExpr is TMyrArrayTypeNode) and
            TMyrArrayTypeNode(TMyrVarDeclNode(AStmt).TypeExpr).IsDynamic then
    begin
      LCompositeName := '__dynarr_' + TMyrVarDeclNode(AStmt).DeclName;
      FBackend.DefineDynArray(LCompositeName,
        DoMapValueType(TMyrArrayTypeNode(TMyrVarDeclNode(AStmt).TypeExpr).ElementType));
      FBackend.VarDecl(TMyrVarDeclNode(AStmt).DeclName, LCompositeName);
    end
    else
      FBackend.VarDecl(TMyrVarDeclNode(AStmt).DeclName,
        DoMapValueType(TMyrVarDeclNode(AStmt).TypeExpr));
    if TMyrVarDeclNode(AStmt).InitExpr <> nil then
    begin
      if (TMyrVarDeclNode(AStmt).InitExpr is TMyrStringLiteralNode) and
         (TMyrVarDeclNode(AStmt).TypeExpr is TMyrTypeRefNode) and
         (TMyrTypeRefNode(TMyrVarDeclNode(AStmt).TypeExpr).TokenKind = tkString) then
        FBackend.Let(TMyrVarDeclNode(AStmt).DeclName, FBackend.Invoke(RT_StrFromLiteral,
          [FBackend.S(TMyrStringLiteralNode(TMyrVarDeclNode(AStmt).InitExpr).StringValue),
           FBackend.I(Length(TMyrStringLiteralNode(TMyrVarDeclNode(AStmt).InitExpr).StringValue))]))
      else if TMyrVarDeclNode(AStmt).InitExpr is TMyrRecordLiteralNode then
        // Store fields directly into the target variable to avoid broken struct copy
        DoEmitRecordLiteralInto(FBackend.Get(TMyrVarDeclNode(AStmt).DeclName),
          TMyrRecordLiteralNode(TMyrVarDeclNode(AStmt).InitExpr))
      else
        FBackend.Let(TMyrVarDeclNode(AStmt).DeclName,
          DoEmitExpression(TMyrVarDeclNode(AStmt).InitExpr));
    end
    else if (TMyrVarDeclNode(AStmt).TypeExpr is TMyrTypeRefNode) and
            (TMyrTypeRefNode(TMyrVarDeclNode(AStmt).TypeExpr).TokenKind = tkString) then
      // A string slot starts as nil so the first assignment can release it
      FBackend.Let(TMyrVarDeclNode(AStmt).DeclName, FBackend.Null());
  end
  else if AStmt is TMyrAssertStmtNode then
    DoEmitAssert(TMyrAssertStmtNode(AStmt))
  else if AStmt is TMyrNewNode then
    DoEmitNew(TMyrNewNode(AStmt))
  else if AStmt is TMyrDisposeNode then
    DoEmitDispose(TMyrDisposeNode(AStmt))
  else if AStmt is TMyrGetMemNode then
    DoEmitGetMem(TMyrGetMemNode(AStmt))
  else if AStmt is TMyrFreeMemNode then
    DoEmitFreeMem(TMyrFreeMemNode(AStmt))
  else if AStmt is TMyrResizeMemNode then
    DoEmitResizeMem(TMyrResizeMemNode(AStmt))
  else if AStmt is TMyrSetLengthNode then
    DoEmitSetLength(TMyrSetLengthNode(AStmt))
  else if AStmt is TMyrDirectiveNode then
    // Directives in statement position -- no emission needed
  else if AStmt is TMyrCppBlockNode then
    // C++ block -- not applicable to native backend
  else
    FErrors.Add(AStmt.Location, esError, MYR_ERR_EMT_001,
      'Unsupported statement node: %s', [AStmt.ClassName]);
end;

procedure TMyrEmitter.DoEmitAssign(const ANode: TMyrAssignNode);
var
  LName: string;
  LValue: TMyrIRExpr;
  LDest: TMyrIRExpr;
  LIsStrLiteralSlot: Boolean;
begin
  // The value is emitted inside each target branch, not here, because the
  // correct form of the value depends on what the target is. Each branch
  // emits it as its FIRST action, so evaluation order is unchanged.
  if ANode.Target is TMyrIndexAccessNode then
  begin
    // Array element assignment: arr[i] := value
    LValue := DoEmitExpression(ANode.ValueExpr);
    LDest := FBackend.GetIndex(
      DoEmitExpression(TMyrIndexAccessNode(ANode.Target).BaseExpr),
      DoEmitExpression(TMyrIndexAccessNode(ANode.Target).IndexExpr));
    case ANode.Op of
      aoAssign:      FBackend.SetVal(LDest, LValue);
      aoPlusAssign:  FBackend.SetVal(LDest, FBackend.Add(LDest, LValue));
      aoMinusAssign: FBackend.SetVal(LDest, FBackend.Sub(LDest, LValue));
      aoMulAssign:   FBackend.SetVal(LDest, FBackend.Mul(LDest, LValue));
      aoDivAssign:   FBackend.SetVal(LDest, FBackend.IDiv(LDest, LValue));
    else
      FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_006,
        'Unsupported assign operator: %d', [Ord(ANode.Op)]);
    end;
  end
  else if (ANode.Target is TMyrDotAccessNode) and
          (TMyrDotAccessNode(ANode.Target).AccessKind = dakField) then
  begin
    // Field assignment: rec.field := value (or ptr^.field := value)
    // String literal to a string field: wrap with RT_StrFromLiteral and assign
    // through RT_StrAssign so the old value is released and the new one AddRef'd.
    // Both must land together -- a bare wrap is released by Phase 1 after the
    // fieldaddr store, turning a crash into a silent use-after-free.
    LIsStrLiteralSlot := (ANode.Op = aoAssign) and
                         (ANode.ValueExpr is TMyrStringLiteralNode) and
                         (ANode.Target is TMyrExprNode) and
                         DoIsStringType(TMyrExprNode(ANode.Target));

    if LIsStrLiteralSlot then
      LValue := FBackend.Invoke(RT_StrFromLiteral,
        [FBackend.S(TMyrStringLiteralNode(ANode.ValueExpr).StringValue),
         FBackend.I(Length(TMyrStringLiteralNode(ANode.ValueExpr).StringValue))])
    else
      LValue := DoEmitExpression(ANode.ValueExpr);

    if (TMyrDotAccessNode(ANode.Target).BaseExpr is TMyrDerefNode) and
       (TMyrExprNode(TMyrDerefNode(TMyrDotAccessNode(ANode.Target).BaseExpr).BaseExpr).ResolvedType is TMyrPointerTypeNode) and
       (TMyrPointerTypeNode(TMyrExprNode(TMyrDerefNode(TMyrDotAccessNode(ANode.Target).BaseExpr).BaseExpr).ResolvedType).TargetType is TMyrTypeRefNode) and
       (TMyrTypeRefNode(TMyrPointerTypeNode(TMyrExprNode(TMyrDerefNode(TMyrDotAccessNode(ANode.Target).BaseExpr).BaseExpr).ResolvedType).TargetType).ResolvedDecl is TMyrTypeDeclNode) then
      LDest := FBackend.GetField(
        FBackend.Deref(
          DoEmitExpression(TMyrDerefNode(TMyrDotAccessNode(ANode.Target).BaseExpr).BaseExpr),
          TMyrTypeDeclNode(TMyrTypeRefNode(TMyrPointerTypeNode(TMyrExprNode(
            TMyrDerefNode(TMyrDotAccessNode(ANode.Target).BaseExpr).BaseExpr).ResolvedType).TargetType).ResolvedDecl).DeclName),
        TMyrDotAccessNode(ANode.Target).MemberName)
    else
      LDest := FBackend.GetField(
        DoEmitExpression(TMyrDotAccessNode(ANode.Target).BaseExpr),
        TMyrDotAccessNode(ANode.Target).MemberName);
    case ANode.Op of
      aoAssign:
        if LIsStrLiteralSlot then
          FBackend.Call(RT_StrAssign,
            [FBackend.AddrOfVal(LDest), LValue])
        else
          FBackend.SetVal(LDest, LValue);
      aoPlusAssign:  FBackend.SetVal(LDest, FBackend.Add(LDest, LValue));
      aoMinusAssign: FBackend.SetVal(LDest, FBackend.Sub(LDest, LValue));
      aoMulAssign:   FBackend.SetVal(LDest, FBackend.Mul(LDest, LValue));
      aoDivAssign:   FBackend.SetVal(LDest, FBackend.IDiv(LDest, LValue));
    else
      FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_006,
        'Unsupported assign operator: %d', [Ord(ANode.Op)]);
    end;
  end
  else if ANode.Target is TMyrDerefNode then
  begin
    // Pointer dereference assignment: ptr^ := value
    LValue := DoEmitExpression(ANode.ValueExpr);
    LDest := FBackend.Deref(DoEmitExpression(TMyrDerefNode(ANode.Target).BaseExpr));
    case ANode.Op of
      aoAssign:      FBackend.SetVal(LDest, LValue);
      aoPlusAssign:  FBackend.SetVal(LDest, FBackend.Add(LDest, LValue));
      aoMinusAssign: FBackend.SetVal(LDest, FBackend.Sub(LDest, LValue));
      aoMulAssign:   FBackend.SetVal(LDest, FBackend.Mul(LDest, LValue));
      aoDivAssign:   FBackend.SetVal(LDest, FBackend.IDiv(LDest, LValue));
    else
      FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_006,
        'Unsupported assign operator: %d', [Ord(ANode.Op)]);
    end;
  end
  else
  begin
    // Simple variable assignment
    LName := DoGetDesignatorName(ANode.Target);

    // Record literal into a named record: store fields directly, same as the
    // declaration path. Going through a temp would copy the record with a
    // register-sized struct assign, which truncates records > 8 bytes.
    if (ANode.Op = aoAssign) and (ANode.ValueExpr is TMyrRecordLiteralNode) then
    begin
      DoEmitRecordLiteralInto(FBackend.Get(LName), TMyrRecordLiteralNode(ANode.ValueExpr));
      Exit;
    end;

    // A bare string literal lowers to a raw .rdata address, which has no
    // TStringRec header. Storing it into a string slot faults on the next
    // RT_StrData/RT_StrRelease. Wrap it exactly as the declaration path does,
    // then assign through RT_StrAssign so the old value is released and the
    // new one AddRef'd. The wrap and RT_StrAssign must land together: backend
    // Phase 1 releases the temp after the store, so a bare wrap would convert
    // the crash into a use-after-free.
    LIsStrLiteralSlot := (ANode.Op = aoAssign) and
                         (ANode.ValueExpr is TMyrStringLiteralNode) and
                         (ANode.Target is TMyrExprNode) and
                         DoIsStringType(TMyrExprNode(ANode.Target));

    if LIsStrLiteralSlot then
      LValue := FBackend.Invoke(RT_StrFromLiteral,
        [FBackend.S(TMyrStringLiteralNode(ANode.ValueExpr).StringValue),
         FBackend.I(Length(TMyrStringLiteralNode(ANode.ValueExpr).StringValue))])
    else
      LValue := DoEmitExpression(ANode.ValueExpr);

    case ANode.Op of
      aoAssign:
        if LIsStrLiteralSlot or
           ((ANode.Target is TMyrExprNode) and DoIsStringType(TMyrExprNode(ANode.Target))) then
        begin
          // String slot, kept in SSA (never written through its address: at
          // full opt a slot rewritten via RT_StrAssign(&t, ..) reads back
          // stale). A fresh literal or a temp hands its reference to the
          // slot; a plain variable value needs its own reference first. The
          // old value is released once the new one is safely held.
          if not LIsStrLiteralSlot and not DoIsStringTemp(ANode.ValueExpr) then
            FBackend.Call(RT_StrAddRef, [LValue]);
          FBackend.Call(RT_StrRelease, [FBackend.Get(LName)]);
          FBackend.Let(LName, LValue);
        end
        else
          FBackend.Let(LName, LValue);
      aoPlusAssign:  FBackend.Let(LName, FBackend.Add(FBackend.Get(LName), LValue));
      aoMinusAssign: FBackend.Let(LName, FBackend.Sub(FBackend.Get(LName), LValue));
      aoMulAssign:   FBackend.Let(LName, FBackend.Mul(FBackend.Get(LName), LValue));
      aoDivAssign:   FBackend.Let(LName, FBackend.IDiv(FBackend.Get(LName), LValue));
    else
      FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_006,
        'Unsupported assign operator: %d', [Ord(ANode.Op)]);
    end;
  end;
end;

procedure TMyrEmitter.DoEmitReturn(const ANode: TMyrReturnNode);
begin
  if ANode.ValueExpr <> nil then
    FBackend.Ret(DoEmitExpression(ANode.ValueExpr))
  else
    FBackend.Ret();
end;

procedure TMyrEmitter.DoEmitCallStmt(const ANode: TMyrCallStmtNode);
var
  LCallExpr: TMyrCallExprNode;
  LArgs: array of TMyrIRExpr;
  LIdx: Integer;
  LFuncName: string;
begin
  if not (ANode.CallExpr is TMyrCallExprNode) then
  begin
    FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_001,
      'Expected call expression in call statement', []);
    Exit;
  end;

  LCallExpr := TMyrCallExprNode(ANode.CallExpr);
  LFuncName := DoGetDesignatorName(LCallExpr.Callee);

  SetLength(LArgs, LCallExpr.Args.Count);
  for LIdx := 0 to LCallExpr.Args.Count - 1 do
  begin
    if (LCallExpr.Args[LIdx] is TMyrStringLiteralNode) and
       DoRoutineParamIsString(LCallExpr.ResolvedRoutine, LIdx) then
      LArgs[LIdx] := DoNewStringTemp(FBackend.Invoke(RT_StrFromLiteral,
        [FBackend.S(TMyrStringLiteralNode(LCallExpr.Args[LIdx]).StringValue),
         FBackend.I(Length(TMyrStringLiteralNode(LCallExpr.Args[LIdx]).StringValue))]))
    else
    begin
      LArgs[LIdx] := DoEmitExpression(LCallExpr.Args[LIdx]);
      // Small records passed by value: the emitted expression is a pointer
      // to the record; dereference it to load the packed integer value
      // that the C ABI expects in the register.
      if DoRoutineParamIsSmallRecord(LCallExpr.ResolvedRoutine, LIdx) then
        LArgs[LIdx] := FBackend.Deref(LArgs[LIdx],
          DoGetSmallRecordValueType(
            TMyrRoutineDeclNode(LCallExpr.ResolvedRoutine).Params[LIdx].TypeExpr));
    end;
  end;

  // A discarded string result is a temp nobody else will release
  if DoRoutineReturnsString(LCallExpr.ResolvedRoutine) then
    FBackend.Call(RT_StrRelease, [DoNewStringTemp(FBackend.Invoke(LFuncName, LArgs))])
  else
    FBackend.Call(LFuncName, LArgs);

  for LIdx := 0 to LCallExpr.Args.Count - 1 do
  begin
    if (LCallExpr.Args[LIdx] is TMyrStringLiteralNode) and
       DoRoutineParamIsString(LCallExpr.ResolvedRoutine, LIdx) then
      FBackend.Call(RT_StrRelease, [LArgs[LIdx]])
    else
      DoReleaseStringTemp(LCallExpr.Args[LIdx], LArgs[LIdx]);
  end;
end;

procedure TMyrEmitter.DoEmitPrint(const ANode: TMyrPrintNode);
var
  LArgs: TList<TMyrIRExpr>;
  LTemps: TList<TMyrIRExpr>;
  LIdx: Integer;
  LEmitted: TMyrIRExpr;
  LTemp: TMyrIRExpr;
begin
  LArgs := TList<TMyrIRExpr>.Create();
  LTemps := TList<TMyrIRExpr>.Create();
  try
    for LIdx := 0 to ANode.Args.Count - 1 do
    begin
      // cstr(temp) borrows the temp's data: emit the temp here so it can be
      // released after printf has read it, wrap it as cstr would.
      if (ANode.Args[LIdx] is TMyrIntrinsicExprNode) and
         (TMyrIntrinsicExprNode(ANode.Args[LIdx]).IntrinsicKind = ikCStr) and
         DoIsStringTemp(TMyrIntrinsicExprNode(ANode.Args[LIdx]).Args[0]) then
      begin
        LTemp := DoEmitExpression(TMyrIntrinsicExprNode(ANode.Args[LIdx]).Args[0]);
        LTemps.Add(LTemp);
        LEmitted := FBackend.Invoke(RT_StrData, [LTemp]);
      end
      else
        LEmitted := DoEmitExpression(ANode.Args[LIdx]);
      // printf varargs: an INTEGER conversion (%d and friends) reads the
      // integer register, so a float argument must be truncated first. A FLOAT
      // conversion (%f/%g/%e/%a) reads the double, and truncating there
      // destroys the value -- printf then reinterprets the integer bits as a
      // double, which is how 3.14 printed as 1.4822e-323.
      // The format string is a literal on the AST, so what each position
      // expects is known rather than guessed from the argument type alone.
      if (LIdx > 0) and (ANode.Args[LIdx] is TMyrExprNode) and
         DoIsFloatType(TMyrExprNode(ANode.Args[LIdx])) and
         (not DoFormatWantsFloatArg(ANode, LIdx - 1)) then
        LEmitted := FBackend.ConvertFloat64ToInt(LEmitted);
      LArgs.Add(LEmitted);
    end;

    if LArgs.Count > 0 then
    begin
      FBackend.Call('printf', LArgs.ToArray());
      // Release the string temps this print consumed
      for LIdx := 0 to ANode.Args.Count - 1 do
        DoReleaseStringTemp(ANode.Args[LIdx], LArgs[LIdx]);
      for LTemp in LTemps do
        FBackend.Call(RT_StrRelease, [LTemp]);
      // Print newline if println (IsPrintLn)
      if ANode.IsLn then
        FBackend.Call('printf', [FBackend.S(#10)]);
    end
    else
    begin
      // println with no args -- just newline
      if ANode.IsLn then
        FBackend.Call('printf', [FBackend.S(#10)]);
    end;
  finally
    LTemps.Free();
    LArgs.Free();
  end;
end;

procedure TMyrEmitter.DoEmitIf(const ANode: TMyrIfNode);
begin
  FBackend.When(DoEmitExpression(ANode.Condition));
  DoEmitStatementList(ANode.ThenBody);
  if ANode.ElseBody.Count > 0 then
  begin
    FBackend.Otherwise();
    DoEmitStatementList(ANode.ElseBody);
  end;
  FBackend.EndWhen();
end;

procedure TMyrEmitter.DoEmitWhile(const ANode: TMyrWhileNode);
begin
  FBackend.Loop(DoEmitExpression(ANode.Condition));
  DoEmitStatementList(ANode.Body);
  FBackend.EndLoop();
end;

procedure TMyrEmitter.DoEmitFor(const ANode: TMyrForNode);
var
  LDecl: TMyrASTNode;
begin
  // If the for-var is a module-scope global, declare a local shadow
  // so the backend's SSA phi nodes get a real stack slot.
  for LDecl in FModule.Declarations do
  begin
    if (LDecl is TMyrVarDeclNode) and
       (TMyrVarDeclNode(LDecl).DeclName = ANode.IteratorName) then
    begin
      FBackend.VarDecl(ANode.IteratorName,
        DoMapValueType(TMyrVarDeclNode(LDecl).TypeExpr));
      Break;
    end;
  end;

  if ANode.IsDownTo then
    FBackend.CountDown(ANode.IteratorName,
      DoEmitExpression(ANode.StartExpr),
      DoEmitExpression(ANode.EndExpr))
  else
    FBackend.Count(ANode.IteratorName,
      DoEmitExpression(ANode.StartExpr),
      DoEmitExpression(ANode.EndExpr));

  DoEmitStatementList(ANode.Body);
  FBackend.EndCount();
end;

procedure TMyrEmitter.DoEmitRepeat(const ANode: TMyrRepeatNode);
begin
  FBackend.DoRepeat();
  DoEmitStatementList(ANode.Body);
  FBackend.StopWhen(DoEmitExpression(ANode.Condition));
end;

procedure TMyrEmitter.DoEmitMatch(const ANode: TMyrMatchNode);
var
  LArm: TMyrMatchArmNode;
  LLabel: TMyrMatchLabelNode;
  LValues: array of TMyrIRExpr;
  LRanges: array of TMyrIRCaseRange;
  LArmIdx: Integer;
  LLabelIdx: Integer;
  LValueCount: Integer;
  LRangeCount: Integer;
  LLowVal: Int64;
  LHighVal: Int64;
  LHasRanges: Boolean;
  LIsUnsigned: Boolean;
begin
  LIsUnsigned := DoIsUnsignedType(TMyrExprNode(ANode.Expr));
  FBackend.Match(DoEmitExpression(ANode.Expr));

  for LArmIdx := 0 to ANode.Arms.Count - 1 do
  begin
    LArm := ANode.Arms[LArmIdx];

    // Count discrete values and ranges
    LValueCount := 0;
    LRangeCount := 0;
    LHasRanges := False;
    for LLabelIdx := 0 to LArm.Labels.Count - 1 do
    begin
      if LArm.Labels[LLabelIdx].HighExpr <> nil then
      begin
        Inc(LRangeCount);
        LHasRanges := True;
      end
      else
        Inc(LValueCount);
    end;

    // Build separate arrays for discrete values and ranges
    SetLength(LValues, LValueCount);
    SetLength(LRanges, LRangeCount);
    LValueCount := 0;
    LRangeCount := 0;
    for LLabelIdx := 0 to LArm.Labels.Count - 1 do
    begin
      LLabel := LArm.Labels[LLabelIdx];
      if LLabel.HighExpr <> nil then
      begin
        // Range label: evaluate both bounds to constants
        if DoEvalConstExpr(LLabel.LowExpr, LLowVal) and
           DoEvalConstExpr(LLabel.HighExpr, LHighVal) then
        begin
          LRanges[LRangeCount].LowValue := LLowVal;
          LRanges[LRangeCount].HighValue := LHighVal;
          Inc(LRangeCount);
        end;
      end
      else
      begin
        LValues[LValueCount] := DoEmitExpression(LLabel.LowExpr);
        Inc(LValueCount);
      end;
    end;

    if LHasRanges then
      FBackend.On(LValues, LRanges, LIsUnsigned)
    else
      FBackend.On(LValues);

    DoEmitStatementList(LArm.Body);
  end;

  if ANode.ElseBody.Count > 0 then
  begin
    FBackend.OnElse();
    DoEmitStatementList(ANode.ElseBody);
  end;

  FBackend.EndMatch();
end;

procedure TMyrEmitter.DoEmitGuard(const ANode: TMyrGuardNode);
begin
  FBackend.Guard();
  DoEmitStatementList(ANode.GuardBody);
  if ANode.ExceptBody.Count > 0 then
  begin
    FBackend.Catch();
    DoEmitStatementList(ANode.ExceptBody);
  end;
  if ANode.FinallyBody.Count > 0 then
  begin
    FBackend.Ensure();
    DoEmitStatementList(ANode.FinallyBody);
  end;
  FBackend.EndGuard();
end;

procedure TMyrEmitter.DoEmitThrow(const ANode: TMyrThrowNode);
begin
  FBackend.Throw(DoEmitExpression(ANode.MessageExpr));
end;

procedure TMyrEmitter.DoEmitThrowCode(const ANode: TMyrThrowCodeNode);
begin
  FBackend.ThrowCode(DoEmitExpression(ANode.CodeExpr),
    DoEmitExpression(ANode.MessageExpr));
end;

procedure TMyrEmitter.DoEmitAssert(const ANode: TMyrAssertStmtNode);
var
  LFile: TMyrIRExpr;
  LLine: TMyrIRExpr;
  LMsg: TMyrIRExpr;
  LExpected: TMyrIRExpr;
  LActual: TMyrIRExpr;
  LCmpExpected: TMyrIRExpr;
  LCmpActual: TMyrIRExpr;
  LCmpRoutine: string;
begin
  LFile := FBackend.S(FModule.SourceFile);
  LLine := FBackend.I(ANode.Location.StartLine);

  case ANode.AssertKind of
    akAssert:
      FBackend.Call('RT_TestAssert', [
        DoEmitExpression(ANode.Args[0]), LFile, LLine]);
    akTrue:
      FBackend.Call('RT_TestAssertTrue', [
        DoEmitExpression(ANode.Args[0]), LFile, LLine]);
    akFalse:
      FBackend.Call('RT_TestAssertFalse', [
        DoEmitExpression(ANode.Args[0]), LFile, LLine]);
    akEq:
    begin
      if ANode.Args.Count > 2 then
        LMsg := DoEmitExpression(ANode.Args[2])
      else
        LMsg := FBackend.Null();
      LExpected := DoEmitExpression(ANode.Args[0]);
      LActual := DoEmitExpression(ANode.Args[1]);
      LCmpRoutine := DoAssertCmpRoutine(TMyrExprNode(ANode.Args[0]), TMyrExprNode(ANode.Args[1]));
      // The string compare is strcmp-based: a managed string operand must be
      // passed as its char data (same as cstr()); a bare literal already is.
      if LCmpRoutine = RT_TestAssertCmpStr then
      begin
        if not (ANode.Args[0] is TMyrStringLiteralNode) then
          LCmpExpected := FBackend.Invoke(RT_StrData, [LExpected])
        else
          LCmpExpected := LExpected;
        if not (ANode.Args[1] is TMyrStringLiteralNode) then
          LCmpActual := FBackend.Invoke(RT_StrData, [LActual])
        else
          LCmpActual := LActual;
      end
      else
      begin
        LCmpExpected := LExpected;
        LCmpActual := LActual;
      end;
      FBackend.Call(LCmpRoutine, [
        LCmpExpected, LCmpActual, FBackend.I(RT_CMP_EQ), LMsg, LFile, LLine]);
      DoReleaseStringTemp(ANode.Args[0], LExpected);
      DoReleaseStringTemp(ANode.Args[1], LActual);
    end;
    akEqF:
      FBackend.Call('RT_TestAssertCmpFloatTol', [
        DoEmitExpression(ANode.Args[0]), DoEmitExpression(ANode.Args[1]),
        DoEmitExpression(ANode.Args[2]),
        FBackend.I(RT_CMP_EQ), FBackend.Null(), LFile, LLine]);
    akNil:
      FBackend.Call('RT_TestAssertNil', [
        DoEmitExpression(ANode.Args[0]), LFile, LLine]);
    akNotNil:
      FBackend.Call('RT_TestAssertNotNil', [
        DoEmitExpression(ANode.Args[0]), LFile, LLine]);
    akFail:
      FBackend.Call('RT_TestFail', [
        DoEmitExpression(ANode.Args[0]), LFile, LLine]);
  else
    FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_001,
      'Unsupported assert kind: %d', [Ord(ANode.AssertKind)]);
  end;
end;

procedure TMyrEmitter.DoEmitNew(const ANode: TMyrNewNode);
var
  LName: string;
  LTypeDecl: TMyrTypeDeclNode;
  LTargetDecl: TMyrTypeDeclNode;
  LSizeExpr: TMyrIRExpr;
begin
  // new(ptr) -- allocates typed memory: ptr := RT_GetMem(sizeof(type))
  LName := DoGetDesignatorName(ANode.ArgExpr);

  // Get the type from the pointer's resolved type
  if (TMyrExprNode(ANode.ArgExpr).ResolvedType is TMyrTypeDeclNode) then
  begin
    LTypeDecl := TMyrTypeDeclNode(TMyrExprNode(ANode.ArgExpr).ResolvedType);
    if LTypeDecl.TypeDef is TMyrPointerTypeNode then
    begin
      if TMyrPointerTypeNode(LTypeDecl.TypeDef).TargetType is TMyrTypeRefNode then
      begin
        if TMyrTypeRefNode(TMyrPointerTypeNode(LTypeDecl.TypeDef).TargetType).ResolvedDecl is TMyrTypeDeclNode then
        begin
          LTargetDecl := TMyrTypeDeclNode(
            TMyrTypeRefNode(TMyrPointerTypeNode(LTypeDecl.TypeDef).TargetType).ResolvedDecl);
          if LTargetDecl.ByteSize > 0 then
            LSizeExpr := FBackend.I(LTargetDecl.ByteSize)
          else
            LSizeExpr := FBackend.TypeSize(LTargetDecl.DeclName);
          FBackend.Let(LName, FBackend.Invoke('RT_GetMem', [LSizeExpr]));
          Exit;
        end;
      end;
    end;
  end
  else if (TMyrExprNode(ANode.ArgExpr).ResolvedType is TMyrPointerTypeNode) then
  begin
    // Bare pointer type (e.g. "pointer to uint8")
    if TMyrPointerTypeNode(TMyrExprNode(ANode.ArgExpr).ResolvedType).TargetType is TMyrTypeRefNode then
    begin
      if TMyrTypeRefNode(TMyrPointerTypeNode(TMyrExprNode(ANode.ArgExpr).ResolvedType).TargetType).ResolvedDecl is TMyrTypeDeclNode then
      begin
        LTargetDecl := TMyrTypeDeclNode(
          TMyrTypeRefNode(TMyrPointerTypeNode(TMyrExprNode(ANode.ArgExpr).ResolvedType).TargetType).ResolvedDecl);
        if LTargetDecl.ByteSize > 0 then
          LSizeExpr := FBackend.I(LTargetDecl.ByteSize)
        else
          LSizeExpr := FBackend.TypeSize(LTargetDecl.DeclName);
        FBackend.Let(LName, FBackend.Invoke('RT_GetMem', [LSizeExpr]));
        Exit;
      end;
    end;
  end;

  // Fallback: cannot determine type size
  FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_001,
    'Cannot determine type size for new', []);
end;

{ TMyrEmitter.DoEmitDispose }
procedure TMyrEmitter.DoEmitDispose(const ANode: TMyrDisposeNode);
begin
  // dispose(ptr) -- frees typed memory and sets pointer to nil
  FBackend.Call('RT_FreeMem', [DoEmitExpression(ANode.ArgExpr)]);
  FBackend.Let(DoGetDesignatorName(ANode.ArgExpr), FBackend.I(0));
end;

{ TMyrEmitter.DoEmitGetMem }
procedure TMyrEmitter.DoEmitGetMem(const ANode: TMyrGetMemNode);
var
  LName: string;
  LTypeDecl: TMyrTypeDeclNode;
  LTargetDecl: TMyrTypeDeclNode;
  LSizeExpr: TMyrIRExpr;
begin
  // getmem(ptr) -- allocate raw memory based on pointer target type
  LName := DoGetDesignatorName(ANode.ArgExpr);

  if (TMyrExprNode(ANode.ArgExpr).ResolvedType is TMyrTypeDeclNode) then
  begin
    LTypeDecl := TMyrTypeDeclNode(TMyrExprNode(ANode.ArgExpr).ResolvedType);
    if LTypeDecl.TypeDef is TMyrPointerTypeNode then
    begin
      if TMyrPointerTypeNode(LTypeDecl.TypeDef).TargetType is TMyrTypeRefNode then
      begin
        if TMyrTypeRefNode(TMyrPointerTypeNode(LTypeDecl.TypeDef).TargetType).ResolvedDecl is TMyrTypeDeclNode then
        begin
          LTargetDecl := TMyrTypeDeclNode(
            TMyrTypeRefNode(TMyrPointerTypeNode(LTypeDecl.TypeDef).TargetType).ResolvedDecl);
          if LTargetDecl.ByteSize > 0 then
            LSizeExpr := FBackend.I(LTargetDecl.ByteSize)
          else
            LSizeExpr := FBackend.TypeSize(LTargetDecl.DeclName);
          FBackend.Let(LName, FBackend.Invoke('RT_GetMem', [LSizeExpr]));
          Exit;
        end;
      end;
    end;
  end
  else if (TMyrExprNode(ANode.ArgExpr).ResolvedType is TMyrPointerTypeNode) then
  begin
    // Bare pointer type (e.g. "pointer to uint8")
    if TMyrPointerTypeNode(TMyrExprNode(ANode.ArgExpr).ResolvedType).TargetType is TMyrTypeRefNode then
    begin
      if TMyrTypeRefNode(TMyrPointerTypeNode(TMyrExprNode(ANode.ArgExpr).ResolvedType).TargetType).ResolvedDecl is TMyrTypeDeclNode then
      begin
        LTargetDecl := TMyrTypeDeclNode(
          TMyrTypeRefNode(TMyrPointerTypeNode(TMyrExprNode(ANode.ArgExpr).ResolvedType).TargetType).ResolvedDecl);
        if LTargetDecl.ByteSize > 0 then
          LSizeExpr := FBackend.I(LTargetDecl.ByteSize)
        else
          LSizeExpr := FBackend.TypeSize(LTargetDecl.DeclName);
        FBackend.Let(LName, FBackend.Invoke('RT_GetMem', [LSizeExpr]));
        Exit;
      end;
    end;
  end;

  // Fallback: untyped pointer -- caller must manage size
  FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_001,
    'Cannot determine type size for getmem', []);
end;

procedure TMyrEmitter.DoEmitFreeMem(const ANode: TMyrFreeMemNode);
begin
  // freemem(ptr) -- free raw memory
  FBackend.Call('RT_FreeMem', [DoEmitExpression(ANode.ArgExpr)]);
end;

procedure TMyrEmitter.DoEmitResizeMem(const ANode: TMyrResizeMemNode);
var
  LName: string;
begin
  // resizemem(ptr, newsize) -- reallocate
  LName := DoGetDesignatorName(ANode.PtrExpr);
  FBackend.Let(LName, FBackend.Invoke('RT_ReAllocMem',
    [DoEmitExpression(ANode.PtrExpr), DoEmitExpression(ANode.SizeExpr)]));
end;

procedure TMyrEmitter.DoEmitSetLength(const ANode: TMyrSetLengthNode);
var
  LName: string;
  LArrayType: TMyrArrayTypeNode;
  LElemTypeDecl: TMyrTypeDeclNode;
  LElemSize: Int64;
  LResolvedType: TMyrASTNode;
begin
  LName := DoGetDesignatorName(ANode.TargetExpr);
  LResolvedType := TMyrExprNode(ANode.TargetExpr).ResolvedType;
  LArrayType := nil;

  // Find the TMyrArrayTypeNode -- may be wrapped in TMyrTypeDeclNode or direct
  if (LResolvedType is TMyrTypeDeclNode) and
     (TMyrTypeDeclNode(LResolvedType).TypeDef is TMyrArrayTypeNode) then
    LArrayType := TMyrArrayTypeNode(TMyrTypeDeclNode(LResolvedType).TypeDef)
  else if LResolvedType is TMyrArrayTypeNode then
    LArrayType := TMyrArrayTypeNode(LResolvedType);

  if (LArrayType <> nil) and LArrayType.IsDynamic then
  begin
    // Dynamic array: RT_SetLength(addr_of_var, newLen, elemSize)
    LElemSize := 8;
    if (LArrayType.ElementType is TMyrTypeRefNode) and
       (TMyrTypeRefNode(LArrayType.ElementType).ResolvedDecl is TMyrTypeDeclNode) then
    begin
      LElemTypeDecl := TMyrTypeDeclNode(
        TMyrTypeRefNode(LArrayType.ElementType).ResolvedDecl);
      if LElemTypeDecl.ByteSize > 0 then
        LElemSize := LElemTypeDecl.ByteSize;
    end;
    FBackend.Call('RT_SetLength', [
      FBackend.AddrOf(LName),
      DoEmitExpression(ANode.LengthExpr),
      FBackend.I(LElemSize)]);
    Exit;
  end;

  // Raw pointer or other: use resizemem semantics
  FBackend.Let(LName, FBackend.Invoke('RT_ReAllocMem',
    [DoEmitExpression(ANode.TargetExpr),
     DoEmitExpression(ANode.LengthExpr)]));
end;

function TMyrEmitter.DoEmitExpression(const AExpr: TMyrASTNode): TMyrIRExpr;
begin
  Result := Default(TMyrIRExpr);

  if AExpr is TMyrIntLiteralNode then
    Result := FBackend.I(TMyrIntLiteralNode(AExpr).IntValue)
  else if AExpr is TMyrFloatLiteralNode then
    Result := FBackend.F(TMyrFloatLiteralNode(AExpr).FloatValue)
  else if AExpr is TMyrStringLiteralNode then
    Result := FBackend.S(TMyrStringLiteralNode(AExpr).StringValue)
  else if AExpr is TMyrWStringLiteralNode then
    Result := FBackend.W(TMyrWStringLiteralNode(AExpr).StringValue)
  else if AExpr is TMyrBoolLiteralNode then
    Result := FBackend.B(TMyrBoolLiteralNode(AExpr).BoolValue)
  else if AExpr is TMyrNilLiteralNode then
    Result := FBackend.Null()
  else if AExpr is TMyrIdentifierNode then
  begin
    if TMyrIdentifierNode(AExpr).ResolvedDecl is TMyrRoutineDeclNode then
      Result := FBackend.FuncAddr(TMyrIdentifierNode(AExpr).IdentName)
    else
      Result := FBackend.Get(TMyrIdentifierNode(AExpr).IdentName);
  end
  else if AExpr is TMyrBinaryExprNode then
    Result := DoEmitBinaryExpr(TMyrBinaryExprNode(AExpr))
  else if AExpr is TMyrUnaryExprNode then
    Result := DoEmitUnaryExpr(TMyrUnaryExprNode(AExpr))
  else if AExpr is TMyrCallExprNode then
    Result := DoEmitCallExpr(TMyrCallExprNode(AExpr))
  else if AExpr is TMyrDotAccessNode then
    Result := DoEmitDotAccess(TMyrDotAccessNode(AExpr))
  else if AExpr is TMyrIndexAccessNode then
    Result := FBackend.GetIndex(
      DoEmitExpression(TMyrIndexAccessNode(AExpr).BaseExpr),
      DoEmitExpression(TMyrIndexAccessNode(AExpr).IndexExpr))
  else if AExpr is TMyrDerefNode then
    Result := FBackend.Deref(DoEmitExpression(TMyrDerefNode(AExpr).BaseExpr))
  else if AExpr is TMyrTypeCastExprNode then
    Result := DoEmitTypeCast(TMyrTypeCastExprNode(AExpr))
  else if AExpr is TMyrIntrinsicExprNode then
    Result := DoEmitIntrinsic(TMyrIntrinsicExprNode(AExpr))
  else if AExpr is TMyrRecordLiteralNode then
    Result := DoEmitRecordLiteral(TMyrRecordLiteralNode(AExpr))
  else if AExpr is TMyrSetLiteralExprNode then
    Result := DoEmitSetLiteral(TMyrSetLiteralExprNode(AExpr))
  else if AExpr is TMyrCppExprNode then
    // cpp() expressions are C++ interop -- not applicable to native backend
    FErrors.Add(AExpr.Location, esError, MYR_ERR_EMT_002,
      'cpp() expressions not supported in native backend', [])
  else if AExpr is TMyrTypeRefNode then
    // Type reference as expression -- should not appear standalone
    FErrors.Add(AExpr.Location, esError, MYR_ERR_EMT_002,
      'Type reference in expression context', [])
  else
    FErrors.Add(AExpr.Location, esError, MYR_ERR_EMT_002,
      'Unsupported expression node: %s', [AExpr.ClassName]);
end;

function TMyrEmitter.DoEmitDotAccess(const ANode: TMyrDotAccessNode): TMyrIRExpr;
var
  LTypeDecl: TMyrTypeDeclNode;
  LChoices: TMyrChoicesTypeNode;
  LValue: Int64;
begin
  Result := Default(TMyrIRExpr);

  if ANode.AccessKind = dakChoices then
  begin
    // Resolve choices value directly from the AST
    if ANode.ResolvedType is TMyrTypeDeclNode then
    begin
      LTypeDecl := TMyrTypeDeclNode(ANode.ResolvedType);
      if LTypeDecl.TypeDef is TMyrChoicesTypeNode then
      begin
        LChoices := TMyrChoicesTypeNode(LTypeDecl.TypeDef);
        LValue := DoResolveChoicesMemberValue(LChoices, ANode.MemberName);
        Result := FBackend.I(LValue);
      end;
    end;
  end
  else if ANode.AccessKind = dakField then
  begin
    if (ANode.BaseExpr is TMyrDerefNode) and
       (TMyrExprNode(TMyrDerefNode(ANode.BaseExpr).BaseExpr).ResolvedType is TMyrPointerTypeNode) and
       (TMyrPointerTypeNode(TMyrExprNode(TMyrDerefNode(ANode.BaseExpr).BaseExpr).ResolvedType).TargetType is TMyrTypeRefNode) and
       (TMyrTypeRefNode(TMyrPointerTypeNode(TMyrExprNode(TMyrDerefNode(ANode.BaseExpr).BaseExpr).ResolvedType).TargetType).ResolvedDecl is TMyrTypeDeclNode) then
    begin
      // Pointer dereference field access: ptr^.field
      // Extract struct type name from the pointer's target type
      Result := FBackend.GetField(
        FBackend.Deref(
          DoEmitExpression(TMyrDerefNode(ANode.BaseExpr).BaseExpr),
          TMyrTypeDeclNode(TMyrTypeRefNode(TMyrPointerTypeNode(TMyrExprNode(
            TMyrDerefNode(ANode.BaseExpr).BaseExpr).ResolvedType).TargetType).ResolvedDecl).DeclName),
        ANode.MemberName);
    end
    else
      Result := FBackend.GetField(DoEmitExpression(ANode.BaseExpr), ANode.MemberName);
  end
  else if ANode.AccessKind = dakModule then
  begin
    // Module-qualified access -- symbol already emitted by imported module.
    // A routine yields its address, exactly as the identifier path does.
    if ANode.ResolvedDecl is TMyrRoutineDeclNode then
      Result := FBackend.FuncAddr(ANode.MemberName)
    else
      Result := FBackend.Get(ANode.MemberName);
  end
  else
    FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_002,
      'Unsupported dot access kind', []);
end;

function TMyrEmitter.DoEmitBinaryExpr(const ANode: TMyrBinaryExprNode): TMyrIRExpr;
var
  LLeft: TMyrIRExpr;
  LRight: TMyrIRExpr;
begin
  LLeft := DoEmitExpression(ANode.Left);
  LRight := DoEmitExpression(ANode.Right);

  case ANode.Op of
    // Arithmetic / string concatenation / set operations
    boAdd:
      if DoIsStringType(ANode) then
      begin
        // RT_StrConcat takes managed strings; a literal operand is raw chars.
        // Wrap it into a temp slot, run the concat into its own slot, then
        // release every temp operand (literal wrap or nested temp) right
        // after its use. The concat result slot is released by its consumer.
        if ANode.Left is TMyrStringLiteralNode then
          LLeft := DoNewStringTemp(FBackend.Invoke(RT_StrFromLiteral,
            [FBackend.S(TMyrStringLiteralNode(ANode.Left).StringValue),
             FBackend.I(Length(TMyrStringLiteralNode(ANode.Left).StringValue))]));
        if ANode.Right is TMyrStringLiteralNode then
          LRight := DoNewStringTemp(FBackend.Invoke(RT_StrFromLiteral,
            [FBackend.S(TMyrStringLiteralNode(ANode.Right).StringValue),
             FBackend.I(Length(TMyrStringLiteralNode(ANode.Right).StringValue))]));
        Result := DoNewStringTemp(FBackend.Invoke(RT_StrConcat, [LLeft, LRight]));
        if ANode.Left is TMyrStringLiteralNode then
          FBackend.Call(RT_StrRelease, [LLeft])
        else
          DoReleaseStringTemp(ANode.Left, LLeft);
        if ANode.Right is TMyrStringLiteralNode then
          FBackend.Call(RT_StrRelease, [LRight])
        else
          DoReleaseStringTemp(ANode.Right, LRight);
      end
      else if DoIsSetType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.SetUnion(LLeft, LRight)
      else if DoIsFloatType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.FAdd(LLeft, LRight)
      else
        Result := FBackend.Add(LLeft, LRight);
    boSub:
      if DoIsSetType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.SetDiff(LLeft, LRight)
      else if DoIsFloatType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.FSub(LLeft, LRight)
      else
        Result := FBackend.Sub(LLeft, LRight);
    boMul:
      if DoIsSetType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.SetInter(LLeft, LRight)
      else if DoIsFloatType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.FMul(LLeft, LRight)
      else
        Result := FBackend.Mul(LLeft, LRight);
    boIntDiv:     Result := FBackend.IDiv(LLeft, LRight);
    boDiv:        Result := FBackend.FDiv(LLeft, LRight);
    boMod:        Result := FBackend.IMod(LLeft, LRight);

    // Bitwise
    boAnd:        Result := FBackend.BitAnd(LLeft, LRight);
    boOr:         Result := FBackend.BitOr(LLeft, LRight);
    boXor:        Result := FBackend.BitXor(LLeft, LRight);
    boShl:        Result := FBackend.ShiftL(LLeft, LRight);
    boShr:        Result := FBackend.ShiftR(LLeft, LRight);

    // Logical
    boLogicalAnd: Result := FBackend.LogAnd(LLeft, LRight);
    boLogicalOr:  Result := FBackend.LogOr(LLeft, LRight);

    // Comparison
    boEq:
      if DoIsSetType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.SetEq(LLeft, LRight)
      else
        Result := FBackend.Eq(LLeft, LRight);
    boNotEq:
      if DoIsSetType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.SetNe(LLeft, LRight)
      else
        Result := FBackend.Ne(LLeft, LRight);
    boLess:
      if DoIsSetType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.SetSubset(LLeft, LRight)
      else
        Result := FBackend.Lt(LLeft, LRight);
    boGreater:
      if DoIsSetType(TMyrExprNode(ANode.Left)) then
        Result := FBackend.SetSuperset(LLeft, LRight)
      else
        Result := FBackend.Gt(LLeft, LRight);
    boLessEq:     Result := FBackend.Le(LLeft, LRight);
    boGreaterEq:  Result := FBackend.Ge(LLeft, LRight);

    // Set membership
    boIn:         Result := FBackend.SetIn(LLeft, LRight);
  else
    FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_004,
      'Unsupported binary operator: %d', [Ord(ANode.Op)]);
    Result := FBackend.I(0);
  end;
end;

function TMyrEmitter.DoEmitUnaryExpr(const ANode: TMyrUnaryExprNode): TMyrIRExpr;
begin
  // The operand is emitted per arm: uoAddressOf takes the address of a named
  // slot and must not load its value first, or a dead load is emitted for
  // every @x.
  case ANode.Op of
    uoNegate:
      // Unary minus must pick the float op by operand type, exactly as the
      // binary arms do. Integer NEG on a float64 bit pattern is not negation
      // (NEG of 1.0 yields -4.0).
      if DoIsFloatType(TMyrExprNode(ANode.Operand)) then
        Result := FBackend.FNeg(DoEmitExpression(ANode.Operand))
      else
        Result := FBackend.Neg(DoEmitExpression(ANode.Operand));
    uoNot:       Result := FBackend.LogNot(DoEmitExpression(ANode.Operand));
    uoPositive:  Result := DoEmitExpression(ANode.Operand);  // identity
    uoAddressOf:
    begin
      if ANode.Operand is TMyrIdentifierNode then
        Result := FBackend.AddrOf(TMyrIdentifierNode(ANode.Operand).IdentName)
      else
      begin
        FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_005,
          'Address-of requires an identifier', []);
        Result := FBackend.I(0);
      end;
    end;
  else
    FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_005,
      'Unsupported unary operator: %d', [Ord(ANode.Op)]);
    Result := FBackend.I(0);
  end;
end;

function TMyrEmitter.DoEmitCallExpr(const ANode: TMyrCallExprNode): TMyrIRExpr;
var
  LArgs: array of TMyrIRExpr;
  LIdx: Integer;
  LFuncName: string;
  LHasTemps: Boolean;
  LSlot: string;
begin
  LFuncName := DoGetDesignatorName(ANode.Callee);

  SetLength(LArgs, ANode.Args.Count);
  for LIdx := 0 to ANode.Args.Count - 1 do
  begin
    // A literal handed to a string parameter is raw chars; wrap it into a
    // temp slot so the callee sees a managed string. Released after the call.
    if (ANode.Args[LIdx] is TMyrStringLiteralNode) and
       DoRoutineParamIsString(ANode.ResolvedRoutine, LIdx) then
      LArgs[LIdx] := DoNewStringTemp(FBackend.Invoke(RT_StrFromLiteral,
        [FBackend.S(TMyrStringLiteralNode(ANode.Args[LIdx]).StringValue),
         FBackend.I(Length(TMyrStringLiteralNode(ANode.Args[LIdx]).StringValue))]))
    else
    begin
      LArgs[LIdx] := DoEmitExpression(ANode.Args[LIdx]);
      if DoRoutineParamIsSmallRecord(ANode.ResolvedRoutine, LIdx) then
        LArgs[LIdx] := FBackend.Deref(LArgs[LIdx],
          DoGetSmallRecordValueType(
            TMyrRoutineDeclNode(ANode.ResolvedRoutine).Params[LIdx].TypeExpr));
    end;
  end;

  if (ANode.ResolvedRoutine is TMyrRoutineDeclNode) or
     (ANode.ResolvedRoutine is TMyrForwardRoutineDeclNode) then
  begin
    // Run the call now (into a slot) so the temps it consumed can be released
    // right after it. A string result is itself a temp its consumer releases.
    LHasTemps := False;
    for LIdx := 0 to ANode.Args.Count - 1 do
    begin
      if DoIsStringTemp(ANode.Args[LIdx]) or
         ((ANode.Args[LIdx] is TMyrStringLiteralNode) and
          DoRoutineParamIsString(ANode.ResolvedRoutine, LIdx)) then
        LHasTemps := True;
    end;
    if DoRoutineReturnsString(ANode.ResolvedRoutine) then
      Result := DoNewStringTemp(FBackend.Invoke(LFuncName, LArgs))
    else if LHasTemps then
    begin
      Inc(FStrTempSeq);
      LSlot := '_calltmp_' + IntToStr(FStrTempSeq);
      FBackend.Let(LSlot, FBackend.Invoke(LFuncName, LArgs));
      Result := FBackend.Get(LSlot);
    end
    else
      Result := FBackend.Invoke(LFuncName, LArgs);
    for LIdx := 0 to ANode.Args.Count - 1 do
    begin
      if (ANode.Args[LIdx] is TMyrStringLiteralNode) and
         DoRoutineParamIsString(ANode.ResolvedRoutine, LIdx) then
        FBackend.Call(RT_StrRelease, [LArgs[LIdx]])
      else
        DoReleaseStringTemp(ANode.Args[LIdx], LArgs[LIdx]);
    end;
  end
  else
    // Indirect call: emit the callee as a full expression so that
    // field accesses (ops.addFn) produce the proper load chain,
    // not just a bare variable reference to the field name.
    Result := FBackend.InvokeIndirect(DoEmitExpression(ANode.Callee), LArgs);
end;

function TMyrEmitter.DoEmitTypeCast(const ANode: TMyrTypeCastExprNode): TMyrIRExpr;
var
  LInner: TMyrIRExpr;
  LTargetKind: TMyrTokenKind;
  LSourceIsFloat: Boolean;
  LSourceIsUnsigned: Boolean;
  LTargetIsFloat: Boolean;
  LTargetIsUnsigned: Boolean;
begin
  LInner := DoEmitExpression(ANode.Expr);

  if not (ANode.TargetType is TMyrTypeRefNode) then
  begin
    Result := LInner;
    Exit;
  end;

  LTargetKind := TMyrTypeRefNode(ANode.TargetType).TokenKind;
  LSourceIsFloat := (ANode.Expr is TMyrExprNode) and
                    DoIsFloatType(TMyrExprNode(ANode.Expr));
  LSourceIsUnsigned := (ANode.Expr is TMyrExprNode) and
                       DoIsUnsignedType(TMyrExprNode(ANode.Expr));
  LTargetIsFloat := (LTargetKind = tkFloat32) or (LTargetKind = tkFloat64);
  LTargetIsUnsigned := (LTargetKind = tkUInt8) or (LTargetKind = tkUInt16) or
                       (LTargetKind = tkUInt32) or (LTargetKind = tkUInt64);

  // Integer -> float: a numeric conversion (CVTSI2SD), not a bit copy. The
  // source signedness comes from the AST; the backend cannot tell uint64 from
  // int64 on expression temps.
  if LTargetIsFloat and not LSourceIsFloat then
  begin
    if LSourceIsUnsigned then
      Result := FBackend.ConvertUIntToFloat64(LInner)
    else
      Result := FBackend.IntToFloat64(LInner);
    Exit;
  end;

  // Float -> integer: truncate toward zero (CVTTSD2SI) BEFORE any width
  // narrowing below. Without this the low bits of the double's bit pattern
  // were being masked and returned as the integer.
  if LSourceIsFloat and not LTargetIsFloat then
  begin
    if LTargetIsUnsigned then
      LInner := FBackend.ConvertFloat64ToUInt(LInner)
    else
      LInner := FBackend.ConvertFloat64ToInt(LInner);
  end;

  // Integer narrowing -- mask to target width
  if (LTargetKind = tkUInt8) or (LTargetKind = tkInt8) or
     (LTargetKind = tkChar) then
    Result := FBackend.BitAnd(LInner, FBackend.I($FF))
  else if (LTargetKind = tkUInt16) or (LTargetKind = tkInt16) or
          (LTargetKind = tkWChar) then
    Result := FBackend.BitAnd(LInner, FBackend.I($FFFF))
  else if (LTargetKind = tkUInt32) or (LTargetKind = tkInt32) then
    Result := FBackend.BitAnd(LInner, FBackend.I($FFFFFFFF))
  else
    // Widening or same-size -- passthrough
    Result := LInner;
end;

function TMyrEmitter.DoEmitIntrinsic(const ANode: TMyrIntrinsicExprNode): TMyrIRExpr;
var
  LTypeDecl: TMyrTypeDeclNode;
  LArg: TMyrIRExpr;
  LSlot: string;
begin
  Result := Default(TMyrIRExpr);

  case ANode.IntrinsicKind of
    ikParamCount:
      Result := FBackend.Invoke('RT_ParamCount', []);
    ikParamStr:
      Result := FBackend.Invoke('RT_ParamStr',
        [DoEmitExpression(ANode.Args[0])]);
    ikExcCode:
      Result := FBackend.ExcCode();
    ikExcMsg:
      Result := FBackend.ExcMsg();
    ikLen:
    begin
      if DoIsStringType(TMyrExprNode(ANode.Args[0])) then
      begin
        // len(temp): take the length into a slot, then release the temp
        LArg := DoEmitExpression(ANode.Args[0]);
        if DoIsStringTemp(ANode.Args[0]) then
        begin
          Inc(FStrTempSeq);
          LSlot := '_lentmp_' + IntToStr(FStrTempSeq);
          FBackend.Let(LSlot, FBackend.Invoke(RT_Len, [FBackend.I(0), LArg]));
          FBackend.Call(RT_StrRelease, [LArg]);
          Result := FBackend.Get(LSlot);
        end
        else
          Result := FBackend.Invoke(RT_Len, [FBackend.I(0), LArg]);
      end
      else if DoIsWStringType(TMyrExprNode(ANode.Args[0])) then
        Result := FBackend.Invoke(RT_Len,
          [FBackend.I(1), DoEmitExpression(ANode.Args[0])])
      else
        Result := FBackend.Invoke(RT_Len,
          [FBackend.I(2), DoEmitExpression(ANode.Args[0])]);
    end;
    ikUtf8:
      Result := FBackend.Invoke('RT_Utf8',
        [DoEmitExpression(ANode.Args[0])]);
    ikCStr:
      Result := FBackend.Invoke('RT_StrData',
        [DoEmitExpression(ANode.Args[0])]);
    ikSize:
      // size(type) -- compile-time type size from the AST
      if (ANode.Args.Count > 0) and (ANode.Args[0] is TMyrTypeRefNode) and
         (TMyrTypeRefNode(ANode.Args[0]).ResolvedDecl is TMyrTypeDeclNode) then
      begin
        LTypeDecl := TMyrTypeDeclNode(TMyrTypeRefNode(ANode.Args[0]).ResolvedDecl);
        if LTypeDecl.ByteSize > 0 then
          Result := FBackend.I(LTypeDecl.ByteSize)
        else
          Result := FBackend.TypeSize(LTypeDecl.DeclName);
      end
      else if (ANode.Args.Count > 0) and (ANode.Args[0] is TMyrIdentifierNode) and
              (TMyrIdentifierNode(ANode.Args[0]).ResolvedDecl is TMyrTypeDeclNode) then
      begin
        LTypeDecl := TMyrTypeDeclNode(TMyrIdentifierNode(ANode.Args[0]).ResolvedDecl);
        if LTypeDecl.ByteSize > 0 then
          Result := FBackend.I(LTypeDecl.ByteSize)
        else
          Result := FBackend.TypeSize(LTypeDecl.DeclName);
      end
      else
        Result := FBackend.I(0);
    ikWStr:
      Result := FBackend.Invoke('RT_StrUtf16',
        [DoEmitExpression(ANode.Args[0])]);
  else
    FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_002,
      'Unsupported intrinsic kind: %d', [Ord(ANode.IntrinsicKind)]);
  end;
end;

function TMyrEmitter.DoEmitRecordLiteral(const ANode: TMyrRecordLiteralNode): TMyrIRExpr;
var
  LTempName: string;
begin
  // Allocate a local temp for the record, fill it through the same path the
  // declaration and assignment forms use, and return a reference to it. The
  // shared path owns the managed-field wiring (RT_StrFromLiteral +
  // RT_StrAssign), so string fields have exactly one owner here too.
  LTempName := '_rl_' + ANode.TypeName;
  FBackend.VarDecl(LTempName, ANode.TypeName);
  DoEmitRecordLiteralInto(FBackend.Get(LTempName), ANode);
  Result := FBackend.Get(LTempName);
end;

{ TMyrEmitter.DoEmitRecordLiteralInto }
procedure TMyrEmitter.DoEmitRecordLiteralInto(const ABase: TMyrIRExpr;
  const ARecLit: TMyrRecordLiteralNode);
var
  LIdx: Integer;
  LFieldInit: TMyrFieldInitNode;
  LWrapped: TMyrIRExpr;
  LFieldRef: TMyrIRExpr;
begin
  // Store each field directly into the base record expression. No temp record,
  // so no register-sized struct copy (which truncates records > 8 bytes) and
  // exactly one owner for each managed field.
  //
  // Nested record literals recurse with GetField as the new base, so fields
  // materialize directly into the parent's slot at any nesting depth -- no
  // temp allocation, no name collision, no register-sized copy.
  //
  // String literal fields: wrap with RT_StrFromLiteral and assign through
  // RT_StrAssign at the field's address. RT_StrAssign AddRefs the source,
  // which balances the backend Phase 1 release of the wrapped temp, and
  // releases the old field value (nil-safe on a fresh record).
  for LIdx := 0 to ARecLit.FieldInits.Count - 1 do
  begin
    LFieldInit := ARecLit.FieldInits[LIdx];
    LFieldRef := FBackend.GetField(ABase, LFieldInit.FieldName);
    if LFieldInit.ValueExpr is TMyrStringLiteralNode then
    begin
      LWrapped := FBackend.Invoke(RT_StrFromLiteral,
        [FBackend.S(TMyrStringLiteralNode(LFieldInit.ValueExpr).StringValue),
         FBackend.I(Length(TMyrStringLiteralNode(LFieldInit.ValueExpr).StringValue))]);
      FBackend.Call(RT_StrAssign,
        [FBackend.AddrOfVal(LFieldRef), LWrapped]);
    end
    else if LFieldInit.ValueExpr is TMyrRecordLiteralNode then
      // Nested record literal: recurse directly into the field slot
      DoEmitRecordLiteralInto(LFieldRef, TMyrRecordLiteralNode(LFieldInit.ValueExpr))
    else
      FBackend.SetVal(LFieldRef, DoEmitExpression(LFieldInit.ValueExpr));
  end;
end;

function TMyrEmitter.DoEmitSetLiteral(const ANode: TMyrSetLiteralExprNode): TMyrIRExpr;
var
  LElements: array of Integer;
  I: Integer;
  J: Integer;
  LIntVal: Int64;
  LHighVal: Int64;
begin
  // Build integer element array from the set literal elements
  SetLength(LElements, 0);
  for I := 0 to ANode.Elements.Count - 1 do
  begin
    if not DoEvalConstExpr(ANode.Elements[I].LowExpr, LIntVal) then
    begin
      FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_002,
        'Set literal element must be a constant expression', []);
      Result := Default(TMyrIRExpr);
      Exit;
    end;

    if ANode.Elements[I].HighExpr <> nil then
    begin
      // Range element: low..high -- expand to all values in range
      if not DoEvalConstExpr(ANode.Elements[I].HighExpr, LHighVal) then
      begin
        FErrors.Add(ANode.Location, esError, MYR_ERR_EMT_002,
          'Set literal range bound must be a constant expression', []);
        Result := Default(TMyrIRExpr);
        Exit;
      end;
      for J := Integer(LIntVal) to Integer(LHighVal) do
      begin
        SetLength(LElements, Length(LElements) + 1);
        LElements[High(LElements)] := J;
      end;
    end
    else
    begin
      // Discrete element
      SetLength(LElements, Length(LElements) + 1);
      LElements[High(LElements)] := Integer(LIntVal);
    end;
  end;

  // Use the backend's SetLit to construct the set value
  // The type name comes from the resolved type on the expression
  if (ANode.ResolvedType is TMyrTypeDeclNode) then
    Result := FBackend.SetLit(TMyrTypeDeclNode(ANode.ResolvedType).DeclName, LElements)
  else
    Result := FBackend.SetLit('$set', LElements);
end;

function TMyrEmitter.DoMapValueType(const ATypeNode: TMyrASTNode): TMyrValueType;
var
  LTypeRef: TMyrTypeRefNode;
  LTypeDecl: TMyrTypeDeclNode;
begin
  Result := cvtVoid;

  if ATypeNode is TMyrTypeRefNode then
  begin
    LTypeRef := TMyrTypeRefNode(ATypeNode);

    // User-defined types: check resolved declaration
    if (LTypeRef.TokenKind = tkIdentifier) and
       (LTypeRef.ResolvedDecl is TMyrTypeDeclNode) then
    begin
      LTypeDecl := TMyrTypeDeclNode(LTypeRef.ResolvedDecl);
      if LTypeDecl.TypeDef is TMyrChoicesTypeNode then
        Result := cvtInt32
      else if LTypeDecl.TypeDef is TMyrRecordTypeNode then
        Result := cvtPointer  // records on stack, but backend uses struct name
      else if LTypeDecl.TypeDef is TMyrPointerTypeNode then
        Result := cvtPointer
      else if LTypeDecl.TypeDef is TMyrRoutineTypeNode then
        Result := cvtPointer
      else if LTypeDecl.TypeDef is TMyrArrayTypeNode then
        Result := cvtPointer
      else if LTypeDecl.TypeDef is TMyrSetTypeNode then
        Result := cvtInt64
      else if LTypeDecl.TypeDef is TMyrOverlayTypeNode then
        Result := cvtPointer
      else if LTypeDecl.TypeDef is TMyrTypeRefNode then
        // Type alias -- recurse
        Result := DoMapValueType(LTypeDecl.TypeDef)
      else
        FErrors.Add(ATypeNode.Location, esError, MYR_ERR_EMT_003,
          'Cannot map user type: %s', [LTypeDecl.DeclName]);
    end
    else
      Result := DoMapTokenToValueType(LTypeRef.TokenKind);
  end
  else if ATypeNode is TMyrPointerTypeNode then
    Result := cvtPointer
  else if ATypeNode is TMyrRecordTypeNode then
    Result := cvtPointer
  else if ATypeNode is TMyrRoutineTypeNode then
    Result := cvtPointer
  else if ATypeNode is TMyrArrayTypeNode then
    Result := cvtPointer
  else if ATypeNode is TMyrSetTypeNode then
    Result := cvtInt64
  else if ATypeNode is TMyrOverlayTypeNode then
    Result := cvtPointer
  else
    FErrors.Add(ATypeNode.Location, esError, MYR_ERR_EMT_003,
      'Cannot map type node: %s', [ATypeNode.ClassName]);
end;

function TMyrEmitter.DoMapTokenToValueType(const AKind: TMyrTokenKind): TMyrValueType;
begin
  if AKind = tkBoolean then
    Result := cvtBoolean
  else if AKind = tkInt8 then
    Result := cvtInt8
  else if AKind = tkInt16 then
    Result := cvtInt16
  else if AKind = tkInt32 then
    Result := cvtInt32
  else if AKind = tkInt64 then
    Result := cvtInt64
  else if AKind = tkUInt8 then
    Result := cvtUInt8
  else if AKind = tkUInt16 then
    Result := cvtUInt16
  else if AKind = tkUInt32 then
    Result := cvtUInt32
  else if AKind = tkUInt64 then
    Result := cvtUInt64
  else if AKind = tkFloat32 then
    Result := cvtFloat32
  else if AKind = tkFloat64 then
    Result := cvtFloat64
  else if AKind = tkChar then
    Result := cvtUInt8
  else if AKind = tkWChar then
    Result := cvtUInt16
  else if AKind = tkString then
    Result := cvtPointer
  else if AKind = tkWString then
    Result := cvtPointer
  else if AKind = tkPointer then
    Result := cvtPointer
  else
  begin
    FErrors.Add(esError, MYR_ERR_EMT_003,
      'Cannot map token kind to value type: %d', [Ord(AKind)]);
    Result := cvtVoid;
  end;
end;

function TMyrEmitter.DoMapLinkage(
  const ALinkage: Myrissa.Frontend.TMyrLinkage): Myrissa.Backend.TMyrLinkage;
begin
  case ALinkage of
    Myrissa.Frontend.lkDefault: Result := plC;
    Myrissa.Frontend.lkCLink:   Result := plC;
    Myrissa.Frontend.lkCppLink: Result := plCPP;
  else
    Result := plC;
  end;
end;

function TMyrEmitter.DoGetManagedTypeName(const ATypeExpr: TMyrASTNode): string;
begin
  Result := '';
  if ATypeExpr is TMyrTypeRefNode then
  begin
    if TMyrTypeRefNode(ATypeExpr).TokenKind = tkString then
      Result := 'string'
    else if TMyrTypeRefNode(ATypeExpr).TokenKind = tkWString then
      Result := 'wstring';
  end;
end;

procedure TMyrEmitter.DoEmitStringCleanup(const AVars: TObjectList<TMyrVarDeclNode>);
var
  LIdx: Integer;
  LVar: TMyrVarDeclNode;
begin
  for LIdx := 0 to AVars.Count - 1 do
  begin
    LVar := AVars[LIdx];
    // Only tkString is refcounted. wstring is a bare UTF-16 pointer with
    // no TStringRec header, so RT_StrRelease on one reads a garbage
    // refcount and corrupts the heap. Same gate as DoCollectStringVars.
    if (LVar.TypeExpr is TMyrTypeRefNode) and
       (TMyrTypeRefNode(LVar.TypeExpr).TokenKind = tkString) then
      FBackend.Call(RT_StrRelease, [FBackend.Get(LVar.DeclName)]);
  end;
end;

procedure TMyrEmitter.DoCollectStringVars(const AStmts: TObjectList<TMyrASTNode>;
  const ANames: TList<string>);
var
  LIdx: Integer;
  LArmIdx: Integer;
  LStmt: TMyrASTNode;
begin
  // A string var declared inside a nested block is still a slot in the same
  // stack frame, so it must be released once before the frame goes away.
  // Walking every body reaches those; a flat scan of the top level does not.
  if AStmts = nil then
    Exit;

  for LIdx := 0 to AStmts.Count - 1 do
  begin
    LStmt := AStmts[LIdx];

    if LStmt is TMyrVarDeclNode then
    begin
      // Only tkString is refcounted. wstring is a bare UTF-16 pointer with
      // no TStringRec header, so RT_StrRelease on one reads a garbage
      // refcount and corrupts the heap.
      if (TMyrVarDeclNode(LStmt).TypeExpr is TMyrTypeRefNode) and
         (TMyrTypeRefNode(TMyrVarDeclNode(LStmt).TypeExpr).TokenKind = tkString) then
        ANames.Add(TMyrVarDeclNode(LStmt).DeclName);
    end
    else if LStmt is TMyrIfNode then
    begin
      DoCollectStringVars(TMyrIfNode(LStmt).ThenBody, ANames);
      DoCollectStringVars(TMyrIfNode(LStmt).ElseBody, ANames);
    end
    else if LStmt is TMyrWhileNode then
      DoCollectStringVars(TMyrWhileNode(LStmt).Body, ANames)
    else if LStmt is TMyrForNode then
      DoCollectStringVars(TMyrForNode(LStmt).Body, ANames)
    else if LStmt is TMyrRepeatNode then
      DoCollectStringVars(TMyrRepeatNode(LStmt).Body, ANames)
    else if LStmt is TMyrMatchNode then
    begin
      for LArmIdx := 0 to TMyrMatchNode(LStmt).Arms.Count - 1 do
        DoCollectStringVars(TMyrMatchNode(LStmt).Arms[LArmIdx].Body, ANames);
      DoCollectStringVars(TMyrMatchNode(LStmt).ElseBody, ANames);
    end
    else if LStmt is TMyrGuardNode then
    begin
      DoCollectStringVars(TMyrGuardNode(LStmt).GuardBody, ANames);
      DoCollectStringVars(TMyrGuardNode(LStmt).ExceptBody, ANames);
      DoCollectStringVars(TMyrGuardNode(LStmt).FinallyBody, ANames);
    end;
  end;
end;

function TMyrEmitter.DoGetDesignatorName(const AExpr: TMyrASTNode): string;
begin
  if AExpr is TMyrIdentifierNode then
    Result := TMyrIdentifierNode(AExpr).IdentName
  else if AExpr is TMyrDotAccessNode then
    Result := TMyrDotAccessNode(AExpr).MemberName
  else
  begin
    FErrors.Add(AExpr.Location, esError, MYR_ERR_EMT_002,
      'Cannot get designator name from: %s', [AExpr.ClassName]);
    Result := '';
  end;
end;

procedure TMyrEmitter.DoEmitTypeFields(const AParentName: string;
  const AFields: TObjectList<TMyrASTNode>);
var
  I: Integer;
  LField: TMyrFieldDeclNode;
  LCompositeName: string;
  LArrayNode: TMyrArrayTypeNode;
begin
  for I := 0 to AFields.Count - 1 do
  begin
    if AFields[I] is TMyrFieldDeclNode then
    begin
      LField := TMyrFieldDeclNode(AFields[I]);
      if LField.BitWidth > 0 then
        FBackend.BitField(LField.FieldName,
          DoMapValueType(LField.TypeExpr), LField.BitWidth)
      else
      begin
        // Composite fields (record/overlay) must use the string overload
        // to preserve type identity -- DoMapValueType collapses them to
        // cvtPointer, which makes the backend treat them as primitive
        // pointers instead of embedded structs.
        // Managed primitives (string, wstring) need the same treatment for
        // the same reason: IsStringType/IsWStringType match on the type NAME,
        // so a cvtPointer field is invisible to the backend cleanup pass and
        // its contents leak. 'string' is DefinePointer('string','TStringRec')
        // and 'wstring' is DefinePointer('wstring'), so both are 8-byte
        // pointer slots -- this is layout-neutral.
        LCompositeName := DoGetCompositeTypeName(LField.TypeExpr);
        if LCompositeName = '' then
          LCompositeName := DoGetManagedTypeName(LField.TypeExpr);

        // Inline array field types (e.g. buf: array[0..3] of uint8) are
        // TMyrArrayTypeNode directly, not TMyrTypeRefNode pointing to a named
        // type. DoGetCompositeTypeName only handles TMyrTypeRefNode, so
        // without this branch the field is registered as cvtPointer (8
        // bytes) and the backend treats it as a scalar pointer instead of
        // embedded storage. This causes ekFieldAccess to load 8 bytes
        // (wrong) and ekArrayIndex to get ElementSize 0 (AV).
        if (LCompositeName = '') and (LField.TypeExpr is TMyrArrayTypeNode) then
        begin
          LArrayNode := TMyrArrayTypeNode(LField.TypeExpr);
          if not LArrayNode.IsDynamic then
          begin
            LCompositeName := '__arr_' + AParentName + '_' + LField.FieldName;
            FBackend.DefineArray(LCompositeName,
              DoMapValueType(LArrayNode.ElementType),
              LArrayNode.LowBound,
              LArrayNode.HighBound);
          end
          else
          begin
            LCompositeName := '__dynarr_' + AParentName + '_' + LField.FieldName;
            FBackend.DefineDynArray(LCompositeName,
              DoMapValueType(LArrayNode.ElementType));
          end;
        end;

        if LCompositeName <> '' then
          FBackend.Field(LField.FieldName, LCompositeName)
        else
          FBackend.Field(LField.FieldName, DoMapValueType(LField.TypeExpr));
      end;
    end
    else if AFields[I] is TMyrAnonOverlayNode then
    begin
      FBackend.BeginUnion();
      DoEmitTypeFields(AParentName, TMyrAnonOverlayNode(AFields[I]).Fields);
      FBackend.EndUnion();
    end
    else if AFields[I] is TMyrAnonRecordNode then
    begin
      FBackend.BeginRecord();
      DoEmitTypeFields(AParentName, TMyrAnonRecordNode(AFields[I]).Fields);
      FBackend.EndRecord();
    end;
  end;
end;

function TMyrEmitter.DoResolveChoicesMemberValue(
  const AChoices: TMyrChoicesTypeNode; const AMemberName: string): Int64;
var
  I: Integer;
  LMember: TMyrChoicesValueNode;
  LNextValue: Int64;
begin
  // Walk members, tracking auto-increment, return value when name matches
  LNextValue := 0;
  for I := 0 to AChoices.Members.Count - 1 do
  begin
    LMember := AChoices.Members[I];
    if (LMember.ValueExpr <> nil) and (LMember.ValueExpr is TMyrIntLiteralNode) then
      LNextValue := TMyrIntLiteralNode(LMember.ValueExpr).IntValue;
    if LMember.MemberName = AMemberName then
    begin
      Result := LNextValue;
      Exit;
    end;
    Inc(LNextValue);
  end;
  // Should not reach here if semantics validated correctly
  Result := 0;
end;

function TMyrEmitter.DoIsFloatType(const AExpr: TMyrExprNode): Boolean;
var
  LTypeDecl: TMyrTypeDeclNode;
begin
  Result := False;
  if AExpr.ResolvedType is TMyrTypeDeclNode then
  begin
    LTypeDecl := TMyrTypeDeclNode(AExpr.ResolvedType);
    Result := (LTypeDecl.PrimitiveKind = tkFloat32) or
              (LTypeDecl.PrimitiveKind = tkFloat64);
  end;
end;

function TMyrEmitter.DoIsUnsignedType(const AExpr: TMyrExprNode): Boolean;
var
  LTypeDecl: TMyrTypeDeclNode;
begin
  Result := False;
  if AExpr.ResolvedType is TMyrTypeDeclNode then
  begin
    LTypeDecl := TMyrTypeDeclNode(AExpr.ResolvedType);
    Result := (LTypeDecl.PrimitiveKind = tkUInt8) or
              (LTypeDecl.PrimitiveKind = tkUInt16) or
              (LTypeDecl.PrimitiveKind = tkUInt32) or
              (LTypeDecl.PrimitiveKind = tkUInt64);
  end;
end;

function TMyrEmitter.DoIsStringType(const AExpr: TMyrExprNode): Boolean;
begin
  Result := (AExpr.ResolvedType is TMyrTypeDeclNode) and
            (TMyrTypeDeclNode(AExpr.ResolvedType).PrimitiveKind = tkString);
end;

function TMyrEmitter.DoAssertCmpRoutine(const AExpected: TMyrExprNode; const AActual: TMyrExprNode): string;
var
  LExpr: TMyrExprNode;
  LKind: TMyrTokenKind;
begin
  // Float on either side wins: an int literal against a float result compares as float
  if DoIsFloatType(AExpected) or DoIsFloatType(AActual) then
    Exit(RT_TestAssertCmpFloat);

  // Otherwise the expected operand decides; fall back to the actual operand if untyped
  LExpr := AExpected;
  if not (LExpr.ResolvedType is TMyrTypeDeclNode) and
     not (LExpr.ResolvedType is TMyrPointerTypeNode) then
    LExpr := AActual;

  if LExpr.ResolvedType is TMyrPointerTypeNode then
    Exit(RT_TestAssertCmpPtr);

  LKind := tkUnknown;
  if LExpr.ResolvedType is TMyrTypeDeclNode then
    LKind := TMyrTypeDeclNode(LExpr.ResolvedType).PrimitiveKind;

  if LKind = tkString then
    Result := RT_TestAssertCmpStr
  else if LKind = tkWString then
    Result := RT_TestAssertCmpWStr
  else if LKind = tkBoolean then
    Result := RT_TestAssertCmpBool
  else if LKind = tkChar then
    Result := RT_TestAssertCmpChar
  else if LKind = tkWChar then
    Result := RT_TestAssertCmpWChar
  else if LKind = tkPointer then
    Result := RT_TestAssertCmpPtr
  else if DoIsUnsignedType(LExpr) then
    Result := RT_TestAssertCmpUInt
  else
    Result := RT_TestAssertCmpInt;
end;

function TMyrEmitter.DoRoutineReturnsString(const ARoutine: TMyrASTNode): Boolean;
var
  LReturn: TMyrASTNode;
begin
  LReturn := nil;
  if ARoutine is TMyrRoutineDeclNode then
    LReturn := TMyrRoutineDeclNode(ARoutine).ReturnType
  else if ARoutine is TMyrForwardRoutineDeclNode then
    LReturn := TMyrForwardRoutineDeclNode(ARoutine).ReturnType;
  Result := (LReturn is TMyrTypeRefNode) and
            (TMyrTypeRefNode(LReturn).TokenKind = tkString);
end;

// Returns the size-appropriate integer value type for a record type that
// fits in a register (<= 8 bytes, power-of-two size). Returns cvtVoid if
// the type is not a record or is too large for by-value passing.
function TMyrEmitter.DoGetSmallRecordValueType(const ATypeExpr: TMyrASTNode): TMyrValueType;
var
  LTypeRef: TMyrTypeRefNode;
  LTypeDecl: TMyrTypeDeclNode;
  LCompositeName: string;
  LSize: Integer;
begin
  Result := cvtVoid;
  LCompositeName := DoGetCompositeTypeName(ATypeExpr);
  if LCompositeName = '' then
    Exit;
  // Verify it is actually a record (not a pointer, array, etc.)
  if (ATypeExpr is TMyrTypeRefNode) then
  begin
    LTypeRef := TMyrTypeRefNode(ATypeExpr);
    if (LTypeRef.ResolvedDecl is TMyrTypeDeclNode) then
    begin
      LTypeDecl := TMyrTypeDeclNode(LTypeRef.ResolvedDecl);
      if not (LTypeDecl.TypeDef is TMyrRecordTypeNode) then
        Exit;
    end
    else
      Exit;
  end
  else
    Exit;
  // Try backend first; if the type is not yet registered (forward decl),
  // compute size from the AST record fields directly.
  if FBackend.TypeRef(LCompositeName).IsValid() then
    LSize := FBackend.GetTypeSize(FBackend.TypeRef(LCompositeName))
  else
    LSize := DoComputeRecordSize(TMyrRecordTypeNode(LTypeDecl.TypeDef));
  case LSize of
    1: Result := cvtUInt8;
    2: Result := cvtUInt16;
    4: Result := cvtUInt32;
    8: Result := cvtInt64;
  end;
end;

// Compute the size of a record from AST field types when the backend type
// is not yet registered (forward-declared records). Sums primitive field
// sizes with natural alignment padding -- matches C ABI default layout.
function TMyrEmitter.DoComputeRecordSize(const ARecordType: TMyrRecordTypeNode): Integer;
var
  LI: Integer;
  LField: TMyrFieldDeclNode;
  LFieldSize: Integer;
  LFieldAlign: Integer;
begin
  Result := 0;
  for LI := 0 to ARecordType.Fields.Count - 1 do
  begin
    if not (ARecordType.Fields[LI] is TMyrFieldDeclNode) then
      Exit(0);
    LField := TMyrFieldDeclNode(ARecordType.Fields[LI]);
    if not (LField.TypeExpr is TMyrTypeRefNode) then
      Exit(0);
    case TMyrTypeRefNode(LField.TypeExpr).TokenKind of
      tkUInt8, tkInt8, tkChar, tkBoolean: begin LFieldSize := 1; LFieldAlign := 1; end;
      tkUInt16, tkInt16, tkWChar: begin LFieldSize := 2; LFieldAlign := 2; end;
      tkUInt32, tkInt32, tkFloat32: begin LFieldSize := 4; LFieldAlign := 4; end;
      tkUInt64, tkInt64, tkFloat64: begin LFieldSize := 8; LFieldAlign := 8; end;
    else
      Exit(0);
    end;
    // C ABI natural alignment
    if not ARecordType.IsPacked then
    begin
      if (Result mod LFieldAlign) <> 0 then
        Result := Result + (LFieldAlign - (Result mod LFieldAlign));
    end;
    Result := Result + LFieldSize;
  end;
end;

function TMyrEmitter.DoRoutineParamIsSmallRecord(const ARoutine: TMyrASTNode; const AIndex: Integer): Boolean;
var
  LParams: TObjectList<TMyrParamDeclNode>;
begin
  Result := False;
  LParams := nil;
  if ARoutine is TMyrRoutineDeclNode then
    LParams := TMyrRoutineDeclNode(ARoutine).Params
  else if ARoutine is TMyrForwardRoutineDeclNode then
    LParams := TMyrForwardRoutineDeclNode(ARoutine).Params;
  if (LParams = nil) or (AIndex >= LParams.Count) then
    Exit;
  // A var param is passed by ADDRESS regardless of size; only by-value small
  // records are packed into a register. DoEmitExternRoutine already makes
  // this distinction at registration; the call site must match it.
  if LParams[AIndex].ParamMode = pmVar then
    Exit;
  Result := DoGetSmallRecordValueType(LParams[AIndex].TypeExpr) <> cvtVoid;
end;

function TMyrEmitter.DoRoutineParamIsString(const ARoutine: TMyrASTNode; const AIndex: Integer): Boolean;
var
  LParams: TObjectList<TMyrParamDeclNode>;
begin
  Result := False;
  LParams := nil;
  if ARoutine is TMyrRoutineDeclNode then
    LParams := TMyrRoutineDeclNode(ARoutine).Params
  else if ARoutine is TMyrForwardRoutineDeclNode then
    LParams := TMyrForwardRoutineDeclNode(ARoutine).Params;
  if (LParams = nil) or (AIndex >= LParams.Count) then
    Exit;
  Result := (LParams[AIndex].TypeExpr is TMyrTypeRefNode) and
            (TMyrTypeRefNode(LParams[AIndex].TypeExpr).TokenKind = tkString);
end;

// A string value the emitter itself allocated for this expression: a concat
// result or the result of a routine returning string. The consumer of such a
// value releases it right after use. Named variables are not temps.
function TMyrEmitter.DoIsStringTemp(const ANode: TMyrASTNode): Boolean;
begin
  Result := False;
  if (ANode is TMyrBinaryExprNode) and (TMyrBinaryExprNode(ANode).Op = boAdd) then
    Result := DoIsStringType(TMyrBinaryExprNode(ANode))
  else if ANode is TMyrCallExprNode then
    Result := DoRoutineReturnsString(TMyrCallExprNode(ANode).ResolvedRoutine);
end;

procedure TMyrEmitter.DoReleaseStringTemp(const ANode: TMyrASTNode; const AExpr: TMyrIRExpr);
begin
  if DoIsStringTemp(ANode) then
    FBackend.Call(RT_StrRelease, [AExpr]);
end;

function TMyrEmitter.DoNewStringTemp(const AValue: TMyrIRExpr): TMyrIRExpr;
var
  LName: string;
begin
  Inc(FStrTempSeq);
  LName := '_strtmp_' + IntToStr(FStrTempSeq);
  FBackend.Let(LName, AValue);
  Result := FBackend.Get(LName);
end;

function TMyrEmitter.DoIsWStringType(const AExpr: TMyrExprNode): Boolean;
begin
  Result := (AExpr.ResolvedType is TMyrTypeDeclNode) and
            (TMyrTypeDeclNode(AExpr.ResolvedType).PrimitiveKind = tkWString);
end;

function TMyrEmitter.DoIsSetType(const AExpr: TMyrExprNode): Boolean;
begin
  // Check ResolvedType directly (works for comparisons where type is preserved)
  if AExpr.ResolvedType is TMyrTypeDeclNode then
    Result := (TMyrTypeDeclNode(AExpr.ResolvedType).TypeDef <> nil) and
              (TMyrTypeDeclNode(AExpr.ResolvedType).TypeDef is TMyrSetTypeNode)
  else if AExpr.ResolvedType is TMyrSetTypeNode then
    Result := True
  // Fallback: check the declaration's type (semantics promotes set to int for arithmetic)
  else if (AExpr is TMyrIdentifierNode) and
          (TMyrIdentifierNode(AExpr).ResolvedDecl is TMyrVarDeclNode) and
          (TMyrVarDeclNode(TMyrIdentifierNode(AExpr).ResolvedDecl).TypeExpr is TMyrSetTypeNode) then
    Result := True
  else
    Result := False;
end;

function TMyrEmitter.DoGetCompositeTypeName(const ATypeExpr: TMyrASTNode): string;
var
  LTypeDecl: TMyrTypeDeclNode;
begin
  Result := '';
  if (ATypeExpr is TMyrTypeRefNode) and
     (TMyrTypeRefNode(ATypeExpr).ResolvedDecl is TMyrTypeDeclNode) then
  begin
    LTypeDecl := TMyrTypeDeclNode(TMyrTypeRefNode(ATypeExpr).ResolvedDecl);
    if (LTypeDecl.TypeDef is TMyrRecordTypeNode) or
       (LTypeDecl.TypeDef is TMyrOverlayTypeNode) or
       (LTypeDecl.TypeDef is TMyrArrayTypeNode) then
      Result := LTypeDecl.DeclName;
  end;
end;

// Returns True when the printf conversion specifier that consumes value
// argument AValueIndex expects a double. AValueIndex is 0-based and counts
// only the arguments that follow the format string.
// '%%' is a literal percent and consumes nothing. A '*' width or precision
// consumes an integer argument of its own, so it advances the position count
// without ever being a float position itself.
function TMyrEmitter.DoFormatArgIsFloat(const AFormat: string;
  const AValueIndex: Integer): Boolean;
var
  LPos: Integer;
  LLen: Integer;
  LIndex: Integer;
  LConv: Char;
begin
  Result := False;
  LLen := Length(AFormat);
  LPos := 1;
  LIndex := 0;

  while LPos <= LLen do
  begin
    if AFormat[LPos] <> '%' then
    begin
      Inc(LPos);
      Continue;
    end;

    Inc(LPos);
    if LPos > LLen then
      Exit;

    if AFormat[LPos] = '%' then
    begin
      Inc(LPos);
      Continue;
    end;

    // Flags
    while (LPos <= LLen) and
          CharInSet(AFormat[LPos], ['-', '+', ' ', '#', '0']) do
      Inc(LPos);

    // Width
    if (LPos <= LLen) and (AFormat[LPos] = '*') then
    begin
      if LIndex = AValueIndex then
        Exit(False);
      Inc(LIndex);
      Inc(LPos);
    end
    else
      while (LPos <= LLen) and CharInSet(AFormat[LPos], ['0'..'9']) do
        Inc(LPos);

    // Precision
    if (LPos <= LLen) and (AFormat[LPos] = '.') then
    begin
      Inc(LPos);
      if (LPos <= LLen) and (AFormat[LPos] = '*') then
      begin
        if LIndex = AValueIndex then
          Exit(False);
        Inc(LIndex);
        Inc(LPos);
      end
      else
        while (LPos <= LLen) and CharInSet(AFormat[LPos], ['0'..'9']) do
          Inc(LPos);
    end;

    // Length modifiers
    while (LPos <= LLen) and
          CharInSet(AFormat[LPos], ['h', 'l', 'L', 'z', 'j', 't']) do
      Inc(LPos);

    if LPos > LLen then
      Exit;

    LConv := AFormat[LPos];
    Inc(LPos);

    if LIndex = AValueIndex then
    begin
      Result := CharInSet(LConv, ['e', 'E', 'f', 'F', 'g', 'G', 'a', 'A']);
      Exit;
    end;

    Inc(LIndex);
  end;
end;

// True only when the format string is a literal AND the specifier consuming
// value argument AValueIndex expects a double. A non-literal format string
// cannot be inspected at compile time, so it answers False and the caller
// keeps the existing truncating behaviour rather than silently changing a
// path that cannot be verified.
function TMyrEmitter.DoFormatWantsFloatArg(const ANode: TMyrPrintNode;
  const AValueIndex: Integer): Boolean;
begin
  Result := False;

  if ANode.Args.Count = 0 then
    Exit;

  if not (ANode.Args[0] is TMyrStringLiteralNode) then
    Exit;

  Result := DoFormatArgIsFloat(
    TMyrStringLiteralNode(ANode.Args[0]).StringValue, AValueIndex);
end;

function TMyrEmitter.DoEvalConstExpr(const AExpr: TMyrASTNode; out AIntVal: Int64): Boolean;
var
  LLeft: Int64;
  LRight: Int64;
  LBinNode: TMyrBinaryExprNode;
  LUnaryNode: TMyrUnaryExprNode;
  LIdentNode: TMyrIdentifierNode;
  LChoices: TMyrChoicesTypeNode;
  LDot: TMyrDotAccessNode;
  LTypeDecl: TMyrTypeDeclNode;
begin
  Result := False;
  AIntVal := 0;

  if AExpr is TMyrIntLiteralNode then
  begin
    AIntVal := TMyrIntLiteralNode(AExpr).IntValue;
    Result := True;
  end
  else if AExpr is TMyrBoolLiteralNode then
  begin
    if TMyrBoolLiteralNode(AExpr).BoolValue then
      AIntVal := 1
    else
      AIntVal := 0;
    Result := True;
  end
  else if AExpr is TMyrUnaryExprNode then
  begin
    LUnaryNode := TMyrUnaryExprNode(AExpr);
    if DoEvalConstExpr(LUnaryNode.Operand, LLeft) then
    begin
      case LUnaryNode.Op of
        uoNegate: begin AIntVal := -LLeft; Result := True; end;
        uoPositive: begin AIntVal := LLeft; Result := True; end;
        uoNot: begin AIntVal := not LLeft; Result := True; end;
      end;
    end;
  end
  else if AExpr is TMyrBinaryExprNode then
  begin
    LBinNode := TMyrBinaryExprNode(AExpr);
    if DoEvalConstExpr(LBinNode.Left, LLeft) and
       DoEvalConstExpr(LBinNode.Right, LRight) then
    begin
      Result := True;
      case LBinNode.Op of
        boAdd:    AIntVal := LLeft + LRight;
        boSub:    AIntVal := LLeft - LRight;
        boMul:    AIntVal := LLeft * LRight;
        boIntDiv: if LRight <> 0 then AIntVal := LLeft div LRight else Result := False;
        boMod:    if LRight <> 0 then AIntVal := LLeft mod LRight else Result := False;
        boAnd:    AIntVal := LLeft and LRight;
        boOr:     AIntVal := LLeft or LRight;
        boXor:    AIntVal := LLeft xor LRight;
        boShl:    AIntVal := LLeft shl LRight;
        boShr:    AIntVal := LLeft shr LRight;
      else
        Result := False;
      end;
    end;
  end
  else if AExpr is TMyrIdentifierNode then
  begin
    // Resolve through AST: identifier -> ResolvedDecl -> const value
    LIdentNode := TMyrIdentifierNode(AExpr);
    if LIdentNode.ResolvedDecl is TMyrConstDeclNode then
      Result := DoEvalConstExpr(TMyrConstDeclNode(LIdentNode.ResolvedDecl).ValueExpr, AIntVal);
  end
  else if AExpr is TMyrDotAccessNode then
  begin
    // Choices member reference: walk AST to get value
    LDot := TMyrDotAccessNode(AExpr);
    if (LDot.AccessKind = dakChoices) and (LDot.ResolvedType is TMyrTypeDeclNode) then
    begin
      LTypeDecl := TMyrTypeDeclNode(LDot.ResolvedType);
      if LTypeDecl.TypeDef is TMyrChoicesTypeNode then
      begin
        LChoices := TMyrChoicesTypeNode(LTypeDecl.TypeDef);
        AIntVal := DoResolveChoicesMemberValue(LChoices, LDot.MemberName);
        Result := True;
      end;
    end;
  end;
end;

end.
