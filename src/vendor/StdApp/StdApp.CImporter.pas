{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.CImporter - C Header to Delphi Unit Converter

  Converts C headers into Delphi unit source code. Uses libtcc (via
  StdApp.LibTCC) for preprocessing -- expanding macros and includes --
  then parses the result to generate Delphi declarations. Configuration
  is loaded/saved via JSON (StdApp.JSON). Resource compilation for
  static binding mode uses TResourceCompiler (StdApp.ResCompiler).

  Key types:
  - TCImporter: Main importer class -- LoadFromConfig, Process,
    SaveToConfig, with support for include paths, type exclusions,
    function renames, insertions, replacements, and multiple binding
    modes (static, dynamic, delayed, custom, VPK)
  - TCLexer: C token lexer for preprocessed output

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.JSON,
    StdApp.ResCompiler, StdApp.LibTCC
===============================================================================}

unit StdApp.CImporter;

{$I StdApp.Defines.inc}

interface

uses
  WinApi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Console,
  StdApp.JSON,
  StdApp.ResCompiler,
  StdApp.LibTCC;

type
  { TCTokenKind }
  TCTokenKind = (
    ctkEOF,
    ctkError,
    ctkIdentifier,
    ctkIntLiteral,
    ctkFloatLiteral,
    ctkStringLiteral,
    ctkTypedef,
    ctkStruct,
    ctkUnion,
    ctkEnum,
    ctkConst,
    ctkVoid,
    ctkChar,
    ctkShort,
    ctkInt,
    ctkLong,
    ctkFloat,
    ctkDouble,
    ctkSigned,
    ctkUnsigned,
    ctkBool,
    ctkExtern,
    ctkStatic,
    ctkInline,
    ctkRestrict,
    ctkVolatile,
    ctkAtomic,
    ctkBuiltin,
    ctkLBrace,
    ctkRBrace,
    ctkLParen,
    ctkRParen,
    ctkLBracket,
    ctkRBracket,
    ctkSemicolon,
    ctkComma,
    ctkStar,
    ctkEquals,
    ctkColon,
    ctkEllipsis,
    ctkDot,
    ctkHash,
    ctkLShift,
    ctkBitOr,
    ctkBitNot,
    ctkLineMarker
  );

  { TCToken }
  TCToken = record
    Kind: TCTokenKind;
    Lexeme: string;
    IntValue: Int64;
    FloatValue: Double;
    Line: Integer;
    Column: Integer;
  end;

  { TCLexer }
  TCLexer = class(TBaseObject)
  private
    FSource: string;
    FPos: Integer;
    FLine: Integer;
    FColumn: Integer;
    FTokens: TList<TCToken>;
    FCurrentChar: Char;

    procedure Advance();
    {$HINTS OFF}
    function Peek(): Char;
    {$HINTS ON}
    function PeekNext(): Char;
    procedure SkipWhitespace();
    procedure SkipLineComment();
    procedure SkipBlockComment();
    function ScanLineMarker(): TCToken;
    function IsAlpha(const AChar: Char): Boolean;
    function IsDigit(const AChar: Char): Boolean;
    function IsAlphaNumeric(const AChar: Char): Boolean;
    function IsHexDigit(const AChar: Char): Boolean;
    function ScanIdentifier(): TCToken;
    function ScanNumber(): TCToken;
    function ScanString(): TCToken;
    function MakeToken(const AKind: TCTokenKind): TCToken;
    function GetKeywordKind(const AIdent: string): TCTokenKind;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure Tokenize(const ASource: string);
    function GetTokenCount(): Integer;
    function GetToken(const AIndex: Integer): TCToken;
    procedure Clear();
  end;

  { TCFieldInfo }
  TCFieldInfo = record
    FieldName: string;
    TypeName: string;
    IsPointer: Boolean;
    PointerDepth: Integer;
    ArraySize: Integer;
    BitWidth: Integer;
  end;

  { TCStructInfo }
  TCStructInfo = record
    StructName: string;
    IsUnion: Boolean;
    Fields: TArray<TCFieldInfo>;
  end;

  { TCEnumValue }
  TCEnumValue = record
    ValueName: string;
    Value: Int64;
    HasExplicitValue: Boolean;
  end;

  { TCEnumInfo }
  TCEnumInfo = record
    EnumName: string;
    Values: TArray<TCEnumValue>;
  end;

  { TCDefineInfo }
  TCDefineInfo = record
    DefineName: string;
    DefineValue: string;
    IsInteger: Boolean;
    IntValue: Int64;
    IsFloat: Boolean;
    FloatValue: Double;
    IsString: Boolean;
    StringValue: string;
    IsTypedConstant: Boolean;
    TypedConstType: string;
    TypedConstValues: string;
  end;

  { TCParamInfo }
  TCParamInfo = record
    ParamName: string;
    TypeName: string;
    IsPointer: Boolean;
    PointerDepth: Integer;
    IsConst: Boolean;
    IsConstTarget: Boolean;
  end;

  { TCFunctionInfo }
  TCFunctionInfo = record
    FuncName: string;
    ReturnType: string;
    ReturnIsPointer: Boolean;
    ReturnPointerDepth: Integer;
    Params: TArray<TCParamInfo>;
    IsVariadic: Boolean;
    SourceFile: string;
  end;

  { TCTypedefInfo }
  TCTypedefInfo = record
    AliasName: string;
    TargetType: string;
    IsPointer: Boolean;
    PointerDepth: Integer;
    IsFunctionPointer: Boolean;
    FuncInfo: TCFunctionInfo;
  end;

  { TBindingMode }
  TBindingMode = (
    bmStatic,           // DLL embedded as RCDATA, loaded via StdApp.DllLoader memory loader
    bmDynamic,          // Traditional external linking: external CDllName
    bmDynamicDelayed,   // Delayed external linking: external CDllName delayed
    bmDynamicCustom,    // Exposes BindExports(AHandle)/UnbindExports for manual handle management
    bmStaticVpk         // Exposes BindExports(AVFS, AFilename)/UnbindExports for StdApp VPK loading
  );

  { TInsertionInfo }
  TInsertionInfo = record
    TargetLine: string;
    Content: string;
    InsertBefore: Boolean;
    Occurrence: Integer;
  end;

  { TReplacementInfo }
  TReplacementInfo = record
    OldText: string;
    NewText: string;
    Occurrence: Integer;
  end;

  { TDllMapEntry }
  TDllMapEntry = record
    Path: string;
    DllName: string;
    DllPath: string;
    ResName: string;
  end;

  { TDepDllInfo }
  TDepDllInfo = record
    DllName: string;
    DllPath: string;
    ResName: string;
  end;

  { TCImporter }
  TCImporter = class(TBaseObject)
  private
    FLexer: TCLexer;
    FPos: Integer;
    FCurrentToken: TCToken;
    FModuleName: string;
    FDllName: string;
    FDllPath: string;
    FResName: string;
    FOutput: TStringBuilder;
    FIndent: Integer;
    FIncludePaths: TList<string>;
    FSourcePaths: TList<string>;
    FExcludedTypes: TList<string>;
    FExcludedFunctions: TList<string>;
    FFunctionRenames: TDictionary<string, string>;
    FUsesUnits: TList<string>;
    FSavePreprocessed: Boolean;
    FOutputPath: string;
    FHeader: string;
    FLastError: string;

    FStructs: TList<TCStructInfo>;
    FEnums: TList<TCEnumInfo>;
    FTypedefs: TList<TCTypedefInfo>;
    FDefines: TList<TCDefineInfo>;
    FFunctions: TList<TCFunctionInfo>;
    FForwardDecls: TList<string>;
    FInsertions: TList<TInsertionInfo>;
    FReplacements: TList<TReplacementInfo>;
    FCurrentSourceFile: string;
    FBindingMode: TBindingMode;
    FDllNameMap: TList<TDllMapEntry>;
    FFuncDllMap: TDictionary<string, string>;
    FDepDlls: TList<TDepDllInfo>;
    FUserDefines: TDictionary<string, string>;
    FUserUndefines: TList<string>;

    function PreprocessHeader(const AHeaderFile: string; out APreprocessedSource: string): Boolean;

    function IsAtEnd(): Boolean;
    function PeekNext(): TCToken;
    procedure Advance();
    function Check(const AKind: TCTokenKind): Boolean;
    function Match(const AKind: TCTokenKind): Boolean;
    function MatchAny(const AKinds: array of TCTokenKind): Boolean;

    procedure SkipToSemicolon();
    procedure SkipToRBrace();
    procedure SkipAttribute();
    function IsTypeKeyword(): Boolean;
    function ParseBaseType(): string;
    function ParsePointerDepth(): Integer;

    procedure ParseTopLevel();
    procedure ParseTypedef();
    procedure ParseFuncPtrTypedef(const AReturnType: string; const AReturnPtrDepth: Integer);
    procedure ParseStruct(const AIsUnion: Boolean; out AInfo: TCStructInfo);
    procedure ParseEnum(out AInfo: TCEnumInfo);
    procedure ParseFunction(const AReturnType: string; const AReturnPtrDepth: Integer; const AFuncName: string);
    procedure ParseStructField(const AStruct: TCStructInfo; var AFields: TArray<TCFieldInfo>);
    function ParseEnumExpression(out AValue: Int64): Boolean;

    procedure EmitLn(const AText: string = '');
    procedure EmitFmt(const AFormat: string; const AArgs: array of const);
    function MapCTypeToDelphi(const ACType: string; const AIsPointer: Boolean; const APtrDepth: Integer; const AIsConstTarget: Boolean = False): string;
    function ResolveTypedefAlias(const ATypeName: string): string;
    function ResolveConstantValue(const AName: string; out AValue: Int64): Boolean;
    function SanitizeIdentifier(const AName: string): string;
    function IsAllowedSourceFile(): Boolean;
    function HasStructDefinition(const AName: string): Boolean;
    function HasTypeNameCollision(const AName: string): Boolean;
    function TypedefReferencesExcludedType(const ATypedef: TCTypedefInfo): Boolean;
    function FunctionReferencesExcludedType(const AFunc: TCFunctionInfo): Boolean;
    function GetDelphiFuncName(const AFuncName: string): string;
    procedure GenerateModule();
    procedure GenerateForwardDecls();
    procedure GenerateAllTypes();
    procedure GenerateFunctions();
    procedure GenerateSimpleConstants();
    procedure GenerateTypedConstants();
    procedure GenerateBindExports();
    procedure GenerateUnbindExports();
    function BindingModeFromString(const AValue: string): TBindingMode;
    procedure GenerateModuleStatic();
    procedure GenerateModuleDynamic();
    procedure GenerateModuleDynamicDelayed();
    procedure GenerateModuleDynamicCustom();
    procedure GenerateModuleStaticVpk();
    procedure GenerateInterfaceCommon();
    procedure GenerateFunctionsExternal(const ADelayed: Boolean);
    procedure GenerateDlmBindExportsCustom();
    procedure GenerateDlmUnbindExportsCustom();
    procedure GenerateDlmBindExportsVpk();
    procedure GenerateDlmUnbindExportsVpk();
    function GenerateResName(): string;
    procedure ProcessInsertions();
    function GetDllNameForFunction(const AFunc: TCFunctionInfo): string;
    function DllNameToIdentifier(const ADllName: string): string;

    procedure ParseDefines(const APreprocessedSource: string);
    procedure ParsePreprocessed(const APreprocessedSource: string);

  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure AddIncludePath(const APath: string; const AModuleName: string = '');
    procedure AddSourcePath(const APath: string);
    procedure AddExcludedType(const ATypeName: string);
    procedure AddExcludedFunction(const AFuncName: string);
    procedure AddFunctionRename(const AOriginalName: string; const ADelphiName: string);
    procedure AddUsesUnit(const AUnitName: string);
    procedure SetSavePreprocessed(const AValue: Boolean);
    procedure InsertTextAfter(const ATargetLine: string; const AText: string; const AOccurrence: Integer = 1);
    procedure InsertFileAfter(const ATargetLine: string; const AFilePath: string; const AOccurrence: Integer = 1);
    procedure InsertTextBefore(const ATargetLine: string; const AText: string; const AOccurrence: Integer = 1);
    procedure InsertFileBefore(const ATargetLine: string; const AFilePath: string; const AOccurrence: Integer = 1);
    procedure ReplaceText(const AOldText: string; const ANewText: string; const AOccurrence: Integer = 0);
    procedure SetOutputPath(const APath: string);
    procedure SetHeader(const AFilename: string);
    function Process(): Boolean;
    procedure SetModuleName(const AName: string);
    procedure SetDllName(const ADllName: string);
    procedure SetDllPath(const ADllPath: string);
    procedure SetBindingMode(const AMode: TBindingMode);
    procedure AddDllNameMap(const APath, ADllName, ADllPath: string);
    procedure AddFunctionDllMap(const AFuncName, ADllName, ADllPath: string);
    procedure AddDepDll(const ADllName, ADllPath: string);
    procedure AddDefine(const AName: string; const AValue: string = '');
    procedure AddUndefine(const AName: string);
    function LoadFromConfig(const AFilename: string): Boolean;
    function SaveToConfig(const AFilename: string): Boolean;
    function GetLastError(): string;
    procedure Clear();
  end;

implementation

{ TDlmCLexer }

constructor TCLexer.Create();
begin
  inherited;
  FTokens := TList<TCToken>.Create();
  Clear();
end;

destructor TCLexer.Destroy();
begin
  FTokens.Free();
  inherited;
end;

procedure TCLexer.Advance();
begin
  if FPos <= Length(FSource) then
  begin
    if FCurrentChar = #10 then
    begin
      Inc(FLine);
      FColumn := 1;
    end
    else
      Inc(FColumn);
    Inc(FPos);
  end;

  if FPos <= Length(FSource) then
    FCurrentChar := FSource[FPos]
  else
    FCurrentChar := #0;
end;

function TCLexer.Peek(): Char;
begin
  Result := FCurrentChar;
end;

function TCLexer.PeekNext(): Char;
begin
  if FPos + 1 <= Length(FSource) then
    Result := FSource[FPos + 1]
  else
    Result := #0;
end;

procedure TCLexer.SkipWhitespace();
begin
  while (FCurrentChar <> #0) and (FCurrentChar <= ' ') do
    Advance();
end;

procedure TCLexer.SkipLineComment();
begin
  while (FCurrentChar <> #0) and (FCurrentChar <> #10) do
    Advance();
end;

procedure TCLexer.SkipBlockComment();
begin
  Advance();
  while FCurrentChar <> #0 do
  begin
    if (FCurrentChar = '*') and (PeekNext() = '/') then
    begin
      Advance();
      Advance();
      Exit;
    end;
    Advance();
  end;
end;

function TCLexer.ScanLineMarker(): TCToken;
var
  LFilename: string;
  LKeyword: string;
begin
  Result.Kind := ctkLineMarker;
  Result.Lexeme := '';
  Result.IntValue := 0;
  Result.FloatValue := 0;
  Result.Line := FLine;
  Result.Column := FColumn;

  // Skip the '#'
  Advance();
  SkipWhitespace();

  // Check if this is a #define directive (skip it, parsed separately)
  if IsAlpha(FCurrentChar) then
  begin
    LKeyword := '';
    while IsAlphaNumeric(FCurrentChar) do
    begin
      LKeyword := LKeyword + FCurrentChar;
      Advance();
    end;
    // Skip rest of line for #define, #undef, etc.
    while (FCurrentChar <> #0) and (FCurrentChar <> #10) do
      Advance();
    // Return empty line marker (will be ignored)
    Result.Lexeme := '';
    Exit;
  end;

  // Skip line number
  while IsDigit(FCurrentChar) do
    Advance();
  SkipWhitespace();

  // Parse filename in quotes
  if FCurrentChar = '"' then
  begin
    Advance(); // skip opening quote
    LFilename := '';
    while (FCurrentChar <> #0) and (FCurrentChar <> '"') and (FCurrentChar <> #10) do
    begin
      LFilename := LFilename + FCurrentChar;
      Advance();
    end;
    if FCurrentChar = '"' then
      Advance(); // skip closing quote
    Result.Lexeme := LFilename;
  end;

  // Skip rest of line (flags)
  while (FCurrentChar <> #0) and (FCurrentChar <> #10) do
    Advance();
end;

function TCLexer.IsAlpha(const AChar: Char): Boolean;
begin
  Result := ((AChar >= 'a') and (AChar <= 'z')) or
            ((AChar >= 'A') and (AChar <= 'Z')) or
            (AChar = '_');
end;

function TCLexer.IsDigit(const AChar: Char): Boolean;
begin
  Result := (AChar >= '0') and (AChar <= '9');
end;

function TCLexer.IsAlphaNumeric(const AChar: Char): Boolean;
begin
  Result := IsAlpha(AChar) or IsDigit(AChar);
end;

function TCLexer.IsHexDigit(const AChar: Char): Boolean;
begin
  Result := IsDigit(AChar) or
            ((AChar >= 'a') and (AChar <= 'f')) or
            ((AChar >= 'A') and (AChar <= 'F'));
end;

function TCLexer.GetKeywordKind(const AIdent: string): TCTokenKind;
begin
  if AIdent = 'typedef' then Result := ctkTypedef
  else if AIdent = 'struct' then Result := ctkStruct
  else if AIdent = 'union' then Result := ctkUnion
  else if AIdent = 'enum' then Result := ctkEnum
  else if AIdent = 'const' then Result := ctkConst
  else if AIdent = 'void' then Result := ctkVoid
  else if AIdent = 'char' then Result := ctkChar
  else if AIdent = 'short' then Result := ctkShort
  else if AIdent = 'int' then Result := ctkInt
  else if AIdent = 'long' then Result := ctkLong
  else if AIdent = 'float' then Result := ctkFloat
  else if AIdent = 'double' then Result := ctkDouble
  else if AIdent = 'signed' then Result := ctkSigned
  else if AIdent = 'unsigned' then Result := ctkUnsigned
  else if AIdent = '_Bool' then Result := ctkBool
  else if AIdent = 'extern' then Result := ctkExtern
  else if AIdent = 'static' then Result := ctkStatic
  else if AIdent = 'inline' then Result := ctkInline
  else if AIdent = '__inline' then Result := ctkInline
  else if AIdent = '__inline__' then Result := ctkInline
  else if AIdent = 'restrict' then Result := ctkRestrict
  else if AIdent = '__restrict' then Result := ctkRestrict
  else if AIdent = '__restrict__' then Result := ctkRestrict
  else if AIdent = 'volatile' then Result := ctkVolatile
  else if AIdent = '_Atomic' then Result := ctkAtomic
  else if AIdent.StartsWith('__builtin') then Result := ctkBuiltin
  else if AIdent.StartsWith('__attribute') then Result := ctkBuiltin
  else if AIdent.StartsWith('__declspec') then Result := ctkBuiltin
  else Result := ctkIdentifier;
end;

function TCLexer.ScanIdentifier(): TCToken;
var
  LStart: Integer;
  LIdent: string;
begin
  LStart := FPos;
  while IsAlphaNumeric(FCurrentChar) do
    Advance();
  LIdent := Copy(FSource, LStart, FPos - LStart);
  Result.Kind := GetKeywordKind(LIdent);
  Result.Lexeme := LIdent;
  Result.IntValue := 0;
  Result.FloatValue := 0;
  Result.Line := FLine;
  Result.Column := FColumn - Length(LIdent);
end;

function TCLexer.ScanNumber(): TCToken;
var
  LStart: Integer;
  LNumStr: string;
  LIsHex: Boolean;
  LIsFloat: Boolean;
begin
  LStart := FPos;
  LIsHex := False;
  LIsFloat := False;

  if (FCurrentChar = '0') and ((PeekNext() = 'x') or (PeekNext() = 'X')) then
  begin
    LIsHex := True;
    Advance();
    Advance();
    while IsHexDigit(FCurrentChar) do
      Advance();
  end
  else
  begin
    while IsDigit(FCurrentChar) do
      Advance();
    if (FCurrentChar = '.') and IsDigit(PeekNext()) then
    begin
      LIsFloat := True;
      Advance();
      while IsDigit(FCurrentChar) do
        Advance();
    end;
    if (FCurrentChar = 'e') or (FCurrentChar = 'E') then
    begin
      LIsFloat := True;
      Advance();
      if (FCurrentChar = '+') or (FCurrentChar = '-') then
        Advance();
      while IsDigit(FCurrentChar) do
        Advance();
    end;
  end;

  while CharInSet(FCurrentChar, ['u', 'U', 'l', 'L', 'f', 'F']) do
    Advance();

  LNumStr := Copy(FSource, LStart, FPos - LStart);

  if LIsFloat then
  begin
    Result.Kind := ctkFloatLiteral;
    Result.FloatValue := StrToFloatDef(LNumStr, 0);
    Result.IntValue := 0;
  end
  else
  begin
    Result.Kind := ctkIntLiteral;
    // Strip suffixes (U, L, LL, ULL, etc.) before parsing
    while (Length(LNumStr) > 0) and CharInSet(LNumStr[Length(LNumStr)], ['u', 'U', 'l', 'L']) do
      LNumStr := Copy(LNumStr, 1, Length(LNumStr) - 1);
    if LIsHex then
      Result.IntValue := StrToInt64Def('$' + Copy(LNumStr, 3, Length(LNumStr)), 0)
    else
      Result.IntValue := StrToInt64Def(LNumStr, 0);
    Result.FloatValue := 0;
  end;
  Result.Lexeme := LNumStr;
  Result.Line := FLine;
  Result.Column := FColumn - Length(LNumStr);
end;

function TCLexer.ScanString(): TCToken;
var
  LStart: Integer;
  LQuote: Char;
begin
  LQuote := FCurrentChar;
  LStart := FPos;
  Advance();
  while (FCurrentChar <> #0) and (FCurrentChar <> LQuote) do
  begin
    if FCurrentChar = '\' then
      Advance();
    Advance();
  end;
  if FCurrentChar = LQuote then
    Advance();
  Result.Kind := ctkStringLiteral;
  Result.Lexeme := Copy(FSource, LStart, FPos - LStart);
  Result.IntValue := 0;
  Result.FloatValue := 0;
  Result.Line := FLine;
  Result.Column := FColumn - Length(Result.Lexeme);
end;

function TCLexer.MakeToken(const AKind: TCTokenKind): TCToken;
begin
  Result.Kind := AKind;
  Result.Lexeme := FCurrentChar;
  Result.IntValue := 0;
  Result.FloatValue := 0;
  Result.Line := FLine;
  Result.Column := FColumn;
  Advance();
end;

procedure TCLexer.Tokenize(const ASource: string);
var
  LToken: TCToken;
begin
  Clear();
  FSource := ASource;
  FPos := 1;
  FLine := 1;
  FColumn := 1;
  if Length(FSource) > 0 then
    FCurrentChar := FSource[1]
  else
    FCurrentChar := #0;

  while FCurrentChar <> #0 do
  begin
    SkipWhitespace();
    if FCurrentChar = #0 then
      Break;

    if (FCurrentChar = '#') and (FColumn = 1) then
    begin
      LToken := ScanLineMarker();
      FTokens.Add(LToken);
      Continue;
    end;

    if (FCurrentChar = '/') and (PeekNext() = '/') then
    begin
      SkipLineComment();
      Continue;
    end;

    if (FCurrentChar = '/') and (PeekNext() = '*') then
    begin
      Advance();
      SkipBlockComment();
      Continue;
    end;

    if IsAlpha(FCurrentChar) then
    begin
      LToken := ScanIdentifier();
      FTokens.Add(LToken);
      Continue;
    end;

    if IsDigit(FCurrentChar) then
    begin
      LToken := ScanNumber();
      FTokens.Add(LToken);
      Continue;
    end;

    // Handle negative number literals (e.g., -1 in enum values)
    if (FCurrentChar = '-') and IsDigit(PeekNext()) then
    begin
      Advance(); // consume '-'
      LToken := ScanNumber();
      LToken.IntValue := -LToken.IntValue;
      LToken.FloatValue := -LToken.FloatValue;
      LToken.Lexeme := '-' + LToken.Lexeme;
      FTokens.Add(LToken);
      Continue;
    end;

    if (FCurrentChar = '"') or (FCurrentChar = '''') then
    begin
      LToken := ScanString();
      FTokens.Add(LToken);
      Continue;
    end;

    case FCurrentChar of
      '{': FTokens.Add(MakeToken(ctkLBrace));
      '}': FTokens.Add(MakeToken(ctkRBrace));
      '(': FTokens.Add(MakeToken(ctkLParen));
      ')': FTokens.Add(MakeToken(ctkRParen));
      '[': FTokens.Add(MakeToken(ctkLBracket));
      ']': FTokens.Add(MakeToken(ctkRBracket));
      ';': FTokens.Add(MakeToken(ctkSemicolon));
      ',': FTokens.Add(MakeToken(ctkComma));
      '*': FTokens.Add(MakeToken(ctkStar));
      '=': FTokens.Add(MakeToken(ctkEquals));
      ':': FTokens.Add(MakeToken(ctkColon));
      '#': FTokens.Add(MakeToken(ctkHash));
      '.':
        begin
          if PeekNext() = '.' then
          begin
            Advance();
            Advance();
            if FCurrentChar = '.' then
            begin
              LToken.Kind := ctkEllipsis;
              LToken.Lexeme := '...';
              LToken.Line := FLine;
              LToken.Column := FColumn - 2;
              Advance();
              FTokens.Add(LToken);
            end;
          end
          else
            FTokens.Add(MakeToken(ctkDot));
        end;
      '<':
        begin
          if PeekNext() = '<' then
          begin
            LToken := MakeToken(ctkLShift);
            LToken.Lexeme := '<<';
            Advance();
            FTokens.Add(LToken);
          end
          else
            Advance();
        end;
      '|': FTokens.Add(MakeToken(ctkBitOr));
      '~': FTokens.Add(MakeToken(ctkBitNot));
    else
      Advance();
    end;
  end;

  LToken.Kind := ctkEOF;
  LToken.Lexeme := '';
  LToken.IntValue := 0;
  LToken.FloatValue := 0;
  LToken.Line := FLine;
  LToken.Column := FColumn;
  FTokens.Add(LToken);
end;

function TCLexer.GetTokenCount(): Integer;
begin
  Result := FTokens.Count;
end;

function TCLexer.GetToken(const AIndex: Integer): TCToken;
begin
  if (AIndex >= 0) and (AIndex < FTokens.Count) then
    Result := FTokens[AIndex]
  else
  begin
    Result.Kind := ctkEOF;
    Result.Lexeme := '';
  end;
end;

procedure TCLexer.Clear();
begin
  FTokens.Clear();
  FSource := '';
  FPos := 1;
  FLine := 1;
  FColumn := 1;
  FCurrentChar := #0;
end;

{ TDlmCImporter }

constructor TCImporter.Create();
begin
  inherited;
  FLexer := TCLexer.Create();
  FOutput := TStringBuilder.Create();
  FStructs := TList<TCStructInfo>.Create();
  FEnums := TList<TCEnumInfo>.Create();
  FTypedefs := TList<TCTypedefInfo>.Create();
  FDefines := TList<TCDefineInfo>.Create();
  FFunctions := TList<TCFunctionInfo>.Create();
  FForwardDecls := TList<string>.Create();
  FInsertions := TList<TInsertionInfo>.Create();
  FReplacements := TList<TReplacementInfo>.Create();
  FIncludePaths := TList<string>.Create();
  FSourcePaths := TList<string>.Create();
  FExcludedTypes := TList<string>.Create();
  FExcludedFunctions := TList<string>.Create();
  FFunctionRenames := TDictionary<string, string>.Create();
  FUsesUnits := TList<string>.Create();
  FDllNameMap := TList<TDllMapEntry>.Create();
  FFuncDllMap := TDictionary<string, string>.Create();
  FDepDlls := TList<TDepDllInfo>.Create();
  FUserDefines := TDictionary<string, string>.Create();
  FUserUndefines := TList<string>.Create();
  FSavePreprocessed := False;
  FModuleName := '';
  FDllName := '';
  FOutputPath := '';
  FHeader := '';
  FLastError := '';
  FCurrentSourceFile := '';
  FBindingMode := bmStatic;
  FIndent := 0;
  FPos := 0;

  // Init per-platform dictionaries

  // Exclude standard C library constants that conflict with stdint.h/inttypes.h
  AddExcludedType('true');
  AddExcludedType('false');

  // Exclude Windows platform macros that conflict with compiler-defined macros
  AddExcludedType('WIN32');
  AddExcludedType('WIN64');
  AddExcludedType('WINVER');
  AddExcludedType('NOSERVICE');
  AddExcludedType('NOMCX');
  AddExcludedType('NOIME');
  AddExcludedType('UNICODE');
  AddExcludedType('_UNICODE');

  // Exclude functions that conflict with compiler intrinsics
  AddExcludedType('INT8_MAX');
  AddExcludedType('INT16_MAX');
  AddExcludedType('INT32_MAX');
  AddExcludedType('INT64_MAX');
  AddExcludedType('INT8_MIN');
  AddExcludedType('INT16_MIN');
  AddExcludedType('INT32_MIN');
  AddExcludedType('INT64_MIN');
  AddExcludedType('UINT8_MAX');
  AddExcludedType('UINT16_MAX');
  AddExcludedType('UINT32_MAX');
  AddExcludedType('UINT64_MAX');
  AddExcludedType('INTMAX_MAX');
  AddExcludedType('INTMAX_MIN');
  AddExcludedType('UINTMAX_MAX');
  AddExcludedType('WCHAR_MIN');
  AddExcludedType('WCHAR_MAX');
  AddExcludedType('WINT_MIN');
  AddExcludedType('WINT_MAX');

  // Exclude printf/scanf format specifiers from inttypes.h
  AddExcludedType('PRId8');
  AddExcludedType('PRId16');
  AddExcludedType('PRId32');
  AddExcludedType('PRId64');
  AddExcludedType('PRIdLEAST8');
  AddExcludedType('PRIdLEAST16');
  AddExcludedType('PRIdLEAST32');
  AddExcludedType('PRIdLEAST64');
  AddExcludedType('PRIdFAST8');
  AddExcludedType('PRIdFAST16');
  AddExcludedType('PRIdFAST32');
  AddExcludedType('PRIdFAST64');
  AddExcludedType('PRIdMAX');
  AddExcludedType('PRIdPTR');
  AddExcludedType('PRIi8');
  AddExcludedType('PRIi16');
  AddExcludedType('PRIi32');
  AddExcludedType('PRIi64');
  AddExcludedType('PRIiLEAST8');
  AddExcludedType('PRIiLEAST16');
  AddExcludedType('PRIiLEAST32');
  AddExcludedType('PRIiLEAST64');
  AddExcludedType('PRIiFAST8');
  AddExcludedType('PRIiFAST16');
  AddExcludedType('PRIiFAST32');
  AddExcludedType('PRIiFAST64');
  AddExcludedType('PRIiMAX');
  AddExcludedType('PRIiPTR');
  AddExcludedType('PRIo8');
  AddExcludedType('PRIo16');
  AddExcludedType('PRIo32');
  AddExcludedType('PRIo64');
  AddExcludedType('PRIoLEAST8');
  AddExcludedType('PRIoLEAST16');
  AddExcludedType('PRIoLEAST32');
  AddExcludedType('PRIoLEAST64');
  AddExcludedType('PRIoFAST8');
  AddExcludedType('PRIoFAST16');
  AddExcludedType('PRIoFAST32');
  AddExcludedType('PRIoFAST64');
  AddExcludedType('PRIoMAX');
  AddExcludedType('PRIoPTR');
  AddExcludedType('PRIu8');
  AddExcludedType('PRIu16');
  AddExcludedType('PRIu32');
  AddExcludedType('PRIu64');
  AddExcludedType('PRIuLEAST8');
  AddExcludedType('PRIuLEAST16');
  AddExcludedType('PRIuLEAST32');
  AddExcludedType('PRIuLEAST64');
  AddExcludedType('PRIuFAST8');
  AddExcludedType('PRIuFAST16');
  AddExcludedType('PRIuFAST32');
  AddExcludedType('PRIuFAST64');
  AddExcludedType('PRIuMAX');
  AddExcludedType('PRIuPTR');
  AddExcludedType('PRIx8');
  AddExcludedType('PRIx16');
  AddExcludedType('PRIx32');
  AddExcludedType('PRIx64');
  AddExcludedType('PRIxLEAST8');
  AddExcludedType('PRIxLEAST16');
  AddExcludedType('PRIxLEAST32');
  AddExcludedType('PRIxLEAST64');
  AddExcludedType('PRIxFAST8');
  AddExcludedType('PRIxFAST16');
  AddExcludedType('PRIxFAST32');
  AddExcludedType('PRIxFAST64');
  AddExcludedType('PRIxMAX');
  AddExcludedType('PRIxPTR');
  AddExcludedType('PRIX8');
  AddExcludedType('PRIX16');
  AddExcludedType('PRIX32');
  AddExcludedType('PRIX64');
  AddExcludedType('PRIXLEAST8');
  AddExcludedType('PRIXLEAST16');
  AddExcludedType('PRIXLEAST32');
  AddExcludedType('PRIXLEAST64');
  AddExcludedType('PRIXFAST8');
  AddExcludedType('PRIXFAST16');
  AddExcludedType('PRIXFAST32');
  AddExcludedType('PRIXFAST64');
  AddExcludedType('PRIXMAX');
  AddExcludedType('PRIXPTR');
  AddExcludedType('SCNd8');
  AddExcludedType('SCNd16');
  AddExcludedType('SCNd32');
  AddExcludedType('SCNd64');
  AddExcludedType('SCNdLEAST8');
  AddExcludedType('SCNdLEAST16');
  AddExcludedType('SCNdLEAST32');
  AddExcludedType('SCNdLEAST64');
  AddExcludedType('SCNdFAST8');
  AddExcludedType('SCNdFAST16');
  AddExcludedType('SCNdFAST32');
  AddExcludedType('SCNdFAST64');
  AddExcludedType('SCNdMAX');
  AddExcludedType('SCNdPTR');
  AddExcludedType('SCNi8');
  AddExcludedType('SCNi16');
  AddExcludedType('SCNi32');
  AddExcludedType('SCNi64');
  AddExcludedType('SCNiLEAST8');
  AddExcludedType('SCNiLEAST16');
  AddExcludedType('SCNiLEAST32');
  AddExcludedType('SCNiLEAST64');
  AddExcludedType('SCNiFAST8');
  AddExcludedType('SCNiFAST16');
  AddExcludedType('SCNiFAST32');
  AddExcludedType('SCNiFAST64');
  AddExcludedType('SCNiMAX');
  AddExcludedType('SCNiPTR');
  AddExcludedType('SCNo8');
  AddExcludedType('SCNo16');
  AddExcludedType('SCNo32');
  AddExcludedType('SCNo64');
  AddExcludedType('SCNoLEAST8');
  AddExcludedType('SCNoLEAST16');
  AddExcludedType('SCNoLEAST32');
  AddExcludedType('SCNoLEAST64');
  AddExcludedType('SCNoFAST8');
  AddExcludedType('SCNoFAST16');
  AddExcludedType('SCNoFAST32');
  AddExcludedType('SCNoFAST64');
  AddExcludedType('SCNoMAX');
  AddExcludedType('SCNoPTR');
  AddExcludedType('SCNu8');
  AddExcludedType('SCNu16');
  AddExcludedType('SCNu32');
  AddExcludedType('SCNu64');
  AddExcludedType('SCNuLEAST8');
  AddExcludedType('SCNuLEAST16');
  AddExcludedType('SCNuLEAST32');
  AddExcludedType('SCNuLEAST64');
  AddExcludedType('SCNuFAST8');
  AddExcludedType('SCNuFAST16');
  AddExcludedType('SCNuFAST32');
  AddExcludedType('SCNuFAST64');
  AddExcludedType('SCNuMAX');
  AddExcludedType('SCNuPTR');
  AddExcludedType('SCNx8');
  AddExcludedType('SCNx16');
  AddExcludedType('SCNx32');
  AddExcludedType('SCNx64');
  AddExcludedType('SCNxLEAST8');
  AddExcludedType('SCNxLEAST16');
  AddExcludedType('SCNxLEAST32');
  AddExcludedType('SCNxLEAST64');
  AddExcludedType('SCNxFAST8');
  AddExcludedType('SCNxFAST16');
  AddExcludedType('SCNxFAST32');
  AddExcludedType('SCNxFAST64');
  AddExcludedType('SCNxMAX');
  AddExcludedType('SCNxPTR');

  AddExcludedFunction('alloca');

  //ReplaceText('parent:', 'parent_:');
  //ReplaceText('name:', 'name_:');

end;

destructor TCImporter.Destroy();
begin
  FUserUndefines.Free();
  FUserDefines.Free();
  FDepDlls.Free();
  FFuncDllMap.Free();
  FDllNameMap.Free();
  FUsesUnits.Free();
  FExcludedFunctions.Free();
  FFunctionRenames.Free();
  FExcludedTypes.Free();
  FIncludePaths.Free();
  FSourcePaths.Free();
  FReplacements.Free();
  FInsertions.Free();
  FForwardDecls.Free();
  FFunctions.Free();
  FDefines.Free();
  FTypedefs.Free();
  FEnums.Free();
  FStructs.Free();
  FOutput.Free();
  FLexer.Free();

  inherited;
end;

function TCImporter.PreprocessHeader(const AHeaderFile: string; out APreprocessedSource: string): Boolean;
var
  LLibTCC: TLibTCC;
  LOutputFile: string;
  LOutputDir: string;
  LHeaderFile: string;
  LIncludePath: string;
  LPath: string;
  LTCCBasePath: string;
  LCompileResult: Boolean;
  LTCCErrors: TStringList;
begin
  Result := False;
  APreprocessedSource := '';

  LHeaderFile := TPath.GetFullPath(AHeaderFile);

  if FOutputPath <> '' then
    LOutputDir := TPath.GetFullPath(FOutputPath)
  else
    LOutputDir := TPath.GetDirectoryName(LHeaderFile);
  LOutputFile := TPath.Combine(LOutputDir, FModuleName + '_pp.c');
  TUtils.CreateDirInPath(LOutputFile);

  LTCCErrors := TStringList.Create();
  try
    LLibTCC := TLibTCC.Create();
    try
      // Capture TCC errors
      LLibTCC.SetPrintCallback(LTCCErrors,
        procedure(const AError: string; const AUserData: Pointer)
        begin
          TStringList(AUserData).Add(AError);
        end);

      if not LLibTCC.SetOuput(opPreProcess) then
      begin
        FLastError := 'Failed to set TCC output type to PreProcess';
        Exit;
      end;

      // Prevent libtcc from searching disk for system headers
      LLibTCC.SetOption('-nostdinc');

      // -dD to preserve #define definitions in output
      LLibTCC.SetOption('-dD');

      // Set preprocess output file
      if not LLibTCC.SetPreprocessOutput(LOutputFile) then
      begin
        FLastError := 'Failed to set preprocess output file';
        Exit;
      end;

      // Add TCC base include paths
      LTCCBasePath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'thirdparty\tcc');
      LLibTCC.AddIncludePath(TPath.Combine(LTCCBasePath, 'include'));
      LLibTCC.AddIncludePath(TPath.Combine(LTCCBasePath, 'include\winapi'));

      // Add user include paths
      for LPath in FIncludePaths do
      begin
        LIncludePath := TPath.GetFullPath(LPath).Replace('\', '/');
        LLibTCC.AddIncludePath(LIncludePath);
      end;

      // Apply user defines
      for LPath in FUserDefines.Keys do
        LLibTCC.DefineSymbol(LPath, FUserDefines[LPath]);

      // Apply user undefines
      for LPath in FUserUndefines do
        LLibTCC.UndefineSymbol(LPath);

      // Compile (preprocess) the header file
      LCompileResult := LLibTCC.CompileFile(LHeaderFile);

      LLibTCC.ClosePreprocessOutput();
    finally
      LLibTCC.Free();
    end;

    if not LCompileResult then
    begin
      FLastError := 'Preprocessing failed via libtcc';
      if LTCCErrors.Count > 0 then
        FLastError := FLastError + sLineBreak + LTCCErrors.Text;
      if TFile.Exists(LOutputFile) then
        TFile.Delete(LOutputFile);
      Exit;
    end;

    if TFile.Exists(LOutputFile) then
    begin
      APreprocessedSource := TFile.ReadAllText(LOutputFile);
      if not FSavePreprocessed then
        TFile.Delete(LOutputFile);
      Result := True;
    end
    else
    begin
      FLastError := 'Preprocessor output file not created';
      if LTCCErrors.Count > 0 then
        FLastError := FLastError + sLineBreak + LTCCErrors.Text;
    end;
  finally
    LTCCErrors.Free();
  end;
end;

function TCImporter.IsAtEnd(): Boolean;
begin
  Result := FCurrentToken.Kind = ctkEOF;
end;

function TCImporter.PeekNext(): TCToken;
begin
  Result := FLexer.GetToken(FPos + 1);
end;

procedure TCImporter.Advance();
begin
  Inc(FPos);
  FCurrentToken := FLexer.GetToken(FPos);
end;

function TCImporter.Check(const AKind: TCTokenKind): Boolean;
begin
  Result := FCurrentToken.Kind = AKind;
end;

function TCImporter.Match(const AKind: TCTokenKind): Boolean;
begin
  if Check(AKind) then
  begin
    Advance();
    Result := True;
  end
  else
    Result := False;
end;

function TCImporter.FunctionReferencesExcludedType(const AFunc: TCFunctionInfo): Boolean;
var
  LI: Integer;
  LTypedef: TCTypedefInfo;
begin
  // Check return type directly
  if FExcludedTypes.Contains(AFunc.ReturnType) then
    Exit(True);

  // Check if return type is a typedef that references excluded types
  for LTypedef in FTypedefs do
  begin
    if LTypedef.AliasName = AFunc.ReturnType then
    begin
      if TypedefReferencesExcludedType(LTypedef) then
        Exit(True);
      Break;
    end;
  end;

  // Check all parameter types
  for LI := 0 to High(AFunc.Params) do
  begin
    if FExcludedTypes.Contains(AFunc.Params[LI].TypeName) then
      Exit(True);

    // Also check if parameter type is a typedef that references excluded types
    for LTypedef in FTypedefs do
    begin
      if LTypedef.AliasName = AFunc.Params[LI].TypeName then
      begin
        if TypedefReferencesExcludedType(LTypedef) then
          Exit(True);
        Break;
      end;
    end;
  end;

  Result := False;
end;

function TCImporter.GetDelphiFuncName(const AFuncName: string): string;
begin
  if FFunctionRenames.TryGetValue(AFuncName, Result) then
    Exit;
  Result := SanitizeIdentifier(AFuncName);
end;

function TCImporter.MatchAny(const AKinds: array of TCTokenKind): Boolean;
var
  LKind: TCTokenKind;
begin
  for LKind in AKinds do
  begin
    if Check(LKind) then
    begin
      Advance();
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TCImporter.SkipToSemicolon();
begin
  while not IsAtEnd() and not Check(ctkSemicolon) do
    Advance();
  if Check(ctkSemicolon) then
    Advance();
end;

procedure TCImporter.SkipToRBrace();
var
  LDepth: Integer;
begin
  LDepth := 1;
  while not IsAtEnd() and (LDepth > 0) do
  begin
    if Check(ctkLBrace) then
      Inc(LDepth)
    else if Check(ctkRBrace) then
      Dec(LDepth);
    Advance();
  end;
end;

procedure TCImporter.SkipAttribute();
var
  LDepth: Integer;
begin
  // Skip __attribute__((...)) constructs
  // Also handles __declspec(...)
  // Note: these are tokenized as ctkBuiltin by the lexer
  while Check(ctkBuiltin) and
    (FCurrentToken.Lexeme.StartsWith('__attribute') or FCurrentToken.Lexeme.StartsWith('__declspec')) do
  begin
    Advance(); // skip __attribute__ or __declspec
    if Check(ctkLParen) then
    begin
      LDepth := 0;
      while not IsAtEnd() do
      begin
        if Check(ctkLParen) then
          Inc(LDepth)
        else if Check(ctkRParen) then
        begin
          Dec(LDepth);
          if LDepth = 0 then
          begin
            Advance(); // skip final ')'
            Break;
          end;
        end;
        Advance();
      end;
    end;
  end;
end;

function TCImporter.IsTypeKeyword(): Boolean;
begin
  Result := FCurrentToken.Kind in [
    ctkVoid, ctkChar, ctkShort, ctkInt, ctkLong,
    ctkFloat, ctkDouble, ctkSigned, ctkUnsigned, ctkBool,
    ctkStruct, ctkUnion, ctkEnum, ctkConst
  ];
end;

function TCImporter.ParseBaseType(): string;
var
  LHasUnsigned: Boolean;
  LHasSigned: Boolean;
  LHasLong: Boolean;
  LLongCount: Integer;
  LHasShort: Boolean;
  LDepth: Integer;
begin
  Result := '';
  LHasUnsigned := False;
  LHasSigned := False;
  LHasLong := False;
  LLongCount := 0;
  LHasShort := False;

  while True do
  begin
    case FCurrentToken.Kind of
      ctkConst, ctkVolatile, ctkRestrict, ctkAtomic, ctkInline, ctkStatic:
        Advance();
      ctkUnsigned:
        begin
          LHasUnsigned := True;
          Advance();
        end;
      ctkSigned:
        begin
          LHasSigned := True;
          Advance();
        end;
      ctkLong:
        begin
          LHasLong := True;
          Inc(LLongCount);
          Advance();
        end;
      ctkShort:
        begin
          LHasShort := True;
          Advance();
        end;
      ctkVoid:
        begin
          Result := 'void';
          Advance();
          Exit;
        end;
      ctkChar:
        begin
          if LHasUnsigned then
            Result := 'unsigned char'
          else if LHasSigned then
            Result := 'signed char'
          else
            Result := 'char';
          Advance();
          Exit;
        end;
      ctkInt:
        begin
          if LHasShort then
          begin
            if LHasUnsigned then Result := 'unsigned short' else Result := 'short';
          end
          else if LHasLong then
          begin
            if LLongCount >= 2 then
            begin
              if LHasUnsigned then Result := 'unsigned long long' else Result := 'long long';
            end
            else
            begin
              if LHasUnsigned then Result := 'unsigned long' else Result := 'long';
            end;
          end
          else
          begin
            if LHasUnsigned then Result := 'unsigned int' else Result := 'int';
          end;
          Advance();
          Exit;
        end;
      ctkFloat:
        begin
          Result := 'float';
          Advance();
          Exit;
        end;
      ctkDouble:
        begin
          if LHasLong then Result := 'long double' else Result := 'double';
          Advance();
          Exit;
        end;
      ctkBool:
        begin
          Result := '_Bool';
          Advance();
          Exit;
        end;
      ctkStruct, ctkUnion:
        begin
          if FCurrentToken.Kind = ctkStruct then Result := 'struct ' else Result := 'union ';
          Advance();
          if Check(ctkIdentifier) then
          begin
            Result := Result + FCurrentToken.Lexeme;
            Advance();
          end;
          if Check(ctkLBrace) then
          begin
            Advance();
            SkipToRBrace();
          end;
          Exit;
        end;
      ctkEnum:
        begin
          Result := 'enum ';
          Advance();
          if Check(ctkIdentifier) then
          begin
            Result := Result + FCurrentToken.Lexeme;
            Advance();
          end;
          if Check(ctkLBrace) then
          begin
            Advance();
            SkipToRBrace();
          end;
          Exit;
        end;
      ctkIdentifier:
        begin
          // If we've seen type modifiers (long, short, unsigned, signed),
          // this identifier is NOT a type name - it's the variable/param name
          if LHasUnsigned or LHasSigned or LHasLong or LHasShort then
            Break;  // Let final logic construct type from modifiers
          Result := FCurrentToken.Lexeme;
          Advance();
          Exit;
        end;
      ctkBuiltin:
        begin
          Result := FCurrentToken.Lexeme;
          Advance();
          if Check(ctkLParen) then
          begin
            LDepth := 1;
            Advance();
            while not IsAtEnd() and (LDepth > 0) do
            begin
              if Check(ctkLParen) then Inc(LDepth)
              else if Check(ctkRParen) then Dec(LDepth);
              Advance();
            end;
          end;
          Exit;
        end;
    else
      Break;
    end;
  end;

  if (Result = '') and (LHasUnsigned or LHasSigned or LHasLong or LHasShort) then
  begin
    if LHasShort then
    begin
      if LHasUnsigned then Result := 'unsigned short' else Result := 'short';
    end
    else if LHasLong then
    begin
      if LLongCount >= 2 then
      begin
        if LHasUnsigned then Result := 'unsigned long long' else Result := 'long long';
      end
      else
      begin
        if LHasUnsigned then Result := 'unsigned long' else Result := 'long';
      end;
    end
    else
    begin
      if LHasUnsigned then Result := 'unsigned int' else Result := 'int';
    end;
  end;
end;

function TCImporter.ParsePointerDepth(): Integer;
begin
  Result := 0;
  while Check(ctkStar) do
  begin
    Inc(Result);
    Advance();
    while MatchAny([ctkConst, ctkVolatile, ctkRestrict]) do
      ;
  end;
end;

procedure TCImporter.ParseTopLevel();
var
  LBaseType: string;
  LPtrDepth: Integer;
  LName: string;
  LIsUnion: Boolean;
  LTagName: string;
  LStructInfo: TCStructInfo;
  LEnumInfo: TCEnumInfo;
begin
  while not IsAtEnd() do
  begin
    // Handle line markers to track current source file
    if Check(ctkLineMarker) then
    begin
      if FCurrentToken.Lexeme <> '' then
        FCurrentSourceFile := FCurrentToken.Lexeme;
      Advance();
      Continue;
    end;

    while MatchAny([ctkExtern, ctkStatic, ctkInline]) do
      ;

    // Skip __attribute__((...)) and __declspec(...) constructs
    SkipAttribute();

    if Check(ctkTypedef) then
      ParseTypedef()
    else if Check(ctkStruct) or Check(ctkUnion) then
    begin
      // Handle standalone struct/union definitions: struct Name { ... };
      LIsUnion := Check(ctkUnion);
      Advance();

      LTagName := '';
      if Check(ctkIdentifier) then
      begin
        LTagName := FCurrentToken.Lexeme;
        Advance();
      end;

      if Check(ctkLBrace) then
      begin
        ParseStruct(LIsUnion, LStructInfo);
        if LTagName <> '' then
          LStructInfo.StructName := LTagName;
        if (LStructInfo.StructName <> '') and IsAllowedSourceFile() then
        begin
          FStructs.Add(LStructInfo);
          // Remove from forward declarations since we now have the full definition
          FForwardDecls.Remove(LStructInfo.StructName);
        end;
        Match(ctkSemicolon);
      end
      else
      begin
        // Could be: function returning struct, variable decl, or forward decl
        LPtrDepth := ParsePointerDepth();
        if Check(ctkIdentifier) then
        begin
          LName := FCurrentToken.Lexeme;
          Advance();
          if Check(ctkLParen) then
            // Function with struct return type: struct Name * func_name(...)
            ParseFunction(LTagName, LPtrDepth, LName)
          else
            SkipToSemicolon();
        end
        else
        begin
          // Forward declaration: struct Name; -- register as opaque type
          if (LTagName <> '') and IsAllowedSourceFile() and
             not FForwardDecls.Contains(LTagName) and
             not HasStructDefinition(LTagName) then
            FForwardDecls.Add(LTagName);
          SkipToSemicolon();
        end;
      end;
    end
    else if Check(ctkEnum) then
    begin
      // Handle standalone enum definitions: enum Name { ... };
      Advance();

      LTagName := '';
      if Check(ctkIdentifier) then
      begin
        LTagName := FCurrentToken.Lexeme;
        Advance();
      end;

      if Check(ctkLBrace) then
      begin
        ParseEnum(LEnumInfo);
        if LTagName <> '' then
          LEnumInfo.EnumName := LTagName;
        if (LEnumInfo.EnumName <> '') and IsAllowedSourceFile() then
          FEnums.Add(LEnumInfo);
        Match(ctkSemicolon);
      end
      else
      begin
        // Could be: function returning enum: enum Name [*] func_name(...)
        LPtrDepth := ParsePointerDepth();
        if Check(ctkIdentifier) then
        begin
          LName := FCurrentToken.Lexeme;
          Advance();
          if Check(ctkLParen) then
            ParseFunction(LTagName, LPtrDepth, LName)
          else
            SkipToSemicolon();
        end
        else
          SkipToSemicolon();
      end;
    end
    else if IsTypeKeyword() or Check(ctkIdentifier) then
    begin
      LBaseType := ParseBaseType();
      LPtrDepth := ParsePointerDepth();

      if Check(ctkIdentifier) then
      begin
        LName := FCurrentToken.Lexeme;
        Advance();

        if Check(ctkLParen) then
          ParseFunction(LBaseType, LPtrDepth, LName)
        else
          SkipToSemicolon();
      end
      else
        SkipToSemicolon();
    end
    else if Check(ctkSemicolon) then
      Advance()
    else
      Advance();
  end;
end;

{ ParseFuncPtrTypedef }
procedure TCImporter.ParseFuncPtrTypedef(const AReturnType: string; const AReturnPtrDepth: Integer);
var
  LInfo: TCTypedefInfo;
  LParam: TCParamInfo;
begin
  // Expects current token is '('
  // Pattern: (*Name)(params)
  Advance();

  if not Check(ctkStar) then
  begin
    SkipToSemicolon();
    Exit;
  end;

  Advance();

  if not Check(ctkIdentifier) then
  begin
    SkipToSemicolon();
    Exit;
  end;

  LInfo.AliasName := FCurrentToken.Lexeme;
  LInfo.IsFunctionPointer := True;
  LInfo.TargetType := AReturnType;
  LInfo.IsPointer := AReturnPtrDepth > 0;
  LInfo.PointerDepth := AReturnPtrDepth;
  Advance();

  if Check(ctkRParen) then
    Advance();

  // Parse function pointer parameters into FuncInfo
  LInfo.FuncInfo.FuncName := LInfo.AliasName;
  LInfo.FuncInfo.ReturnType := AReturnType;
  LInfo.FuncInfo.ReturnIsPointer := AReturnPtrDepth > 0;
  LInfo.FuncInfo.ReturnPointerDepth := AReturnPtrDepth;
  LInfo.FuncInfo.IsVariadic := False;
  SetLength(LInfo.FuncInfo.Params, 0);

  if Check(ctkLParen) then
  begin
    Advance();

    while not IsAtEnd() and not Check(ctkRParen) do
    begin
      // Check for void parameter list
      if Check(ctkVoid) and (PeekNext().Kind = ctkRParen) then
      begin
        Advance();
        Break;
      end;

      // Check for variadic
      if Check(ctkEllipsis) then
      begin
        LInfo.FuncInfo.IsVariadic := True;
        Advance();
        Break;
      end;

      LParam.IsConst := False;
      LParam.IsConstTarget := False;
      if Check(ctkConst) then
      begin
        LParam.IsConst := True;
        Advance();
      end;

      LParam.TypeName := ParseBaseType();
      LParam.PointerDepth := ParsePointerDepth();
      LParam.IsPointer := LParam.PointerDepth > 0;

      // If const was before type and we have a pointer, it's pointer to const
      if LParam.IsConst and LParam.IsPointer then
        LParam.IsConstTarget := True;

      if Check(ctkConst) then
      begin
        LParam.IsConst := True;
        Advance();
      end;

      if Check(ctkIdentifier) then
      begin
        LParam.ParamName := FCurrentToken.Lexeme;
        Advance();
      end
      else
        LParam.ParamName := '';

      // Handle array parameters as pointers
      if Check(ctkLBracket) then
      begin
        LParam.IsPointer := True;
        Inc(LParam.PointerDepth);
        while not IsAtEnd() and not Check(ctkRBracket) do
          Advance();
        Match(ctkRBracket);
      end;

      SetLength(LInfo.FuncInfo.Params, Length(LInfo.FuncInfo.Params) + 1);
      LInfo.FuncInfo.Params[High(LInfo.FuncInfo.Params)] := LParam;

      if not Match(ctkComma) then
        Break;
    end;

    Match(ctkRParen);
  end;

  if IsAllowedSourceFile() then
    FTypedefs.Add(LInfo);
end;

procedure TCImporter.ParseTypedef();
var
  LInfo: TCTypedefInfo;
  LStructInfo: TCStructInfo;
  LEnumInfo: TCEnumInfo;
  LBaseType: string;
  LPtrDepth: Integer;
  LIsUnion: Boolean;
  LTagName: string;
  LAliasName: string;
begin
  Advance();

  if Check(ctkStruct) or Check(ctkUnion) then
  begin
    LIsUnion := Check(ctkUnion);
    Advance();

    LTagName := '';
    if Check(ctkIdentifier) then
    begin
      LTagName := FCurrentToken.Lexeme;
      Advance();
    end;

    if Check(ctkLBrace) then
    begin
      ParseStruct(LIsUnion, LStructInfo);

      if Check(ctkIdentifier) then
      begin
        LStructInfo.StructName := FCurrentToken.Lexeme;
        Advance();
      end
      else if LTagName <> '' then
        LStructInfo.StructName := LTagName;

      if LStructInfo.StructName <> '' then
      begin
        if IsAllowedSourceFile() then
          FStructs.Add(LStructInfo);
      end;
    end
    else
    begin
      // Handle pointer typedefs like: typedef struct X *Y;
      LPtrDepth := ParsePointerDepth();
      if Check(ctkIdentifier) then
      begin
        LAliasName := FCurrentToken.Lexeme;
        Advance();

        if (LTagName <> '') and (LTagName = LAliasName) and (LPtrDepth = 0) then
        begin
          if IsAllowedSourceFile() and not FForwardDecls.Contains(LAliasName) and not HasStructDefinition(LAliasName) then
            FForwardDecls.Add(LAliasName);
        end
        else if LTagName <> '' then
        begin
          // Add tag name as forward decl if it's an opaque struct (no body defined)
          if IsAllowedSourceFile() and not FForwardDecls.Contains(LTagName) and not HasStructDefinition(LTagName) then
            FForwardDecls.Add(LTagName);

          LInfo.AliasName := LAliasName;
          LInfo.TargetType := LTagName;
          LInfo.IsPointer := LPtrDepth > 0;
          LInfo.PointerDepth := LPtrDepth;
          LInfo.IsFunctionPointer := False;
          if IsAllowedSourceFile() then
            FTypedefs.Add(LInfo);
        end;
      end
      else if Check(ctkLParen) then
      begin
        // Function pointer returning struct: typedef struct Tag (*Name)(params)
        if LTagName <> '' then
          ParseFuncPtrTypedef(LTagName, 0);
      end;
    end;
  end
  else if Check(ctkEnum) then
  begin
    Advance();
    LTagName := '';
    if Check(ctkIdentifier) then
    begin
      LTagName := FCurrentToken.Lexeme;
      Advance();
    end;

    if Check(ctkLBrace) then
    begin
      ParseEnum(LEnumInfo);

      if Check(ctkIdentifier) then
      begin
        LEnumInfo.EnumName := FCurrentToken.Lexeme;
        Advance();
      end
      else if LTagName <> '' then
        LEnumInfo.EnumName := LTagName;

      if LEnumInfo.EnumName <> '' then
      begin
        if IsAllowedSourceFile() then
          FEnums.Add(LEnumInfo);
      end;
    end;
  end
  else
  begin
    LBaseType := ParseBaseType();
    LPtrDepth := ParsePointerDepth();

    if Check(ctkLParen) then
      ParseFuncPtrTypedef(LBaseType, LPtrDepth)
    else if Check(ctkIdentifier) then
    begin
      LInfo.AliasName := FCurrentToken.Lexeme;
      LInfo.TargetType := LBaseType;
      LInfo.IsPointer := LPtrDepth > 0;
      LInfo.PointerDepth := LPtrDepth;
      LInfo.IsFunctionPointer := False;
      Advance();
      if IsAllowedSourceFile() then
        FTypedefs.Add(LInfo);
    end;
  end;

  if Check(ctkSemicolon) then
    Advance();
end;

procedure TCImporter.ParseStruct(const AIsUnion: Boolean; out AInfo: TCStructInfo);
begin
  AInfo.StructName := '';
  AInfo.IsUnion := AIsUnion;
  SetLength(AInfo.Fields, 0);

  if not Match(ctkLBrace) then
    Exit;

  while not IsAtEnd() and not Check(ctkRBrace) do
    ParseStructField(AInfo, AInfo.Fields);

  Match(ctkRBrace);
end;

procedure TCImporter.ParseStructField(const AStruct: TCStructInfo; var AFields: TArray<TCFieldInfo>);
var
  LField: TCFieldInfo;
  LBaseType: string;
  LConstVal: Int64;
begin
  // Skip line markers inside structs/unions
  while Check(ctkLineMarker) do
  begin
    FCurrentSourceFile := FCurrentToken.Lexeme;
    Advance();
  end;

  if Check(ctkStruct) or Check(ctkUnion) then
  begin
    Advance();
    if Check(ctkIdentifier) then
    begin
      if PeekNext().Kind = ctkLBrace then
      begin
        // Inline struct/union definition — skip the body
        Advance(); // skip type name
        Advance(); // skip '{'
        SkipToRBrace();
      end
      else
      begin
        // Forward reference: struct TypeName *field — capture the type name
        LBaseType := FCurrentToken.Lexeme;
        Advance();
      end;
    end
    else if Check(ctkLBrace) then
    begin
      // Anonymous struct/union — skip the body
      Advance();
      SkipToRBrace();
    end;
  end;

  if LBaseType = '' then
    LBaseType := ParseBaseType();
  if LBaseType = '' then
  begin
    SkipToSemicolon();
    Exit;
  end;

  repeat
    LField.TypeName := LBaseType;
    LField.PointerDepth := ParsePointerDepth();
    LField.IsPointer := LField.PointerDepth > 0;
    LField.ArraySize := 0;
    LField.BitWidth := 0;

    if Check(ctkIdentifier) then
    begin
      LField.FieldName := FCurrentToken.Lexeme;
      Advance();

      if Check(ctkLBracket) then
      begin
        Advance();
        if Check(ctkIntLiteral) then
        begin
          LField.ArraySize := FCurrentToken.IntValue;
          Advance();
        end
        else if Check(ctkIdentifier) then
        begin
          // Try to resolve enum constant or #define integer
          if ResolveConstantValue(FCurrentToken.Lexeme, LConstVal) then
            LField.ArraySize := LConstVal
          else
            LField.ArraySize := 0;
          Advance();
        end
        else
        begin
          // Skip unknown expression tokens until ] for graceful recovery
          while not IsAtEnd() and not Check(ctkRBracket) do
            Advance();
        end;
        Match(ctkRBracket);
      end;

      if Check(ctkColon) then
      begin
        Advance();
        if Check(ctkIntLiteral) then
        begin
          LField.BitWidth := FCurrentToken.IntValue;
          Advance();
        end;
      end;

      SetLength(AFields, Length(AFields) + 1);
      AFields[High(AFields)] := LField;
    end;
  until not Match(ctkComma);

  Match(ctkSemicolon);
end;

function TCImporter.ParseEnumExpression(out AValue: Int64): Boolean;

  function ParsePrimary(out AVal: Int64): Boolean;
  var
    LInner: Int64;
  begin
    Result := False;
    AVal := 0;

    if Check(ctkBitNot) then
    begin
      Advance();
      if not ParsePrimary(LInner) then
        Exit;
      AVal := not LInner;
      Exit(True);
    end;

    if Check(ctkIntLiteral) then
    begin
      AVal := FCurrentToken.IntValue;
      Advance();
      Exit(True);
    end;

    if Check(ctkIdentifier) then
    begin
      Result := ResolveConstantValue(FCurrentToken.Lexeme, AVal);
      Advance();
      Exit;
    end;

    if Check(ctkLParen) then
    begin
      Advance();
      Result := ParseEnumExpression(AVal);
      if Check(ctkRParen) then
        Advance();
      Exit;
    end;
  end;

  function ParseShiftExpr(out AVal: Int64): Boolean;
  var
    LRight: Int64;
  begin
    Result := ParsePrimary(AVal);
    if not Result then
      Exit;

    while Check(ctkLShift) do
    begin
      Advance();
      if not ParsePrimary(LRight) then
        Break;
      AVal := AVal shl LRight;
    end;
  end;

var
  LRight: Int64;
begin
  // Precedence: | (lowest) then << then primary (highest)
  Result := ParseShiftExpr(AValue);
  if not Result then
    Exit;

  while Check(ctkBitOr) do
  begin
    Advance();
    if not ParseShiftExpr(LRight) then
      Break;
    AValue := AValue or LRight;
  end;
end;

procedure TCImporter.ParseEnum(out AInfo: TCEnumInfo);
var
  LValue: TCEnumValue;
  LNextVal: Int64;
begin
  AInfo.EnumName := '';
  SetLength(AInfo.Values, 0);
  LNextVal := 0;

  if not Match(ctkLBrace) then
    Exit;

  while not IsAtEnd() and not Check(ctkRBrace) do
  begin
    if Check(ctkIdentifier) then
    begin
      LValue.ValueName := FCurrentToken.Lexeme;
      LValue.HasExplicitValue := False;
      LValue.Value := LNextVal;
      Advance();

      if Match(ctkEquals) then
      begin
        LValue.HasExplicitValue := True;

        if not ParseEnumExpression(LValue.Value) then
        begin
          // Skip unrecognized expression tokens until comma or rbrace
          while not IsAtEnd() and not Check(ctkComma) and not Check(ctkRBrace) do
            Advance();
          LValue.HasExplicitValue := False;
        end;
      end;

      LNextVal := LValue.Value + 1;
      SetLength(AInfo.Values, Length(AInfo.Values) + 1);
      AInfo.Values[High(AInfo.Values)] := LValue;
    end;

    if not Match(ctkComma) then
      Break;
  end;

  Match(ctkRBrace);
end;

procedure TCImporter.ParseFunction(const AReturnType: string; const AReturnPtrDepth: Integer; const AFuncName: string);
var
  LFunc: TCFunctionInfo;
  LParam: TCParamInfo;
  LExisting: TCFunctionInfo;
  LI: Integer;
begin
  // Skip if we've already seen this function name
  for LExisting in FFunctions do
  begin
    if LExisting.FuncName = AFuncName then
    begin
      // Skip to end of this declaration/definition
      while not IsAtEnd() and not Check(ctkSemicolon) do
      begin
        if Check(ctkLBrace) then
        begin
          Advance();
          SkipToRBrace();
          Exit;
        end;
        Advance();
      end;
      Match(ctkSemicolon);
      Exit;
    end;
  end;

  LFunc.FuncName := AFuncName;
  LFunc.ReturnType := AReturnType;
  LFunc.ReturnIsPointer := AReturnPtrDepth > 0;
  LFunc.ReturnPointerDepth := AReturnPtrDepth;
  LFunc.IsVariadic := False;
  SetLength(LFunc.Params, 0);

  if not Match(ctkLParen) then
  begin
    SkipToSemicolon();
    Exit;
  end;

  while not IsAtEnd() and not Check(ctkRParen) do
  begin
    if Check(ctkVoid) and (PeekNext().Kind = ctkRParen) then
    begin
      Advance();
      Break;
    end;

    if Check(ctkEllipsis) then
    begin
      LFunc.IsVariadic := True;
      Advance();
      Break;
    end;

    LParam.IsConst := False;
    LParam.IsConstTarget := False;
    if Check(ctkConst) then
    begin
      LParam.IsConst := True;
      Advance();
    end;

    LParam.TypeName := ParseBaseType();
    LParam.PointerDepth := ParsePointerDepth();
    LParam.IsPointer := LParam.PointerDepth > 0;

    // If const was before type and we have a pointer, it's pointer to const
    if LParam.IsConst and LParam.IsPointer then
      LParam.IsConstTarget := True;

    if Check(ctkConst) then
    begin
      LParam.IsConst := True;
      Advance();
    end;

    if Check(ctkIdentifier) then
    begin
      LParam.ParamName := FCurrentToken.Lexeme;
      Advance();
    end
    else
      LParam.ParamName := '';

    if Check(ctkLBracket) then
    begin
      LParam.IsPointer := True;
      Inc(LParam.PointerDepth);
      while not IsAtEnd() and not Check(ctkRBracket) do
        Advance();
      Match(ctkRBracket);
    end;

    SetLength(LFunc.Params, Length(LFunc.Params) + 1);
    LFunc.Params[High(LFunc.Params)] := LParam;

    if not Match(ctkComma) then
      Break;
  end;

  Match(ctkRParen);
  Match(ctkSemicolon);

  if IsAllowedSourceFile() then
  begin
    // Don't add malformed functions (parsing errors from macros/inline defs)
    for LI := 0 to High(LFunc.Params) do
    begin
      if LFunc.Params[LI].TypeName = '' then
        Exit;
      if (Length(LFunc.Params[LI].TypeName) = 1) and CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
        Exit;
    end;
    // Final duplicate check
    for LExisting in FFunctions do
    begin
      if LExisting.FuncName = LFunc.FuncName then
        Exit;
    end;
    // Skip if function name collides with a type name (C allows this,
    // Delphi does not) -- unless a rename is configured to resolve it
    if HasTypeNameCollision(LFunc.FuncName) and
       not FFunctionRenames.ContainsKey(LFunc.FuncName) then
      Exit;
    LFunc.SourceFile := FCurrentSourceFile;
    FFunctions.Add(LFunc);
  end;
end;

procedure TCImporter.EmitLn(const AText: string);
begin
  FOutput.AppendLine(StringOfChar(' ', FIndent * 2) + AText);
end;

procedure TCImporter.EmitFmt(const AFormat: string; const AArgs: array of const);
begin
  EmitLn(Format(AFormat, AArgs));
end;


function TCImporter.MapCTypeToDelphi(const ACType: string; const AIsPointer: Boolean; const APtrDepth: Integer; const AIsConstTarget: Boolean): string;
var
  LBaseType: string;
  LI: Integer;
begin
  LBaseType := ACType;

  // Basic C types → Delphi types
  if LBaseType = 'void' then LBaseType := 'Pointer'
  else if LBaseType = '_Bool' then LBaseType := 'Boolean'
  else if LBaseType = 'bool' then LBaseType := 'Boolean'
  else if LBaseType = 'char' then LBaseType := 'UTF8Char'
  else if LBaseType = 'wchar_t' then LBaseType := 'WideChar'
  else if LBaseType = 'signed char' then LBaseType := 'ShortInt'
  else if LBaseType = 'unsigned char' then LBaseType := 'Byte'
  else if LBaseType = 'short' then LBaseType := 'SmallInt'
  else if LBaseType = 'unsigned short' then LBaseType := 'Word'
  else if LBaseType = 'int' then LBaseType := 'Integer'
  else if LBaseType = 'unsigned int' then LBaseType := 'Cardinal'
  else if LBaseType = 'long' then LBaseType := 'Integer'
  else if LBaseType = 'unsigned long' then LBaseType := 'Cardinal'
  else if LBaseType = 'long long' then LBaseType := 'Int64'
  else if LBaseType = 'unsigned long long' then LBaseType := 'UInt64'
  else if LBaseType = 'float' then LBaseType := 'Single'
  else if LBaseType = 'double' then LBaseType := 'Double'
  else if LBaseType = 'long double' then LBaseType := 'Double'

  // C99 stdint.h exact-width types
  else if LBaseType = 'int8_t' then LBaseType := 'Int8'
  else if LBaseType = 'int16_t' then LBaseType := 'Int16'
  else if LBaseType = 'int32_t' then LBaseType := 'Int32'
  else if LBaseType = 'int64_t' then LBaseType := 'Int64'
  else if LBaseType = 'uint8_t' then LBaseType := 'UInt8'
  else if LBaseType = 'uint16_t' then LBaseType := 'UInt16'
  else if LBaseType = 'uint32_t' then LBaseType := 'UInt32'
  else if LBaseType = 'uint64_t' then LBaseType := 'UInt64'

  // C99 stdint.h pointer/size types (Win64)
  else if LBaseType = 'size_t' then LBaseType := 'NativeUInt'
  else if LBaseType = 'ssize_t' then LBaseType := 'NativeInt'
  else if LBaseType = 'ptrdiff_t' then LBaseType := 'NativeInt'
  else if LBaseType = 'intptr_t' then LBaseType := 'NativeInt'
  else if LBaseType = 'uintptr_t' then LBaseType := 'NativeUInt'
  else if LBaseType = 'intmax_t' then LBaseType := 'Int64'
  else if LBaseType = 'uintmax_t' then LBaseType := 'UInt64'

  // SDL-specific integer types
  else if LBaseType = 'Sint8' then LBaseType := 'Int8'
  else if LBaseType = 'Sint16' then LBaseType := 'Int16'
  else if LBaseType = 'Sint32' then LBaseType := 'Int32'
  else if LBaseType = 'Sint64' then LBaseType := 'Int64'
  else if LBaseType = 'Uint8' then LBaseType := 'UInt8'
  else if LBaseType = 'Uint16' then LBaseType := 'UInt16'
  else if LBaseType = 'Uint32' then LBaseType := 'UInt32'
  else if LBaseType = 'Uint64' then LBaseType := 'UInt64'

  // Variadic argument types
  else if LBaseType = 'va_list' then LBaseType := 'Pointer'
  else if LBaseType = '__va_list_tag' then LBaseType := 'Pointer'

  // Compound type prefixes — strip prefix, keep original name
  else if LBaseType.StartsWith('struct ') then LBaseType := Copy(LBaseType, 8, Length(LBaseType))
  else if LBaseType.StartsWith('union ') then LBaseType := Copy(LBaseType, 7, Length(LBaseType))
  else if LBaseType.StartsWith('enum ') then LBaseType := Copy(LBaseType, 6, Length(LBaseType));

  // Special case: char* → PUTF8Char (most common C string type)
  if (ACType = 'char') and (APtrDepth = 1) then
  begin
    Result := 'PUTF8Char';
    Exit;
  end;

  // Special case: wchar_t* → PWideChar
  if (ACType = 'wchar_t') and (APtrDepth = 1) then
  begin
    Result := 'PWideChar';
    Exit;
  end;

  // Special case: void* → Pointer, void** → PPointer
  if (ACType = 'void') and (APtrDepth > 0) then
  begin
    if APtrDepth = 1 then
      Result := 'Pointer'
    else if APtrDepth = 2 then
      Result := 'PPointer'
    else
    begin
      Result := 'Pointer';
      for LI := 2 to APtrDepth do
        Result := 'P' + Result;
    end;
    Exit;
  end;

  // General pointer handling: T* → PT, T** → PPT
  if AIsPointer or (APtrDepth > 0) then
  begin
    Result := LBaseType;
    for LI := 1 to APtrDepth do
      Result := 'P' + Result;
  end
  else
    Result := LBaseType;
end;

function TCImporter.ResolveTypedefAlias(const ATypeName: string): string;
var
  LTypedef: TCTypedefInfo;
begin
  // Check if this type is a typedef alias and return the target type
  for LTypedef in FTypedefs do
  begin
    if (not LTypedef.IsFunctionPointer) and (LTypedef.AliasName = ATypeName) then
      Exit(LTypedef.TargetType);
  end;
  // Not a typedef alias, return as-is
  Result := ATypeName;
end;

function TCImporter.ResolveConstantValue(const AName: string; out AValue: Int64): Boolean;
var
  LEnum: TCEnumInfo;
  LVal: TCEnumValue;
  LDef: TCDefineInfo;
begin
  Result := False;

  // Search enum values
  for LEnum in FEnums do
  begin
    for LVal in LEnum.Values do
    begin
      if LVal.ValueName = AName then
      begin
        AValue := LVal.Value;
        Exit(True);
      end;
    end;
  end;

  // Search #define integer constants
  for LDef in FDefines do
  begin
    if (LDef.DefineName = AName) and LDef.IsInteger then
    begin
      AValue := LDef.IntValue;
      Exit(True);
    end;
  end;
end;

function TCImporter.SanitizeIdentifier(const AName: string): string;
const
  CDelphiKeywords: array[0..64] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const',
    'constructor', 'destructor', 'dispinterface', 'div', 'do', 'downto',
    'else', 'end', 'except', 'exports', 'file', 'finalization', 'finally',
    'for', 'function', 'goto', 'if', 'implementation', 'in', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library',
    'mod', 'nil', 'not', 'object', 'of', 'or', 'out', 'packed',
    'procedure', 'program', 'property', 'raise', 'record', 'repeat',
    'resourcestring', 'set', 'shl', 'shr', 'string', 'then', 'threadvar',
    'to', 'try', 'type', 'unit', 'until', 'uses', 'var', 'while',
    'with', 'xor'
  );
var
  LLower: string;
  LKeyword: string;
begin
  Result := AName;
  LLower := LowerCase(AName);
  for LKeyword in CDelphiKeywords do
  begin
    if LLower = LKeyword then
    begin
      Result := AName + '_';
      Exit;
    end;
  end;
end;

function TCImporter.IsAllowedSourceFile(): Boolean;
var
  LPath: string;
  LNormalizedCurrent: string;
  LNormalizedAllowed: string;
  LFilterPaths: TList<string>;
begin
  // Use source paths if specified, otherwise fall back to include paths
  if FSourcePaths.Count > 0 then
    LFilterPaths := FSourcePaths
  else
    LFilterPaths := FIncludePaths;

  // If no filter paths specified, allow all
  if LFilterPaths.Count = 0 then
    Exit(True);

  // If no current source file tracked, allow (safety)
  if FCurrentSourceFile = '' then
    Exit(True);

  // Normalize current file path (forward slashes, lowercase)
  LNormalizedCurrent := LowerCase(FCurrentSourceFile.Replace('\', '/'));

  // Check if current file is under any allowed path
  for LPath in LFilterPaths do
  begin
    LNormalizedAllowed := LowerCase(LPath.Replace('\', '/'));
    // Ensure path ends with /
    if not LNormalizedAllowed.EndsWith('/') then
      LNormalizedAllowed := LNormalizedAllowed + '/';

    if LNormalizedCurrent.Contains(LNormalizedAllowed) then
      Exit(True);
  end;

  // File is from other headers, skip it
  Result := False;
end;

function TCImporter.HasStructDefinition(const AName: string): Boolean;
var
  LI: Integer;
begin
  for LI := 0 to FStructs.Count - 1 do
  begin
    if FStructs[LI].StructName = AName then
      Exit(True);
  end;
  Result := False;
end;

function TCImporter.HasTypeNameCollision(const AName: string): Boolean;
var
  LI: Integer;
begin
  // A function name that matches any emitted type identifier (struct,
  // typedef alias, or enum name) is legal in C but a duplicate
  // identifier in Delphi.
  if HasStructDefinition(AName) then
    Exit(True);

  for LI := 0 to FTypedefs.Count - 1 do
  begin
    if FTypedefs[LI].AliasName = AName then
      Exit(True);
  end;

  for LI := 0 to FEnums.Count - 1 do
  begin
    if FEnums[LI].EnumName = AName then
      Exit(True);
  end;

  Result := False;
end;

function TCImporter.TypedefReferencesExcludedType(const ATypedef: TCTypedefInfo): Boolean;
var
  LI: Integer;
begin
  // Check alias name
  if FExcludedTypes.Contains(ATypedef.AliasName) then
    Exit(True);

  // Check target type
  if FExcludedTypes.Contains(ATypedef.TargetType) then
    Exit(True);

  // For function pointers, check return type and all parameter types
  if ATypedef.IsFunctionPointer then
  begin
    if FExcludedTypes.Contains(ATypedef.FuncInfo.ReturnType) then
      Exit(True);

    for LI := 0 to High(ATypedef.FuncInfo.Params) do
    begin
      if FExcludedTypes.Contains(ATypedef.FuncInfo.Params[LI].TypeName) then
        Exit(True);
    end;
  end;

  Result := False;
end;

procedure TCImporter.GenerateModule();
begin
  FOutput.Clear();

  // === Unit declaration + interface keyword (shared by all modes) ===
  EmitFmt('unit %s;', [FModuleName]);
  EmitLn();
  EmitLn('interface');
  EmitLn();

  // Dispatch to mode-specific generation
  if FBindingMode = bmStatic then
    GenerateModuleStatic()
  else if FBindingMode = bmDynamic then
    GenerateModuleDynamic()
  else if FBindingMode = bmDynamicDelayed then
    GenerateModuleDynamicDelayed()
  else if FBindingMode = bmDynamicCustom then
    GenerateModuleDynamicCustom()
  else if FBindingMode = bmStaticVpk then
    GenerateModuleStaticVpk();
end;

procedure TCImporter.GenerateInterfaceCommon();
begin
  // Common pointer helper types not declared in Delphi
  EmitLn('type');
  Inc(FIndent);
  EmitLn('PPUTF8Char = ^PUTF8Char;');
  EmitLn('PInt8 = ^Int8;');
  EmitLn('PUInt8 = ^UInt8;');
  EmitLn('PPUInt8 = ^PUInt8;');
  EmitLn('PInt16 = ^Int16;');
  EmitLn('PUInt16 = ^UInt16;');
  EmitLn('PInt32 = ^Int32;');
  EmitLn('PUInt32 = ^UInt32;');
  Dec(FIndent);
  EmitLn();

  // Emit interface content via sub-generators
  GenerateSimpleConstants();
  GenerateForwardDecls();
  GenerateAllTypes();
  GenerateTypedConstants();
end;

procedure TCImporter.GenerateModuleStatic();
var
  LI: Integer;
  LId: string;
begin
  // === INTERFACE uses clause ===
  EmitLn('uses');
  Inc(FIndent);
  if FUsesUnits.Count > 0 then
  begin
    EmitLn('WinApi.Windows,');
    for LI := 0 to FUsesUnits.Count - 2 do
      EmitFmt('%s,', [FUsesUnits[LI]]);
    EmitFmt('%s;', [FUsesUnits[FUsesUnits.Count - 1]]);
  end
  else
    EmitLn('WinApi.Windows;');
  Dec(FIndent);
  EmitLn();

  GenerateInterfaceCommon();
  GenerateFunctions();

  // === IMPLEMENTATION SECTION ===
  EmitLn('implementation');
  EmitLn();
  EmitLn('uses');
  Inc(FIndent);
  EmitLn('StdApp.DllLoader;');
  Dec(FIndent);
  EmitLn();

  EmitFmt('{$R %s.res}', [FModuleName]);
  EmitLn();
  EmitLn();

  EmitLn('const');
  Inc(FIndent);
  if FDllNameMap.Count > 0 then
  begin
    for LI := 0 to FDllNameMap.Count - 1 do
    begin
      LId := DllNameToIdentifier(FDllNameMap[LI].DllName);
      EmitFmt('CDll%s = ''%s'';', [LId, FDllNameMap[LI].DllName]);
      EmitFmt('CRes%s = ''%s'';', [LId, FDllNameMap[LI].ResName]);
    end;
    for LI := 0 to FDepDlls.Count - 1 do
    begin
      LId := DllNameToIdentifier(FDepDlls[LI].DllName);
      EmitFmt('CDepDll%s = ''%s'';', [LId, FDepDlls[LI].DllName]);
      EmitFmt('CDepRes%s = ''%s'';', [LId, FDepDlls[LI].ResName]);
    end;
  end
  else
  begin
    EmitFmt('CDllName = ''%s'';', [FDllName]);
    EmitFmt('CResName = ''%s'';', [FResName]);
  end;
  Dec(FIndent);
  EmitLn();

  EmitLn('var');
  Inc(FIndent);
  if FDllNameMap.Count > 0 then
  begin
    for LI := 0 to FDllNameMap.Count - 1 do
    begin
      LId := DllNameToIdentifier(FDllNameMap[LI].DllName);
      EmitFmt('GDllHandle%s: THandle = 0;', [LId]);
    end;
  end
  else
    EmitLn('GDllHandle: THandle = 0;');
  Dec(FIndent);
  EmitLn();

  GenerateBindExports();
  GenerateUnbindExports();

  EmitLn('initialization');
  Inc(FIndent);
  EmitLn('BindExports();');
  Dec(FIndent);
  EmitLn();
  EmitLn('finalization');
  Inc(FIndent);
  EmitLn('UnbindExports();');
  Dec(FIndent);
  EmitLn();
  EmitLn('end.');
end;

procedure TCImporter.GenerateModuleDynamic();
var
  LI: Integer;
begin
  // === INTERFACE uses clause ===
  EmitLn('uses');
  Inc(FIndent);
  if FUsesUnits.Count > 0 then
  begin
    EmitLn('WinApi.Windows,');
    for LI := 0 to FUsesUnits.Count - 2 do
      EmitFmt('%s,', [FUsesUnits[LI]]);
    EmitFmt('%s;', [FUsesUnits[FUsesUnits.Count - 1]]);
  end
  else
    EmitLn('WinApi.Windows;');
  Dec(FIndent);
  EmitLn();

  GenerateInterfaceCommon();
  GenerateFunctionsExternal(False);

  // === IMPLEMENTATION SECTION (empty) ===
  EmitLn('implementation');
  EmitLn();
  EmitLn('end.');
end;

procedure TCImporter.GenerateModuleDynamicDelayed();
var
  LI: Integer;
begin
  // === INTERFACE uses clause ===
  EmitLn('uses');
  Inc(FIndent);
  if FUsesUnits.Count > 0 then
  begin
    EmitLn('WinApi.Windows,');
    for LI := 0 to FUsesUnits.Count - 2 do
      EmitFmt('%s,', [FUsesUnits[LI]]);
    EmitFmt('%s;', [FUsesUnits[FUsesUnits.Count - 1]]);
  end
  else
    EmitLn('WinApi.Windows;');
  Dec(FIndent);
  EmitLn();

  GenerateInterfaceCommon();
  EmitLn('{$WARN SYMBOL_PLATFORM OFF}');
  GenerateFunctionsExternal(True);

  // === IMPLEMENTATION SECTION (empty) ===
  EmitLn('implementation');
  EmitLn();
  EmitLn('end.');
end;

procedure TCImporter.GenerateModuleDynamicCustom();
var
  LI: Integer;
  LId: string;
  LEntry: TDllMapEntry;
  LSignature: string;
begin
  // === INTERFACE uses clause ===
  EmitLn('uses');
  Inc(FIndent);
  if FUsesUnits.Count > 0 then
  begin
    EmitLn('WinApi.Windows,');
    for LI := 0 to FUsesUnits.Count - 2 do
      EmitFmt('%s,', [FUsesUnits[LI]]);
    EmitFmt('%s;', [FUsesUnits[FUsesUnits.Count - 1]]);
  end
  else
    EmitLn('WinApi.Windows;');
  Dec(FIndent);
  EmitLn();

  GenerateInterfaceCommon();
  GenerateFunctions();

  // Public bind/unbind declarations in interface
  if FDllNameMap.Count > 1 then
  begin
    // Multi-DLL: separate BindExports/UnbindExports per DLL
    for LI := 0 to FDllNameMap.Count - 1 do
    begin
      LId := DllNameToIdentifier(FDllNameMap[LI].DllName);
      EmitFmt('procedure BindExports%s(const AHandle: THandle);', [LId]);
      EmitFmt('procedure UnbindExports%s();', [LId]);
    end;
  end
  else if FDllNameMap.Count = 1 then
  begin
    LId := DllNameToIdentifier(FDllNameMap[0].DllName);
    EmitFmt('procedure BindExports(const AHandle%s: THandle);', [LId]);
    EmitLn('procedure UnbindExports();');
  end
  else
  begin
    EmitLn('procedure BindExports(const AHandle: THandle);');
    EmitLn('procedure UnbindExports();');
  end;
  EmitLn();

  // === IMPLEMENTATION SECTION ===
  EmitLn('implementation');
  EmitLn();

  EmitLn('var');
  Inc(FIndent);
  if FDllNameMap.Count > 0 then
  begin
    for LEntry in FDllNameMap do
    begin
      LId := DllNameToIdentifier(LEntry.DllName);
      EmitFmt('GDllHandle%s: THandle = 0;', [LId]);
    end;
  end
  else
    EmitLn('GDllHandle: THandle = 0;');
  Dec(FIndent);
  EmitLn();

  GenerateDlmBindExportsCustom();
  GenerateDlmUnbindExportsCustom();

  EmitLn('end.');
end;

procedure TCImporter.GenerateModuleStaticVpk();
var
  LI: Integer;
  LId: string;
  LEntry: TDllMapEntry;
begin
  // === INTERFACE uses clause (includes StdApp units) ===
  EmitLn('uses');
  Inc(FIndent);
  EmitLn('WinApi.Windows,');
  if FUsesUnits.Count > 0 then
  begin
    for LI := 0 to FUsesUnits.Count - 1 do
      EmitFmt('%s,', [FUsesUnits[LI]]);
  end;
  EmitLn('StdApp.DllLoader,');
  EmitLn('StdApp.VFS;');
  Dec(FIndent);
  EmitLn();

  GenerateInterfaceCommon();
  GenerateFunctions();

  // Public bind/unbind declarations in interface
  EmitLn('procedure BindExports(const AVFS: TVFS; const AFilename: string);');
  EmitLn('procedure UnbindExports();');
  EmitLn();

  // === IMPLEMENTATION SECTION ===
  EmitLn('implementation');
  EmitLn();
  EmitLn('uses');
  Inc(FIndent);
  EmitLn('StdApp.DllLoader;');
  Dec(FIndent);
  EmitLn();

  if FDllNameMap.Count > 0 then
  begin
    EmitLn('const');
    Inc(FIndent);
    for LEntry in FDllNameMap do
    begin
      LId := DllNameToIdentifier(LEntry.DllName);
      EmitFmt('CDll%s = ''%s'';', [LId, LEntry.DllName]);
    end;
    Dec(FIndent);
    EmitLn();
  end;

  EmitLn('var');
  Inc(FIndent);
  if FDllNameMap.Count > 0 then
  begin
    for LEntry in FDllNameMap do
    begin
      LId := DllNameToIdentifier(LEntry.DllName);
      EmitFmt('GDllHandle%s: THandle = 0;', [LId]);
    end;
  end
  else
    EmitLn('GDllHandle: THandle = 0;');
  Dec(FIndent);
  EmitLn();

  GenerateDlmBindExportsVpk();
  GenerateDlmUnbindExportsVpk();

  EmitLn('end.');
end;

procedure TCImporter.GenerateForwardDecls();
var
  LName: string;
  LSanitized: string;
begin
  if FForwardDecls.Count = 0 then
    Exit;

  EmitLn('type');
  Inc(FIndent);
  EmitLn('{ Forward declarations (opaque types) }');
  for LName in FForwardDecls do
  begin
    LSanitized := SanitizeIdentifier(LName);
    EmitFmt('P%s = ^%s;', [LSanitized, LSanitized]);
    EmitFmt('PP%s = ^P%s;', [LSanitized, LSanitized]);
    EmitFmt('%s = record end;', [LSanitized]);
  end;
  Dec(FIndent);
  EmitLn();
end;

procedure TCImporter.GenerateAllTypes();
var
  LEnum: TCEnumInfo;
  LTypedef: TCTypedefInfo;
  LField: TCFieldInfo;
  LValue: TCEnumValue;
  LFieldType: string;
  LTargetType: string;
  LI: Integer;
  LJ: Integer;
  LHasTypes: Boolean;
  LParamStr: string;
  LParam: TCParamInfo;
  LParamType: string;
  LParamName: string;
  LReturnType: string;
  LCurrentValue: Int64;
  LKnown: TDictionary<string, Boolean>;
  LStructEmitted: array of Boolean;
  LTypedefEmitted: array of Boolean;
  LProgress: Boolean;
  LAllMet: Boolean;
  LDep: string;
begin
  LHasTypes := (FStructs.Count > 0) or (FEnums.Count > 0) or (FTypedefs.Count > 0);
  if not LHasTypes then
    Exit;

  // 1. Emit enum type aliases
  if FEnums.Count > 0 then
  begin
    EmitLn('type');
    Inc(FIndent);
    for LEnum in FEnums do
    begin
      EmitFmt('%s = Cardinal;', [SanitizeIdentifier(LEnum.EnumName)]);
      EmitFmt('P%s = ^%s;', [SanitizeIdentifier(LEnum.EnumName),
        SanitizeIdentifier(LEnum.EnumName)]);
    end;
    Dec(FIndent);
    EmitLn();

    // 2. Emit enum value const groups
    EmitLn('const');
    Inc(FIndent);
    for LEnum in FEnums do
    begin
      EmitFmt('{ %s }', [LEnum.EnumName]);
      LCurrentValue := 0;
      for LI := 0 to High(LEnum.Values) do
      begin
        LValue := LEnum.Values[LI];
        if LValue.HasExplicitValue then
          LCurrentValue := LValue.Value;
        EmitFmt('%s = %d;', [SanitizeIdentifier(LValue.ValueName), LCurrentValue]);
        Inc(LCurrentValue);
      end;
      EmitLn();
    end;
    Dec(FIndent);
  end;

  // 3. Emit structs, type aliases, and function pointer types
  //    Uses multi-pass dependency ordering to ensure types are declared
  //    before they are referenced as value types.
  EmitLn('type');
  Inc(FIndent);

  // Pre-declare all pointer types for structs for forward reference resolution
  // This allows any type to reference P/PP pointer types freely
  for LI := 0 to FStructs.Count - 1 do
  begin
    EmitFmt('P%s = ^%s;', [SanitizeIdentifier(FStructs[LI].StructName),
      SanitizeIdentifier(FStructs[LI].StructName)]);
    EmitFmt('PP%s = ^P%s;', [SanitizeIdentifier(FStructs[LI].StructName),
      SanitizeIdentifier(FStructs[LI].StructName)]);
  end;
  EmitLn();

  // Build known type set (forward decls + enum names are already emitted)
  LKnown := TDictionary<string, Boolean>.Create();
  try
    for LI := 0 to FForwardDecls.Count - 1 do
      LKnown.AddOrSetValue(FForwardDecls[LI], True);
    for LEnum in FEnums do
      LKnown.AddOrSetValue(LEnum.EnumName, True);

    // Seed with built-in C types so they don't block dependency resolution
    LKnown.AddOrSetValue('void', True);
    LKnown.AddOrSetValue('char', True);
    LKnown.AddOrSetValue('short', True);
    LKnown.AddOrSetValue('int', True);
    LKnown.AddOrSetValue('long', True);
    LKnown.AddOrSetValue('long long', True);
    LKnown.AddOrSetValue('float', True);
    LKnown.AddOrSetValue('double', True);
    LKnown.AddOrSetValue('long double', True);
    LKnown.AddOrSetValue('_Bool', True);
    LKnown.AddOrSetValue('signed char', True);
    LKnown.AddOrSetValue('unsigned char', True);
    LKnown.AddOrSetValue('unsigned short', True);
    LKnown.AddOrSetValue('unsigned int', True);
    LKnown.AddOrSetValue('unsigned long', True);
    LKnown.AddOrSetValue('unsigned long long', True);
    LKnown.AddOrSetValue('size_t', True);
    LKnown.AddOrSetValue('int8_t', True);
    LKnown.AddOrSetValue('uint8_t', True);
    LKnown.AddOrSetValue('int16_t', True);
    LKnown.AddOrSetValue('uint16_t', True);
    LKnown.AddOrSetValue('int32_t', True);
    LKnown.AddOrSetValue('uint32_t', True);
    LKnown.AddOrSetValue('int64_t', True);
    LKnown.AddOrSetValue('uint64_t', True);
    LKnown.AddOrSetValue('intptr_t', True);
    LKnown.AddOrSetValue('uintptr_t', True);
    LKnown.AddOrSetValue('ptrdiff_t', True);
    LKnown.AddOrSetValue('wchar_t', True);

    // Initialize emission tracking
    SetLength(LStructEmitted, FStructs.Count);
    SetLength(LTypedefEmitted, FTypedefs.Count);
    for LI := 0 to High(LStructEmitted) do
      LStructEmitted[LI] := False;
    for LI := 0 to High(LTypedefEmitted) do
      LTypedefEmitted[LI] := False;

    // Multi-pass: emit types whose dependencies are all satisfied
    repeat
      LProgress := False;

      // Try each struct
      for LI := 0 to FStructs.Count - 1 do
      begin
        if LStructEmitted[LI] then
          Continue;

        // Check if all value-type field dependencies are known
        LAllMet := True;
        for LJ := 0 to High(FStructs[LI].Fields) do
        begin
          LField := FStructs[LI].Fields[LJ];
          if LField.IsPointer or (LField.PointerDepth > 0) then
            Continue;
          LDep := LField.TypeName;
          if (LDep <> '') and not LKnown.ContainsKey(LDep) then
          begin
            LAllMet := False;
            Break;
          end;
        end;

        if not LAllMet then
          Continue;

        // Emit this struct
        if FStructs[LI].IsUnion then
        begin
          EmitFmt('%s = record', [SanitizeIdentifier(FStructs[LI].StructName)]);
          Inc(FIndent);
          EmitLn('case Integer of');
          Inc(FIndent);
          for LJ := 0 to High(FStructs[LI].Fields) do
          begin
            LField := FStructs[LI].Fields[LJ];
            LFieldType := MapCTypeToDelphi(ResolveTypedefAlias(LField.TypeName),
              LField.IsPointer, LField.PointerDepth);
            if LField.ArraySize > 0 then
              EmitFmt('%d: (%s: array[0..%d] of %s);', [LJ,
                SanitizeIdentifier(LField.FieldName), LField.ArraySize - 1, LFieldType])
            else
              EmitFmt('%d: (%s: %s);', [LJ, SanitizeIdentifier(LField.FieldName), LFieldType]);
          end;
          Dec(FIndent);
          Dec(FIndent);
        end
        else
        begin
          EmitFmt('%s = record', [SanitizeIdentifier(FStructs[LI].StructName)]);
          Inc(FIndent);
          for LJ := 0 to High(FStructs[LI].Fields) do
          begin
            LField := FStructs[LI].Fields[LJ];
            LFieldType := MapCTypeToDelphi(ResolveTypedefAlias(LField.TypeName),
              LField.IsPointer, LField.PointerDepth);
            if LField.ArraySize > 0 then
              EmitFmt('%s: array[0..%d] of %s;', [SanitizeIdentifier(LField.FieldName),
                LField.ArraySize - 1, LFieldType])
            else if LField.BitWidth > 0 then
              EmitFmt('%s: %s; { bitwidth: %d }', [SanitizeIdentifier(LField.FieldName),
                LFieldType, LField.BitWidth])
            else
              EmitFmt('%s: %s;', [SanitizeIdentifier(LField.FieldName), LFieldType]);
          end;
          Dec(FIndent);
        end;
        EmitLn('end;');
        EmitLn();

        LKnown.AddOrSetValue(FStructs[LI].StructName, True);
        LStructEmitted[LI] := True;
        LProgress := True;
      end;

      // Try each typedef (both function pointers and simple aliases)
      for LI := 0 to FTypedefs.Count - 1 do
      begin
        if LTypedefEmitted[LI] then
          Continue;
        // Skip duplicate typedefs (same alias already emitted from another header)
        if LKnown.ContainsKey(FTypedefs[LI].AliasName) then
        begin
          LTypedefEmitted[LI] := True;
          Continue;
        end;
        if TypedefReferencesExcludedType(FTypedefs[LI]) then
        begin
          LTypedefEmitted[LI] := True;
          Continue;
        end;

        LTypedef := FTypedefs[LI];
        LAllMet := True;

        if LTypedef.IsFunctionPointer then
        begin
          // Check param value-type dependencies
          for LJ := 0 to High(LTypedef.FuncInfo.Params) do
          begin
            LParam := LTypedef.FuncInfo.Params[LJ];
            if LParam.IsPointer then
              Continue;
            LDep := LParam.TypeName;
            if (LDep <> '') and (LDep <> 'void') and not LKnown.ContainsKey(LDep) then
            begin
              LAllMet := False;
              Break;
            end;
          end;
          // Check return type
          if LAllMet and not LTypedef.FuncInfo.ReturnIsPointer then
          begin
            LDep := LTypedef.FuncInfo.ReturnType;
            if (LDep <> '') and (LDep <> 'void') and not LKnown.ContainsKey(LDep) then
              LAllMet := False;
          end;
        end
        else
        begin
          // Simple typedef: check target type dependency
          if not LTypedef.IsPointer and (LTypedef.PointerDepth = 0) then
          begin
            LDep := LTypedef.TargetType;
            if (LDep <> '') and not LKnown.ContainsKey(LDep) then
              LAllMet := False;
          end;
        end;

        if not LAllMet then
          Continue;

        // Emit this typedef
        if LTypedef.IsFunctionPointer then
        begin
          LParamStr := '';
          for LJ := 0 to High(LTypedef.FuncInfo.Params) do
          begin
            LParam := LTypedef.FuncInfo.Params[LJ];
            LParamType := MapCTypeToDelphi(LParam.TypeName, LParam.IsPointer,
              LParam.PointerDepth, LParam.IsConstTarget);
            if LParam.ParamName <> '' then
              LParamName := 'A' + LParam.ParamName
            else
              LParamName := Format('AParam%d', [LJ]);
            if LJ > 0 then
              LParamStr := LParamStr + '; ';
            LParamStr := LParamStr + Format('const %s: %s',
              [SanitizeIdentifier(LParamName), LParamType]);
          end;

          if (LTypedef.FuncInfo.ReturnType = 'void') and
             not LTypedef.FuncInfo.ReturnIsPointer then
            EmitFmt('%s = procedure(%s); cdecl;',
              [SanitizeIdentifier(LTypedef.AliasName), LParamStr])
          else
          begin
            LReturnType := MapCTypeToDelphi(LTypedef.FuncInfo.ReturnType,
              LTypedef.FuncInfo.ReturnIsPointer, LTypedef.FuncInfo.ReturnPointerDepth);
            EmitFmt('%s = function(%s): %s; cdecl;',
              [SanitizeIdentifier(LTypedef.AliasName), LParamStr, LReturnType]);
          end;
          EmitFmt('P%s = ^%s;', [SanitizeIdentifier(LTypedef.AliasName),
            SanitizeIdentifier(LTypedef.AliasName)]);
        end
        else
        begin
          LTargetType := MapCTypeToDelphi(LTypedef.TargetType, LTypedef.IsPointer,
            LTypedef.PointerDepth);

          // Skip redundant aliases where both map to the same type
          if MapCTypeToDelphi(LTypedef.AliasName, False, 0) <> LTargetType then
          begin
            EmitFmt('%s = %s;', [SanitizeIdentifier(LTypedef.AliasName), LTargetType]);
            EmitFmt('P%s = ^%s;', [SanitizeIdentifier(LTypedef.AliasName),
              SanitizeIdentifier(LTypedef.AliasName)]);
          end;
        end;

        LKnown.AddOrSetValue(LTypedef.AliasName, True);
        LTypedefEmitted[LI] := True;
        LProgress := True;
      end;
    until not LProgress;

    // Emit any remaining types (circular deps or unresolvable deps)
    for LI := 0 to FStructs.Count - 1 do
    begin
      if LStructEmitted[LI] then
        Continue;

      if FStructs[LI].IsUnion then
      begin
        EmitFmt('%s = record', [SanitizeIdentifier(FStructs[LI].StructName)]);
        Inc(FIndent);
        EmitLn('case Integer of');
        Inc(FIndent);
        for LJ := 0 to High(FStructs[LI].Fields) do
        begin
          LField := FStructs[LI].Fields[LJ];
          LFieldType := MapCTypeToDelphi(ResolveTypedefAlias(LField.TypeName),
            LField.IsPointer, LField.PointerDepth);
          if LField.ArraySize > 0 then
            EmitFmt('%d: (%s: array[0..%d] of %s);', [LJ,
              SanitizeIdentifier(LField.FieldName), LField.ArraySize - 1, LFieldType])
          else
            EmitFmt('%d: (%s: %s);', [LJ, SanitizeIdentifier(LField.FieldName), LFieldType]);
        end;
        Dec(FIndent);
        Dec(FIndent);
      end
      else
      begin
        EmitFmt('%s = record', [SanitizeIdentifier(FStructs[LI].StructName)]);
        Inc(FIndent);
        for LJ := 0 to High(FStructs[LI].Fields) do
        begin
          LField := FStructs[LI].Fields[LJ];
          LFieldType := MapCTypeToDelphi(ResolveTypedefAlias(LField.TypeName),
            LField.IsPointer, LField.PointerDepth);
          if LField.ArraySize > 0 then
            EmitFmt('%s: array[0..%d] of %s;', [SanitizeIdentifier(LField.FieldName),
              LField.ArraySize - 1, LFieldType])
          else if LField.BitWidth > 0 then
            EmitFmt('%s: %s; { bitwidth: %d }', [SanitizeIdentifier(LField.FieldName),
              LFieldType, LField.BitWidth])
          else
            EmitFmt('%s: %s;', [SanitizeIdentifier(LField.FieldName), LFieldType]);
        end;
        Dec(FIndent);
      end;
      EmitLn('end;');
      EmitLn();
    end;

    for LI := 0 to FTypedefs.Count - 1 do
    begin
      if LTypedefEmitted[LI] then
        Continue;
      if TypedefReferencesExcludedType(FTypedefs[LI]) then
        Continue;

      LTypedef := FTypedefs[LI];

      if LTypedef.IsFunctionPointer then
      begin
        LParamStr := '';
        for LJ := 0 to High(LTypedef.FuncInfo.Params) do
        begin
          LParam := LTypedef.FuncInfo.Params[LJ];
          LParamType := MapCTypeToDelphi(LParam.TypeName, LParam.IsPointer,
            LParam.PointerDepth, LParam.IsConstTarget);
          if LParam.ParamName <> '' then
            LParamName := 'A' + LParam.ParamName
          else
            LParamName := Format('AParam%d', [LJ]);
          if LJ > 0 then
            LParamStr := LParamStr + '; ';
          LParamStr := LParamStr + Format('const %s: %s',
            [SanitizeIdentifier(LParamName), LParamType]);
        end;

        if (LTypedef.FuncInfo.ReturnType = 'void') and
           not LTypedef.FuncInfo.ReturnIsPointer then
          EmitFmt('%s = procedure(%s); cdecl;',
            [SanitizeIdentifier(LTypedef.AliasName), LParamStr])
        else
        begin
          LReturnType := MapCTypeToDelphi(LTypedef.FuncInfo.ReturnType,
            LTypedef.FuncInfo.ReturnIsPointer, LTypedef.FuncInfo.ReturnPointerDepth);
          EmitFmt('%s = function(%s): %s; cdecl;',
            [SanitizeIdentifier(LTypedef.AliasName), LParamStr, LReturnType]);
        end;
        EmitFmt('P%s = ^%s;', [SanitizeIdentifier(LTypedef.AliasName),
          SanitizeIdentifier(LTypedef.AliasName)]);
      end
      else
      begin
        LTargetType := MapCTypeToDelphi(LTypedef.TargetType, LTypedef.IsPointer,
          LTypedef.PointerDepth);
        if MapCTypeToDelphi(LTypedef.AliasName, False, 0) <> LTargetType then
        begin
          EmitFmt('%s = %s;', [SanitizeIdentifier(LTypedef.AliasName), LTargetType]);
          EmitFmt('P%s = ^%s;', [SanitizeIdentifier(LTypedef.AliasName),
            SanitizeIdentifier(LTypedef.AliasName)]);
        end;
      end;
    end;
    EmitLn();

  finally
    LKnown.Free();
  end;

  Dec(FIndent);
  EmitLn();
end;

procedure TCImporter.GenerateFunctions();
var
  LFunc: TCFunctionInfo;
  LParam: TCParamInfo;
  LReturnType: string;
  LParamStr: string;
  LI: Integer;
  LParamType: string;
  LParamName: string;
  LSkip: Boolean;
begin
  if FFunctions.Count = 0 then
    Exit;

  EmitLn('var');
  Inc(FIndent);

  for LFunc in FFunctions do
  begin
    if FExcludedFunctions.Contains(LFunc.FuncName) then
      Continue;
    if FunctionReferencesExcludedType(LFunc) then
      Continue;

    // Skip malformed functions (parsing errors)
    if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
      Continue;
    if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
      Continue;

    LSkip := False;
    for LI := 0 to High(LFunc.Params) do
    begin
      if LFunc.Params[LI].TypeName = '' then
      begin
        LSkip := True;
        Break;
      end;
      if (Length(LFunc.Params[LI].TypeName) = 1) and
         CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
      begin
        LSkip := True;
        Break;
      end;
    end;
    if LSkip then
      Continue;

    LParamStr := '';
    for LI := 0 to High(LFunc.Params) do
    begin
      LParam := LFunc.Params[LI];
      LParamType := MapCTypeToDelphi(LParam.TypeName, LParam.IsPointer,
        LParam.PointerDepth, LParam.IsConstTarget);
      if LParam.ParamName <> '' then
        LParamName := 'A' + LParam.ParamName
      else
        LParamName := Format('AParam%d', [LI]);
      if LI > 0 then
        LParamStr := LParamStr + '; ';
      LParamStr := LParamStr + Format('const %s: %s',
        [SanitizeIdentifier(LParamName), LParamType]);
    end;

    if (LFunc.ReturnType = 'void') and not LFunc.ReturnIsPointer then
      EmitFmt('%s: procedure(%s); cdecl;', [GetDelphiFuncName(LFunc.FuncName), LParamStr])
    else
    begin
      LReturnType := MapCTypeToDelphi(LFunc.ReturnType, LFunc.ReturnIsPointer,
        LFunc.ReturnPointerDepth);
      EmitFmt('%s: function(%s): %s; cdecl;', [GetDelphiFuncName(LFunc.FuncName),
        LParamStr, LReturnType]);
    end;
  end;

  Dec(FIndent);
  EmitLn();
end;

procedure TCImporter.GenerateSimpleConstants();
var
  LDefine: TCDefineInfo;
  LHasConstants: Boolean;
begin
  LHasConstants := False;
  for LDefine in FDefines do
  begin
    // Skip excluded constants when checking
    if FExcludedTypes.Contains(LDefine.DefineName) then
      Continue;

    if LDefine.IsInteger or LDefine.IsFloat or LDefine.IsString then
    begin
      LHasConstants := True;
      Break;
    end;
  end;

  if not LHasConstants then
    Exit;

  EmitLn('const');
  Inc(FIndent);
  EmitLn('{ Constants from #define }');

  for LDefine in FDefines do
  begin
    // Skip excluded constants (e.g., stdint.h macros)
    if FExcludedTypes.Contains(LDefine.DefineName) then
      Continue;

    if LDefine.IsInteger then
      EmitFmt('%s = %d;', [SanitizeIdentifier(LDefine.DefineName), LDefine.IntValue])
    else if LDefine.IsFloat then
      EmitFmt('%s = %s;', [SanitizeIdentifier(LDefine.DefineName), FloatToStr(LDefine.FloatValue)])
    else if LDefine.IsString then
      EmitFmt('%s = ''%s'';', [SanitizeIdentifier(LDefine.DefineName), LDefine.StringValue.Replace('''', '''''')]);
  end;

  Dec(FIndent);
  EmitLn();
end;

procedure TCImporter.GenerateTypedConstants();
var
  LDefine: TCDefineInfo;
  LHasTypedConstants: Boolean;
  LStruct: TCStructInfo;
  LValues: TArray<string>;
  LFieldInits: string;
  LStructFound: Boolean;
  LI: Integer;
begin
  LHasTypedConstants := False;
  for LDefine in FDefines do
  begin
    if FExcludedTypes.Contains(LDefine.DefineName) then
      Continue;

    if LDefine.IsTypedConstant then
    begin
      LHasTypedConstants := True;
      Break;
    end;
  end;

  if not LHasTypedConstants then
    Exit;

  EmitLn('const');
  Inc(FIndent);
  EmitLn('{ Typed constants from compound literals }');

  for LDefine in FDefines do
  begin
    if FExcludedTypes.Contains(LDefine.DefineName) then
      Continue;

    if LDefine.IsTypedConstant then
    begin
      // Look up struct to get field names for Delphi record constant syntax
      LStructFound := False;
      for LStruct in FStructs do
      begin
        if LStruct.StructName = LDefine.TypedConstType then
        begin
          LStructFound := True;
          Break;
        end;
      end;

      if LStructFound then
      begin
        // Split values and pair with field names: (field1: val1; field2: val2)
        LValues := LDefine.TypedConstValues.Split([',']);
        LFieldInits := '';
        for LI := 0 to High(LValues) do
        begin
          if LI > High(LStruct.Fields) then
            Break;
          if LI > 0 then
            LFieldInits := LFieldInits + '; ';
          LFieldInits := LFieldInits + LStruct.Fields[LI].FieldName + ': ' + LValues[LI].Trim();
        end;
        EmitFmt('%s: %s = (%s);', [
          SanitizeIdentifier(LDefine.DefineName),
          SanitizeIdentifier(LDefine.TypedConstType),
          LFieldInits
        ]);
      end
      else
      begin
        // Fallback — no struct found, emit positional
        EmitFmt('%s: %s = (%s);', [
          SanitizeIdentifier(LDefine.DefineName),
          SanitizeIdentifier(LDefine.TypedConstType),
          LDefine.TypedConstValues
        ]);
      end;
    end;
  end;

  Dec(FIndent);
  EmitLn();
end;

procedure TCImporter.ParseDefines(const APreprocessedSource: string);
var
  LLines: TArray<string>;
  LLine: string;
  LTrimmed: string;
  LDefineInfo: TCDefineInfo;
  LSpacePos: Integer;
  LValue: string;
  LIntVal: Int64;
  LFloatVal: Double;
  LQuoteStart: Integer;
  LQuoteEnd: Integer;
  LParenPos: Integer;
  LBracePos: Integer;
  LPrefix: string;
  LBraceEnd: Integer;
  LTypeStart: Integer;
  LTypeName: string;
  LValues: string;
  LCastEnd: Integer;
  LInnerValue: string;
begin
  // Parse #define directives from preprocessed source
  // Format: #define NAME value
  LLines := APreprocessedSource.Split([#10]);
  for LLine in LLines do
  begin
    LTrimmed := LLine.Trim();

    // Check for line marker to track current source file
    // Format: # linenum "filename" [flags]
    if (Length(LTrimmed) > 2) and (LTrimmed[1] = '#') and (LTrimmed[2] = ' ') and
       CharInSet(LTrimmed[3], ['0'..'9']) then
    begin
      LQuoteStart := Pos('"', LTrimmed);
      if LQuoteStart > 0 then
      begin
        LQuoteEnd := Pos('"', LTrimmed, LQuoteStart + 1);
        if LQuoteEnd > LQuoteStart then
          FCurrentSourceFile := Copy(LTrimmed, LQuoteStart + 1, LQuoteEnd - LQuoteStart - 1);
      end;
      Continue;
    end;

    // Skip if not a #define
    if not LTrimmed.StartsWith('#define ') then
      Continue;

    // Skip defines from non-allowed source files
    if not IsAllowedSourceFile() then
      Continue;

    // Extract name and value: "#define NAME value"
    LTrimmed := Copy(LTrimmed, 9, Length(LTrimmed)); // Skip "#define "
    LTrimmed := LTrimmed.TrimLeft();

    // Skip function-like macros (parenthesis immediately after name, before space)
    // Function-like: #define FOO(x) -> "FOO(x) ..."
    // Value with cast: #define FOO ((Type) val) -> "FOO ((Type) val)"
    LSpacePos := Pos(' ', LTrimmed);
    LParenPos := Pos('(', LTrimmed);
    if (LParenPos > 0) and ((LSpacePos = 0) or (LParenPos < LSpacePos)) then
      Continue;

    // Find space separating name from value (already found above)
    if LSpacePos = 0 then
      Continue; // No value, skip

    LDefineInfo.DefineName := Copy(LTrimmed, 1, LSpacePos - 1);
    LValue := Copy(LTrimmed, LSpacePos + 1, Length(LTrimmed)).Trim();
    LDefineInfo.DefineValue := LValue;

    // Skip empty values
    if LValue = '' then
      Continue;

    // Skip internal/system defines (start with underscore)
    if LDefineInfo.DefineName.StartsWith('_') then
      Continue;

    // Determine value type
    LDefineInfo.IsInteger := False;
    LDefineInfo.IsFloat := False;
    LDefineInfo.IsString := False;
    LDefineInfo.IsTypedConstant := False;
    LDefineInfo.IntValue := 0;
    LDefineInfo.FloatValue := 0;
    LDefineInfo.StringValue := '';
    LDefineInfo.TypedConstType := '';
    LDefineInfo.TypedConstValues := '';

    // Handle compound literals: IDENTIFIER(Type){ val1, val2, ... } or (Type){ val1, val2, ... }
    // Examples: CLITERAL(Color){ 200, 200, 200, 255 }, (Vector2){ 1.0f, 2.0f }
    LBracePos := Pos('{', LValue);
    if LBracePos > 1 then
    begin
      LPrefix := Copy(LValue, 1, LBracePos - 1).Trim();
      LBraceEnd := Pos('}', LValue);
      if (LBraceEnd > LBracePos) and LPrefix.EndsWith(')') then
      begin
        // Extract type name from IDENTIFIER(Type) or (Type)
        LTypeStart := Pos('(', LPrefix);
        if LTypeStart > 0 then
        begin
          LTypeName := Copy(LPrefix, LTypeStart + 1, Length(LPrefix) - LTypeStart - 1);
          // Extract values between { and }
          LValues := Copy(LValue, LBracePos + 1, LBraceEnd - LBracePos - 1).Trim();
          if (LTypeName <> '') and (LValues <> '') then
          begin
            LDefineInfo.IsTypedConstant := True;
            LDefineInfo.TypedConstType := LTypeName;
            LDefineInfo.TypedConstValues := LValues;
            FDefines.Add(LDefineInfo);
            Continue;
          end;
        end;
      end;
    end;

    // Handle C cast expressions: ((TypeName) value) or (TypeName) value
    // Examples: ((SDL_AudioDeviceID) 0xFFFFFFFFu), (int) 42
    if LValue.StartsWith('(') then
    begin
      // Find the closing paren of the cast type
      LCastEnd := Pos(')', LValue);
      if LCastEnd > 0 then
      begin
        // Extract everything after the cast
        LInnerValue := Copy(LValue, LCastEnd + 1, Length(LValue)).Trim();
        // Strip outer parens if present: ((Type) val) -> val)
        if LInnerValue.EndsWith(')') then
          LInnerValue := Copy(LInnerValue, 1, Length(LInnerValue) - 1).Trim();
        // Use extracted value for further parsing
        if LInnerValue <> '' then
          LValue := LInnerValue;
      end;
    end;

    // Handle integer literal wrapper macros: SDL_UINT64_C(0x...), UINT32_C(42), etc.
    // The preprocessor with -dD preserves these as-is; strip to extract the inner value
    if (Length(LValue) > 2) and CharInSet(LValue[1], ['A'..'Z', 'a'..'z', '_']) then
    begin
      LParenPos := Pos('(', LValue);
      if LParenPos > 1 then
      begin
        LCastEnd := Pos(')', LValue, LParenPos + 1);
        if (LCastEnd > LParenPos + 1) then
        begin
          LInnerValue := Copy(LValue, LParenPos + 1, LCastEnd - LParenPos - 1).Trim();
          if (LInnerValue <> '') and CharInSet(LInnerValue[1], ['0'..'9', '-']) then
            LValue := LInnerValue;
        end;
      end;
    end;

    // Check for hex integer
    if LValue.StartsWith('0x') or LValue.StartsWith('0X') then
    begin
      // Strip suffixes
      while (Length(LValue) > 0) and CharInSet(LValue[Length(LValue)], ['u', 'U', 'l', 'L']) do
        LValue := Copy(LValue, 1, Length(LValue) - 1);
      if TryStrToInt64('$' + Copy(LValue, 3, Length(LValue)), LIntVal) then
      begin
        LDefineInfo.IsInteger := True;
        LDefineInfo.IntValue := LIntVal;
      end;
    end
    // Check for decimal integer
    else if (Length(LValue) > 0) and (CharInSet(LValue[1], ['0'..'9', '-'])) then
    begin
      // Strip suffixes
      while (Length(LValue) > 0) and CharInSet(LValue[Length(LValue)], ['u', 'U', 'l', 'L', 'f', 'F']) do
        LValue := Copy(LValue, 1, Length(LValue) - 1);

      // Try integer first
      if TryStrToInt64(LValue, LIntVal) then
      begin
        LDefineInfo.IsInteger := True;
        LDefineInfo.IntValue := LIntVal;
      end
      // Try float
      else if TryStrToFloat(LValue, LFloatVal) then
      begin
        LDefineInfo.IsFloat := True;
        LDefineInfo.FloatValue := LFloatVal;
      end;
    end
    // Check for string literal
    else if LValue.StartsWith('"') and LValue.EndsWith('"') then
    begin
      LDefineInfo.IsString := True;
      LDefineInfo.StringValue := Copy(LValue, 2, Length(LValue) - 2);
    end;

    // Only add if we parsed a value
    if LDefineInfo.IsInteger or LDefineInfo.IsFloat or LDefineInfo.IsString then
      FDefines.Add(LDefineInfo);
  end;
end;

procedure TCImporter.ParsePreprocessed(const APreprocessedSource: string);
begin
  // Parse #define directives first (before tokenization strips them)
  ParseDefines(APreprocessedSource);

  FLexer.Tokenize(APreprocessedSource);
  FPos := 0;
  FCurrentToken := FLexer.GetToken(0);
  ParseTopLevel();
  GenerateModule();
  ProcessInsertions();
end;

procedure TCImporter.AddIncludePath(const APath: string; const AModuleName: string);
var
  LPath: string;
begin
  LPath := TPath.GetFullPath(APath).Replace('\', '/');
  if not FIncludePaths.Contains(LPath) then
    FIncludePaths.Add(LPath);
end;

procedure TCImporter.AddSourcePath(const APath: string);
var
  LPath: string;
begin
  LPath := TPath.GetFullPath(APath).Replace('\', '/');
  if not FSourcePaths.Contains(LPath) then
    FSourcePaths.Add(LPath);
end;

procedure TCImporter.AddExcludedType(const ATypeName: string);
begin
  if not FExcludedTypes.Contains(ATypeName) then
    FExcludedTypes.Add(ATypeName);
end;

procedure TCImporter.AddExcludedFunction(const AFuncName: string);
begin
  if not FExcludedFunctions.Contains(AFuncName) then
    FExcludedFunctions.Add(AFuncName);
end;

procedure TCImporter.AddFunctionRename(const AOriginalName: string; const ADelphiName: string);
begin
  FFunctionRenames.AddOrSetValue(AOriginalName, ADelphiName);
end;

procedure TCImporter.AddUsesUnit(const AUnitName: string);
begin
  if not FUsesUnits.Contains(AUnitName) then
    FUsesUnits.Add(AUnitName);
end;

procedure TCImporter.SetSavePreprocessed(const AValue: Boolean);
begin
  FSavePreprocessed := AValue;
end;

procedure TCImporter.InsertTextAfter(const ATargetLine: string; const AText: string; const AOccurrence: Integer);
var
  LInfo: TInsertionInfo;
begin
  LInfo.TargetLine := ATargetLine;
  LInfo.Content := AText;
  LInfo.InsertBefore := False;
  LInfo.Occurrence := AOccurrence;
  FInsertions.Add(LInfo);
end;

procedure TCImporter.InsertFileAfter(const ATargetLine: string; const AFilePath: string; const AOccurrence: Integer);
var
  LContent: string;
begin
  if TFile.Exists(AFilePath) then
  begin
    LContent := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
    InsertTextAfter(ATargetLine, LContent, AOccurrence);
  end;
end;

procedure TCImporter.InsertTextBefore(const ATargetLine: string; const AText: string; const AOccurrence: Integer);
var
  LInfo: TInsertionInfo;
begin
  LInfo.TargetLine := ATargetLine;
  LInfo.Content := AText;
  LInfo.InsertBefore := True;
  LInfo.Occurrence := AOccurrence;
  FInsertions.Add(LInfo);
end;

procedure TCImporter.InsertFileBefore(const ATargetLine: string; const AFilePath: string; const AOccurrence: Integer);
var
  LContent: string;
begin
  if TFile.Exists(AFilePath) then
  begin
    LContent := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
    InsertTextBefore(ATargetLine, LContent, AOccurrence);
  end;
end;

procedure TCImporter.ReplaceText(const AOldText: string; const ANewText: string; const AOccurrence: Integer);
var
  LInfo: TReplacementInfo;
begin
  LInfo.OldText := AOldText;
  LInfo.NewText := ANewText;
  LInfo.Occurrence := AOccurrence;
  FReplacements.Add(LInfo);
end;

procedure TCImporter.GenerateBindExports();
var
  LFunc: TCFunctionInfo;
  LI: Integer;
  LSkip: Boolean;
  LId: string;
  LHandleName: string;
  LEntry: TDllMapEntry;
  LDepEntry: TDepDllInfo;
begin
  if FFunctions.Count = 0 then
    Exit;

  EmitLn('procedure BindExports();');
  EmitLn('begin');
  Inc(FIndent);

  if FDllNameMap.Count > 0 then
  begin
    // Register dependency DLLs first
    for LDepEntry in FDepDlls do
    begin
      LId := DllNameToIdentifier(LDepEntry.DllName);
      EmitFmt('RegisterDllData(CDepDll%s, CDepRes%s);', [LId, LId]);
    end;

    // Register mapped DLLs
    for LEntry in FDllNameMap do
    begin
      LId := DllNameToIdentifier(LEntry.DllName);
      EmitFmt('RegisterDllData(CDll%s, CRes%s);', [LId, LId]);
    end;

    EmitLn();
    EmitLn('// Load all DLLs with dependency resolution');
    EmitLn('if not StdApp.DllLoader.LoadAll() then');
    Inc(FIndent);
    EmitLn('Exit;');
    Dec(FIndent);
    EmitLn();

    // Get handles for each mapped DLL
    for LEntry in FDllNameMap do
    begin
      LId := DllNameToIdentifier(LEntry.DllName);
      EmitFmt('GDllHandle%s := StdApp.DllLoader.LoadLibrary(CDll%s);', [LId, LId]);
    end;
    EmitLn();
  end
  else
  begin
    EmitLn('RegisterDllData(CDllName, CResName);');
    EmitLn('GDllHandle := StdApp.DllLoader.LoadLibrary(CDllName);');
    EmitLn('if GDllHandle = 0 then');
    Inc(FIndent);
    EmitLn('Exit;');
    Dec(FIndent);
  end;

  for LFunc in FFunctions do
  begin
    if FExcludedFunctions.Contains(LFunc.FuncName) then
      Continue;
    if FunctionReferencesExcludedType(LFunc) then
      Continue;
    if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
      Continue;
    if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
      Continue;

    LSkip := False;
    for LI := 0 to High(LFunc.Params) do
    begin
      if LFunc.Params[LI].TypeName = '' then
      begin
        LSkip := True;
        Break;
      end;
      if (Length(LFunc.Params[LI].TypeName) = 1) and
         CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
      begin
        LSkip := True;
        Break;
      end;
    end;
    if LSkip then
      Continue;

    if FDllNameMap.Count > 0 then
      LHandleName := 'GDllHandle' + DllNameToIdentifier(GetDllNameForFunction(LFunc))
    else
      LHandleName := 'GDllHandle';

    EmitFmt('@%s := GetProcAddress(%s, ''%s'');', [
      GetDelphiFuncName(LFunc.FuncName), LHandleName, LFunc.FuncName]);
  end;

  Dec(FIndent);
  EmitLn('end;');
  EmitLn();
end;

procedure TCImporter.GenerateUnbindExports();
var
  LFunc: TCFunctionInfo;
  LI: Integer;
  LSkip: Boolean;
  LId: string;
  LEntry: TDllMapEntry;
begin
  if FFunctions.Count = 0 then
    Exit;

  EmitLn('procedure UnbindExports();');
  EmitLn('begin');
  Inc(FIndent);

  for LFunc in FFunctions do
  begin
    if FExcludedFunctions.Contains(LFunc.FuncName) then
      Continue;
    if FunctionReferencesExcludedType(LFunc) then
      Continue;
    if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
      Continue;
    if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
      Continue;

    LSkip := False;
    for LI := 0 to High(LFunc.Params) do
    begin
      if LFunc.Params[LI].TypeName = '' then
      begin
        LSkip := True;
        Break;
      end;
      if (Length(LFunc.Params[LI].TypeName) = 1) and
         CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
      begin
        LSkip := True;
        Break;
      end;
    end;
    if LSkip then
      Continue;

    EmitFmt('@%s := nil;', [GetDelphiFuncName(LFunc.FuncName)]);
  end;

  if FDllNameMap.Count > 0 then
  begin
    // Free each mapped DLL handle
    for LI := FDllNameMap.Count - 1 downto 0 do
    begin
      LEntry := FDllNameMap[LI];
      LId := DllNameToIdentifier(LEntry.DllName);
      EmitFmt('if GDllHandle%s <> 0 then', [LId]);
      EmitLn('begin');
      Inc(FIndent);
      EmitFmt('FreeLibrary(GDllHandle%s);', [LId]);
      EmitFmt('GDllHandle%s := 0;', [LId]);
      Dec(FIndent);
      EmitLn('end;');
    end;
  end
  else
  begin
    EmitLn('if GDllHandle <> 0 then');
    EmitLn('begin');
    Inc(FIndent);
    EmitLn('FreeLibrary(GDllHandle);');
    EmitLn('GDllHandle := 0;');
    Dec(FIndent);
    EmitLn('end;');
  end;

  Dec(FIndent);
  EmitLn('end;');
  EmitLn();
end;

function TCImporter.BindingModeFromString(const AValue: string): TBindingMode;
var
  LLower: string;
begin
  LLower := LowerCase(Trim(AValue));
  if LLower = 'dynamic' then
    Result := bmDynamic
  else if LLower = 'dynamic_delayed' then
    Result := bmDynamicDelayed
  else if LLower = 'dynamic_custom' then
    Result := bmDynamicCustom
  else if LLower = 'static_vpk' then
    Result := bmStaticVpk
  else
    Result := bmStatic;
end;

procedure TCImporter.SetBindingMode(const AMode: TBindingMode);
begin
  FBindingMode := AMode;
end;

procedure TCImporter.AddDllNameMap(const APath, ADllName, ADllPath: string);
var
  LEntry: TDllMapEntry;
begin
  LEntry.Path := TPath.GetFullPath(APath).Replace('\', '/');
  LEntry.DllName := ADllName;
  if not LEntry.DllName.EndsWith('.dll', True) then
    LEntry.DllName := LEntry.DllName + '.dll';
  LEntry.DllPath := ADllPath;
  LEntry.ResName := GenerateResName();
  FDllNameMap.Add(LEntry);
end;

procedure TCImporter.AddFunctionDllMap(const AFuncName, ADllName, ADllPath: string);
var
  LDll: string;
  LEntry: TDllMapEntry;
  LFound: Boolean;
  LI: Integer;
begin
  LDll := ADllName;
  if not LDll.EndsWith('.dll', True) then
    LDll := LDll + '.dll';

  // Store function -> DLL override
  FFuncDllMap.AddOrSetValue(AFuncName, LDll);

  // Auto-register the DLL in FDllNameMap if not already present
  LFound := False;
  for LI := 0 to FDllNameMap.Count - 1 do
  begin
    if SameText(FDllNameMap[LI].DllName, LDll) then
    begin
      LFound := True;
      Break;
    end;
  end;

  if not LFound then
  begin
    LEntry.Path := '';
    LEntry.DllName := LDll;
    LEntry.DllPath := ADllPath;
    LEntry.ResName := GenerateResName();
    FDllNameMap.Add(LEntry);
  end;
end;

procedure TCImporter.AddDepDll(const ADllName, ADllPath: string);
var
  LEntry: TDepDllInfo;
begin
  LEntry.DllName := ADllName;
  if not LEntry.DllName.EndsWith('.dll', True) then
    LEntry.DllName := LEntry.DllName + '.dll';
  LEntry.DllPath := ADllPath;
  LEntry.ResName := GenerateResName();
  FDepDlls.Add(LEntry);
end;

function TCImporter.GetDllNameForFunction(const AFunc: TCFunctionInfo): string;
var
  LNormalizedSource: string;
  LNormalizedPath: string;
  LEntry: TDllMapEntry;
  LBestLen: Integer;
begin
  // If no DLL name map defined, use default single DLL name
  if FDllNameMap.Count = 0 then
    Exit(FDllName);

  // Check function-level overrides first
  if FFuncDllMap.TryGetValue(AFunc.FuncName, Result) then
    Exit;

  // Normalize the function's source file path
  LNormalizedSource := LowerCase(AFunc.SourceFile.Replace('\', '/'));
  while LNormalizedSource.Contains('//') do
    LNormalizedSource := LNormalizedSource.Replace('//', '/');

  // Find the longest matching path (most specific wins)
  Result := '';
  LBestLen := 0;
  for LEntry in FDllNameMap do
  begin
    LNormalizedPath := LowerCase(LEntry.Path.Replace('\', '/'));
    while LNormalizedPath.Contains('//') do
      LNormalizedPath := LNormalizedPath.Replace('//', '/');
    if LNormalizedSource.Contains(LNormalizedPath) then
    begin
      if Length(LNormalizedPath) > LBestLen then
      begin
        LBestLen := Length(LNormalizedPath);
        Result := LEntry.DllName;
      end;
    end;
  end;

  // Fallback: use first map entry when map is active
  if Result = '' then
    Result := FDllNameMap[0].DllName;
end;

function TCImporter.DllNameToIdentifier(const ADllName: string): string;
var
  LI: Integer;
  LCh: Char;
  LCapNext: Boolean;
begin
  // Convert 'csfml-audio.dll' -> 'CsfmlAudio'
  Result := '';
  LCapNext := True;
  for LI := 1 to Length(ADllName) do
  begin
    LCh := ADllName[LI];
    if LCh = '.' then
      Break;
    if CharInSet(LCh, ['-', '_']) then
    begin
      LCapNext := True;
      Continue;
    end;
    if LCapNext then
    begin
      Result := Result + UpCase(LCh);
      LCapNext := False;
    end
    else
      Result := Result + LCh;
  end;
end;

procedure TCImporter.GenerateFunctionsExternal(const ADelayed: Boolean);
var
  LFunc: TCFunctionInfo;
  LParam: TCParamInfo;
  LReturnType: string;
  LParamStr: string;
  LI: Integer;
  LParamType: string;
  LParamName: string;
  LSkip: Boolean;
  LDelayedStr: string;
  LConstName: string;
  LEntry: TDllMapEntry;
begin
  if FFunctions.Count = 0 then
    Exit;

  // Emit DLL name constant(s) for external declarations
  EmitLn('const');
  Inc(FIndent);
  if FDllNameMap.Count > 0 then
  begin
    for LEntry in FDllNameMap do
      EmitFmt('CDll%s = ''%s'';', [DllNameToIdentifier(LEntry.DllName), LEntry.DllName]);
  end
  else
    EmitFmt('CDllName = ''%s'';', [FDllName]);
  Dec(FIndent);
  EmitLn();

  if ADelayed then
    LDelayedStr := ' delayed'
  else
    LDelayedStr := '';

  for LFunc in FFunctions do
  begin
    if FExcludedFunctions.Contains(LFunc.FuncName) then
      Continue;
    if FunctionReferencesExcludedType(LFunc) then
      Continue;

    // Skip malformed functions
    if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
      Continue;
    if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
      Continue;

    LSkip := False;
    for LI := 0 to High(LFunc.Params) do
    begin
      if LFunc.Params[LI].TypeName = '' then
      begin
        LSkip := True;
        Break;
      end;
      if (Length(LFunc.Params[LI].TypeName) = 1) and
         CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
      begin
        LSkip := True;
        Break;
      end;
    end;
    if LSkip then
      Continue;

    if FDllNameMap.Count > 0 then
      LConstName := 'CDll' + DllNameToIdentifier(GetDllNameForFunction(LFunc))
    else
      LConstName := 'CDllName';

    LParamStr := '';
    for LI := 0 to High(LFunc.Params) do
    begin
      LParam := LFunc.Params[LI];
      LParamType := MapCTypeToDelphi(LParam.TypeName, LParam.IsPointer,
        LParam.PointerDepth, LParam.IsConstTarget);
      if LParam.ParamName <> '' then
        LParamName := 'A' + LParam.ParamName
      else
        LParamName := Format('AParam%d', [LI]);
      if LI > 0 then
        LParamStr := LParamStr + '; ';
      LParamStr := LParamStr + Format('const %s: %s',
        [SanitizeIdentifier(LParamName), LParamType]);
    end;

    if (LFunc.ReturnType = 'void') and not LFunc.ReturnIsPointer then
      EmitFmt('procedure %s(%s); cdecl; external %s%s;',
        [GetDelphiFuncName(LFunc.FuncName), LParamStr, LConstName, LDelayedStr])
    else
    begin
      LReturnType := MapCTypeToDelphi(LFunc.ReturnType, LFunc.ReturnIsPointer,
        LFunc.ReturnPointerDepth);
      EmitFmt('function  %s(%s): %s; cdecl; external %s%s;',
        [GetDelphiFuncName(LFunc.FuncName), LParamStr, LReturnType, LConstName, LDelayedStr]);
    end;
  end;

  EmitLn();
end;

procedure TCImporter.GenerateDlmBindExportsCustom();
var
  LFunc: TCFunctionInfo;
  LI, LDllIdx: Integer;
  LSkip: Boolean;
  LId: string;
  LHandleName: string;
  LSignature: string;
  LDllName: string;
begin
  if FFunctions.Count = 0 then
    Exit;

  if FDllNameMap.Count > 1 then
  begin
    // Multi-DLL: separate BindExports per DLL
    for LDllIdx := 0 to FDllNameMap.Count - 1 do
    begin
      LId := DllNameToIdentifier(FDllNameMap[LDllIdx].DllName);
      LDllName := FDllNameMap[LDllIdx].DllName;
      LHandleName := 'GDllHandle' + LId;
      EmitFmt('procedure BindExports%s(const AHandle: THandle);', [LId]);
      EmitLn('begin');
      Inc(FIndent);
      EmitFmt('%s := AHandle;', [LHandleName]);

      for LFunc in FFunctions do
      begin
        if FExcludedFunctions.Contains(LFunc.FuncName) then
          Continue;
        if FunctionReferencesExcludedType(LFunc) then
          Continue;
        if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
          Continue;
        if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
          Continue;

        LSkip := False;
        for LI := 0 to High(LFunc.Params) do
        begin
          if LFunc.Params[LI].TypeName = '' then
          begin
            LSkip := True;
            Break;
          end;
          if (Length(LFunc.Params[LI].TypeName) = 1) and
             CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
          begin
            LSkip := True;
            Break;
          end;
        end;
        if LSkip then
          Continue;

        if GetDllNameForFunction(LFunc) <> LDllName then
          Continue;

        EmitFmt('@%s := GetProcAddress(%s, ''%s'');', [
          GetDelphiFuncName(LFunc.FuncName), LHandleName, LFunc.FuncName]);
      end;

      Dec(FIndent);
      EmitLn('end;');
      EmitLn();
    end;
  end
  else if FDllNameMap.Count > 0 then
  begin
    // Single mapped DLL
    LSignature := 'procedure BindExports(';
    LId := DllNameToIdentifier(FDllNameMap[0].DllName);
    LSignature := LSignature + Format('const AHandle%s: THandle);', [LId]);
    EmitLn(LSignature);
    EmitLn('begin');
    Inc(FIndent);
    EmitFmt('GDllHandle%s := AHandle%s;', [LId, LId]);

    for LFunc in FFunctions do
    begin
      if FExcludedFunctions.Contains(LFunc.FuncName) then
        Continue;
      if FunctionReferencesExcludedType(LFunc) then
        Continue;
      if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
        Continue;
      if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
        Continue;

      LSkip := False;
      for LI := 0 to High(LFunc.Params) do
      begin
        if LFunc.Params[LI].TypeName = '' then
        begin
          LSkip := True;
          Break;
        end;
        if (Length(LFunc.Params[LI].TypeName) = 1) and
           CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
        begin
          LSkip := True;
          Break;
        end;
      end;
      if LSkip then
        Continue;

      LHandleName := 'GDllHandle' + DllNameToIdentifier(GetDllNameForFunction(LFunc));
      EmitFmt('@%s := GetProcAddress(%s, ''%s'');', [
        GetDelphiFuncName(LFunc.FuncName), LHandleName, LFunc.FuncName]);
    end;

    Dec(FIndent);
    EmitLn('end;');
  end
  else
  begin
    EmitLn('procedure BindExports(const AHandle: THandle);');
    EmitLn('begin');
    Inc(FIndent);
    EmitLn('GDllHandle := AHandle;');
    EmitLn('if GDllHandle = 0 then');
    Inc(FIndent);
    EmitLn('Exit;');
    Dec(FIndent);

    for LFunc in FFunctions do
    begin
      if FExcludedFunctions.Contains(LFunc.FuncName) then
        Continue;
      if FunctionReferencesExcludedType(LFunc) then
        Continue;
      if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
        Continue;
      if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
        Continue;

      LSkip := False;
      for LI := 0 to High(LFunc.Params) do
      begin
        if LFunc.Params[LI].TypeName = '' then
        begin
          LSkip := True;
          Break;
        end;
        if (Length(LFunc.Params[LI].TypeName) = 1) and
           CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
        begin
          LSkip := True;
          Break;
        end;
      end;
      if LSkip then
        Continue;

      EmitFmt('@%s := GetProcAddress(GDllHandle, ''%s'');', [
        GetDelphiFuncName(LFunc.FuncName), LFunc.FuncName]);
    end;

    Dec(FIndent);
    EmitLn('end;');
  end;
  EmitLn();
end;

procedure TCImporter.GenerateDlmUnbindExportsCustom();
var
  LFunc: TCFunctionInfo;
  LI, LDllIdx: Integer;
  LSkip: Boolean;
  LId: string;
  LDllName: string;
begin
  if FFunctions.Count = 0 then
    Exit;

  if FDllNameMap.Count > 1 then
  begin
    // Multi-DLL: separate UnbindExports per DLL
    for LDllIdx := 0 to FDllNameMap.Count - 1 do
    begin
      LId := DllNameToIdentifier(FDllNameMap[LDllIdx].DllName);
      LDllName := FDllNameMap[LDllIdx].DllName;
      EmitFmt('procedure UnbindExports%s();', [LId]);
      EmitLn('begin');
      Inc(FIndent);

      for LFunc in FFunctions do
      begin
        if FExcludedFunctions.Contains(LFunc.FuncName) then
          Continue;
        if FunctionReferencesExcludedType(LFunc) then
          Continue;
        if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
          Continue;
        if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
          Continue;

        LSkip := False;
        for LI := 0 to High(LFunc.Params) do
        begin
          if LFunc.Params[LI].TypeName = '' then
          begin
            LSkip := True;
            Break;
          end;
          if (Length(LFunc.Params[LI].TypeName) = 1) and
             CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
          begin
            LSkip := True;
            Break;
          end;
        end;
        if LSkip then
          Continue;

        if GetDllNameForFunction(LFunc) <> LDllName then
          Continue;

        EmitFmt('@%s := nil;', [GetDelphiFuncName(LFunc.FuncName)]);
      end;

      EmitFmt('GDllHandle%s := 0;', [LId]);
      Dec(FIndent);
      EmitLn('end;');
      EmitLn();
    end;
  end
  else
  begin
    EmitLn('procedure UnbindExports();');
    EmitLn('begin');
    Inc(FIndent);

    for LFunc in FFunctions do
    begin
      if FExcludedFunctions.Contains(LFunc.FuncName) then
        Continue;
      if FunctionReferencesExcludedType(LFunc) then
        Continue;
      if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
        Continue;
      if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
        Continue;

      LSkip := False;
      for LI := 0 to High(LFunc.Params) do
      begin
        if LFunc.Params[LI].TypeName = '' then
        begin
          LSkip := True;
          Break;
        end;
        if (Length(LFunc.Params[LI].TypeName) = 1) and
           CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
        begin
          LSkip := True;
          Break;
        end;
      end;
      if LSkip then
        Continue;

      EmitFmt('@%s := nil;', [GetDelphiFuncName(LFunc.FuncName)]);
    end;

    // Does NOT call FreeLibrary -- caller owns the handle(s)
    if FDllNameMap.Count > 0 then
    begin
      for LI := 0 to FDllNameMap.Count - 1 do
      begin
        LId := DllNameToIdentifier(FDllNameMap[LI].DllName);
        EmitFmt('GDllHandle%s := 0;', [LId]);
      end;
    end
    else
      EmitLn('GDllHandle := 0;');

    Dec(FIndent);
    EmitLn('end;');
    EmitLn();
  end;
end;

procedure TCImporter.GenerateDlmBindExportsVpk();
var
  LFunc: TCFunctionInfo;
  LI: Integer;
  LSkip: Boolean;
  LId: string;
  LHandleName: string;
  LEntry: TDllMapEntry;
begin
  if FFunctions.Count = 0 then
    Exit;

  EmitLn('procedure BindExports(const AVFS: TVFS; const AFilename: string);');
  EmitLn('var');
  Inc(FIndent);
  EmitLn('LView: TVirtualMemoryView<Byte>;');
  Dec(FIndent);
  EmitLn('begin');
  Inc(FIndent);

  if FDllNameMap.Count > 0 then
  begin
    // Multi-DLL: load each mapped DLL from VPK by its DLL name
    for LEntry in FDllNameMap do
    begin
      LId := DllNameToIdentifier(LEntry.DllName);
      EmitFmt('LView := AVFS.OpenFile(CDll%s);', [LId]);
      EmitLn('try');
      Inc(FIndent);
      EmitFmt('GDllHandle%s := StdApp.DllLoader.LoadLibrary(LView.Memory, LView.Size);', [LId]);
      Dec(FIndent);
      EmitLn('finally');
      Inc(FIndent);
      EmitLn('LView.Free();');
      Dec(FIndent);
      EmitLn('end;');
    end;
  end
  else
  begin
    EmitLn('LView := AVFS.OpenFile(AFilename);');
    EmitLn('try');
    Inc(FIndent);
    EmitLn('GDllHandle := StdApp.DllLoader.LoadLibrary(LView.Memory, LView.Size);');
    Dec(FIndent);
    EmitLn('finally');
    Inc(FIndent);
    EmitLn('LView.Free();');
    Dec(FIndent);
    EmitLn('end;');
    EmitLn('if GDllHandle = 0 then');
    Inc(FIndent);
    EmitLn('Exit;');
    Dec(FIndent);
  end;

  for LFunc in FFunctions do
  begin
    if FExcludedFunctions.Contains(LFunc.FuncName) then
      Continue;
    if FunctionReferencesExcludedType(LFunc) then
      Continue;
    if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
      Continue;
    if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
      Continue;

    LSkip := False;
    for LI := 0 to High(LFunc.Params) do
    begin
      if LFunc.Params[LI].TypeName = '' then
      begin
        LSkip := True;
        Break;
      end;
      if (Length(LFunc.Params[LI].TypeName) = 1) and
         CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
      begin
        LSkip := True;
        Break;
      end;
    end;
    if LSkip then
      Continue;

    if FDllNameMap.Count > 0 then
      LHandleName := 'GDllHandle' + DllNameToIdentifier(GetDllNameForFunction(LFunc))
    else
      LHandleName := 'GDllHandle';

    EmitFmt('@%s := GetProcAddress(%s, ''%s'');', [
      GetDelphiFuncName(LFunc.FuncName), LHandleName, LFunc.FuncName]);
  end;

  Dec(FIndent);
  EmitLn('end;');
  EmitLn();
end;

procedure TCImporter.GenerateDlmUnbindExportsVpk();
var
  LFunc: TCFunctionInfo;
  LI: Integer;
  LSkip: Boolean;
  LId: string;
  LEntry: TDllMapEntry;
begin
  if FFunctions.Count = 0 then
    Exit;

  EmitLn('procedure UnbindExports();');
  EmitLn('begin');
  Inc(FIndent);

  for LFunc in FFunctions do
  begin
    if FExcludedFunctions.Contains(LFunc.FuncName) then
      Continue;
    if FunctionReferencesExcludedType(LFunc) then
      Continue;
    if (LFunc.ReturnType = '') or (LFunc.ReturnType = 'return') then
      Continue;
    if (Length(LFunc.ReturnType) = 1) and CharInSet(LFunc.ReturnType[1], ['a'..'z', 'A'..'Z']) then
      Continue;

    LSkip := False;
    for LI := 0 to High(LFunc.Params) do
    begin
      if LFunc.Params[LI].TypeName = '' then
      begin
        LSkip := True;
        Break;
      end;
      if (Length(LFunc.Params[LI].TypeName) = 1) and
         CharInSet(LFunc.Params[LI].TypeName[1], ['a'..'z', 'A'..'Z']) then
      begin
        LSkip := True;
        Break;
      end;
    end;
    if LSkip then
      Continue;

    EmitFmt('@%s := nil;', [GetDelphiFuncName(LFunc.FuncName)]);
  end;

  // Generated unit owns the handle(s), so free them
  if FDllNameMap.Count > 0 then
  begin
    for LI := FDllNameMap.Count - 1 downto 0 do
    begin
      LEntry := FDllNameMap[LI];
      LId := DllNameToIdentifier(LEntry.DllName);
      EmitFmt('if GDllHandle%s <> 0 then', [LId]);
      EmitLn('begin');
      Inc(FIndent);
      EmitFmt('FreeLibrary(GDllHandle%s);', [LId]);
      EmitFmt('GDllHandle%s := 0;', [LId]);
      Dec(FIndent);
      EmitLn('end;');
    end;
  end
  else
  begin
    EmitLn('if GDllHandle <> 0 then');
    EmitLn('begin');
    Inc(FIndent);
    EmitLn('FreeLibrary(GDllHandle);');
    EmitLn('GDllHandle := 0;');
    Dec(FIndent);
    EmitLn('end;');
  end;

  Dec(FIndent);
  EmitLn('end;');
  EmitLn();
end;

function TCImporter.GenerateResName(): string;
var
  LGuid: TGUID;
begin
  CreateGUID(LGuid);
  Result := LowerCase(GUIDToString(LGuid));
  Result := StringReplace(Result, '{', '', []);
  Result := StringReplace(Result, '}', '', []);
  Result := StringReplace(Result, '-', '', [rfReplaceAll]);
  Result := 'r' + Result;
end;

procedure TCImporter.ProcessInsertions();
var
  LOutput: string;
  LInsertion: TInsertionInfo;
  LReplacement: TReplacementInfo;
  LOccurrenceCount: Integer;
  LTargetTrimmed: string;
  LLines: TArray<string>;
  LLine: string;
  LTrimmedLine: string;
  LResult: TStringBuilder;
  LI: Integer;
  LInserted: Boolean;
  LPos: Integer;
  LCount: Integer;
  LSearchStart: Integer;
begin
  if (FInsertions.Count = 0) and (FReplacements.Count = 0) then
    Exit;

  LOutput := FOutput.ToString();

  for LInsertion in FInsertions do
  begin
    LTargetTrimmed := LowerCase(Trim(LInsertion.TargetLine));
    LOccurrenceCount := 0;
    LInserted := False;

    // Split preserving empty lines
    LLines := LOutput.Split([#13#10, #10], TStringSplitOptions.None);

    LResult := TStringBuilder.Create();
    try
      for LI := 0 to High(LLines) do
      begin
        LLine := LLines[LI];
        LTrimmedLine := LowerCase(Trim(LLine));

        if (not LInserted) and (LTrimmedLine = LTargetTrimmed) then
        begin
          Inc(LOccurrenceCount);
          if LOccurrenceCount = LInsertion.Occurrence then
          begin
            if LInsertion.InsertBefore then
            begin
              LResult.Append(LInsertion.Content);
              LResult.AppendLine(LLine);
            end
            else
            begin
              LResult.AppendLine(LLine);
              LResult.Append(LInsertion.Content);
            end;
            LInserted := True;
          end
          else
          begin
            LResult.AppendLine(LLine);
          end;
        end
        else
        begin
          // Don't add newline after last line
          if LI < High(LLines) then
            LResult.AppendLine(LLine)
          else
            LResult.Append(LLine);
        end;
      end;

      LOutput := LResult.ToString();
    finally
      LResult.Free();
    end;
  end;

  // Update output
  FOutput.Clear();
  FOutput.Append(LOutput);

  // Process replacements
  if FReplacements.Count > 0 then
  begin
    LOutput := FOutput.ToString();

    for LReplacement in FReplacements do
    begin
      if LReplacement.Occurrence = 0 then
      begin
        // Replace all occurrences
        LOutput := LOutput.Replace(LReplacement.OldText, LReplacement.NewText);
      end
      else
      begin
        // Replace specific occurrence
        LCount := 0;
        LSearchStart := 1;

        while LSearchStart <= Length(LOutput) do
        begin
          LPos := Pos(LReplacement.OldText, LOutput, LSearchStart);
          if LPos = 0 then
            Break;

          Inc(LCount);
          if LCount = LReplacement.Occurrence then
          begin
            // Replace this occurrence
            LOutput := Copy(LOutput, 1, LPos - 1) +
                       LReplacement.NewText +
                       Copy(LOutput, LPos + Length(LReplacement.OldText), MaxInt);
            Break;
          end;

          LSearchStart := LPos + Length(LReplacement.OldText);
        end;
      end;
    end;

    FOutput.Clear();
    FOutput.Append(LOutput);
  end;
end;

procedure TCImporter.SetOutputPath(const APath: string);
begin
  FOutputPath := APath.Replace('\', '/');
end;

procedure TCImporter.SetHeader(const AFilename: string);
begin
  FHeader := AFilename.Replace('\', '/');
end;

function TCImporter.Process(): Boolean;
var
  LPreprocessedSource: string;
  LHeaderName: string;
  LOutputFile: string;
  LOutputDir: string;
  LStructCount: Integer;
  LUnionCount: Integer;
  LEnumCount: Integer;
  LTypedefCount: Integer;
  LFuncPtrCount: Integer;
  LDefineCount: Integer;
  LStruct: TCStructInfo;
  LTypedef: TCTypedefInfo;
  LDefine: TCDefineInfo;
  LResFile: string;
  LResCompiler: TResourceCompiler;
  LMapEntry: TDllMapEntry;
  LDepEntry: TDepDllInfo;
begin
  Result := False;
  FLastError := '';

  if FHeader = '' then
  begin
    FLastError := 'No header file specified';
    Exit;
  end;

  FLexer.Clear();
  FOutput.Clear();
  FStructs.Clear();
  FEnums.Clear();
  FTypedefs.Clear();
  FDefines.Clear();
  FFunctions.Clear();
  FForwardDecls.Clear();
  FCurrentSourceFile := '';
  FPos := 0;
  FIndent := 0;

  LHeaderName := TPath.GetFileNameWithoutExtension(FHeader);

  if FModuleName = '' then
    FModuleName := LHeaderName;

  if FDllName = '' then
    FDllName := FModuleName + '.dll';

  if FDllPath = '' then
    FDllPath := FDllName;

  FResName := GenerateResName();

  if FOutputPath <> '' then
    LOutputDir := FOutputPath
  else
    LOutputDir := TPath.GetDirectoryName(TPath.GetFullPath(FHeader));

  LOutputFile := TPath.Combine(LOutputDir, FModuleName + '.pas').Replace('\', '/');

  // Header info
  Status(COLOR_CYAN + 'CImporter' + COLOR_RESET + ' - C Header to Delphi Unit Converter', []);
  Status(COLOR_WHITE + '  Header: ' + COLOR_RESET + '%s', [FHeader]);
  Status(COLOR_WHITE + '  Unit:   ' + COLOR_RESET + '%s', [FModuleName]);
  Status('', []);

  // Preprocessing phase
  Status(COLOR_CYAN + 'Preprocessing...' + COLOR_RESET, []);
  if not PreprocessHeader(FHeader, LPreprocessedSource) then
  begin
    Status(COLOR_RED + '  Failed: ' + COLOR_RESET + '%s', [FLastError]);
    Exit;
  end;
  Status(COLOR_WHITE + '  Preprocessed size: ' + COLOR_RESET + '%d bytes', [Length(LPreprocessedSource)]);
  if FSavePreprocessed then
    Status(COLOR_WHITE + '  Saved preprocessed: ' + COLOR_RESET + '%s_pp.c', [FModuleName]);

  // Parsing phase
  Status(COLOR_CYAN + 'Parsing declarations...' + COLOR_RESET, []);
  ParsePreprocessed(LPreprocessedSource);

  // Count structs vs unions
  LStructCount := 0;
  LUnionCount := 0;
  for LStruct in FStructs do
  begin
    if LStruct.IsUnion then
      Inc(LUnionCount)
    else
      Inc(LStructCount);
  end;

  // Count typedefs vs function pointers
  LTypedefCount := 0;
  LFuncPtrCount := 0;
  for LTypedef in FTypedefs do
  begin
    if LTypedef.IsFunctionPointer then
      Inc(LFuncPtrCount)
    else
      Inc(LTypedefCount);
  end;

  LEnumCount := FEnums.Count;

  // Count defines that pass the exclusion filter
  LDefineCount := 0;
  for LDefine in FDefines do
  begin
    if FExcludedTypes.Contains(LDefine.DefineName) then
      Continue;
    if LDefine.IsInteger or LDefine.IsFloat or LDefine.IsString then
      Inc(LDefineCount);
  end;

  Status(COLOR_WHITE + '  Forward decls:    ' + COLOR_RESET + '%d', [FForwardDecls.Count]);
  Status(COLOR_WHITE + '  Structs:          ' + COLOR_RESET + '%d', [LStructCount]);
  Status(COLOR_WHITE + '  Unions:           ' + COLOR_RESET + '%d', [LUnionCount]);
  Status(COLOR_WHITE + '  Enums:            ' + COLOR_RESET + '%d', [LEnumCount]);
  Status(COLOR_WHITE + '  Type aliases:     ' + COLOR_RESET + '%d', [LTypedefCount]);
  Status(COLOR_WHITE + '  Function ptrs:    ' + COLOR_RESET + '%d', [LFuncPtrCount]);
  Status(COLOR_WHITE + '  Functions:        ' + COLOR_RESET + '%d', [FFunctions.Count]);
  Status(COLOR_WHITE + '  Defines:          ' + COLOR_RESET + '%d', [LDefineCount]);

  // Writing phase
  Status(COLOR_CYAN + 'Writing output...' + COLOR_RESET, []);
  try
    TUtils.CreateDirInPath(LOutputFile);
    if TFile.Exists(LOutputFile) then
      TFile.Delete(LOutputFile);
    TFile.WriteAllText(LOutputFile, FOutput.ToString(), TEncoding.UTF8);
  except
    on E: Exception do
    begin
      FLastError := 'Failed to write output file: ' + E.Message;
      Status(COLOR_RED + '  Failed: ' + COLOR_RESET + '%s', [FLastError]);
      Exit;
    end;
  end;

  Status(COLOR_WHITE + '  Output: ' + COLOR_RESET + '%s', [LOutputFile]);

  // Generate .res resource file only for bmStatic mode using TResourceCompiler
  if FBindingMode = bmStatic then
  begin
    LResFile := TPath.Combine(LOutputDir, FModuleName + '.res').Replace('\', '/');
    try
      LResCompiler := TResourceCompiler.Create();
      try
        if FDllNameMap.Count > 0 then
        begin
          // Multi-DLL: add one RCDATA resource per mapped + dep DLL
          for LMapEntry in FDllNameMap do
            LResCompiler.AddResourceFromFile(RES_RT_RCDATA, LMapEntry.ResName,
              TPath.GetFullPath(LMapEntry.DllPath));
          for LDepEntry in FDepDlls do
            LResCompiler.AddResourceFromFile(RES_RT_RCDATA, LDepEntry.ResName,
              TPath.GetFullPath(LDepEntry.DllPath));
        end
        else
          LResCompiler.AddResourceFromFile(RES_RT_RCDATA, FResName,
            TPath.GetFullPath(FDllPath));
        LResCompiler.CompileToFile(LResFile);
        Status(COLOR_WHITE + '  RES:    ' + COLOR_RESET + '%s', [LResFile]);
      finally
        LResCompiler.Free();
      end;
    except
      on E: Exception do
      begin
        Status(COLOR_YELLOW + '  Warning: ' + COLOR_RESET + 'Failed to compile .res: %s', [E.Message]);
      end;
    end;
  end;

  Status('', []);
  Status(COLOR_GREEN + 'Import complete.' + COLOR_RESET, []);

  Result := True;
end;

procedure TCImporter.SetModuleName(const AName: string);
begin
  FModuleName := AName;
end;

procedure TCImporter.SetDllName(const ADllName: string);
begin
  FDllName := ADllName;
  if not FDllName.EndsWith('.dll', True) then
    FDllName := FDllName + '.dll';
end;

procedure TCImporter.SetDllPath(const ADllPath: string);
begin
  FDllPath := ADllPath;
end;

procedure TCImporter.AddDefine(const AName: string; const AValue: string);
begin
  FUserDefines.AddOrSetValue(AName, AValue);
end;

procedure TCImporter.AddUndefine(const AName: string);
begin
  if not FUserUndefines.Contains(AName) then
    FUserUndefines.Add(AName);
end;

function TCImporter.LoadFromConfig(const AFilename: string): Boolean;
var
  LJson: TJSON;
  LItem: TJSON;
begin
  Result := False;

  LJson := TJSON.Create();
  try
    try
      LJson.LoadFromFile(AFilename);
    except
      on E: Exception do
      begin
        FLastError := 'Failed to load config: ' + E.Message;
        Exit;
      end;
    end;

    // Header (required)
    if not LJson.Has('header') then
    begin
      FLastError := 'No header file specified in configuration';
      Exit;
    end;
    SetHeader(LJson.Get('header').AsString());

    // Simple settings
    if LJson.Has('module_name') then
      SetModuleName(LJson.Get('module_name').AsString());

    if LJson.Has('dll_name') then
      SetDllName(LJson.Get('dll_name').AsString());

    if LJson.Has('dll_path') then
      SetDllPath(LJson.Get('dll_path').AsString());

    if LJson.Has('output_path') then
      SetOutputPath(LJson.Get('output_path').AsString());

    // Binding mode
    if LJson.Has('binding_mode') then
      SetBindingMode(BindingModeFromString(LJson.Get('binding_mode').AsString()));

    // Include paths (array of objects with path and optional module)
    if LJson.Has('include_paths') then
    begin
      for LItem in LJson.Get('include_paths') do
      begin
        if LItem.Has('path') then
          AddIncludePath(LItem.Get('path').AsString(), LItem.Get('module').AsString());
      end;
    end;

    // Source paths (string array)
    if LJson.Has('source_paths') then
    begin
      for LItem in LJson.Get('source_paths') do
        AddSourcePath(LItem.AsString());
    end;

    // Excluded types (string array)
    if LJson.Has('excluded_types') then
    begin
      for LItem in LJson.Get('excluded_types') do
        AddExcludedType(LItem.AsString());
    end;

    // Excluded functions (string array)
    if LJson.Has('excluded_functions') then
    begin
      for LItem in LJson.Get('excluded_functions') do
        AddExcludedFunction(LItem.AsString());
    end;

    // Function renames (array of objects)
    if LJson.Has('function_renames') then
    begin
      for LItem in LJson.Get('function_renames') do
      begin
        if LItem.Has('original') and LItem.Has('rename_to') then
          AddFunctionRename(LItem.Get('original').AsString(), LItem.Get('rename_to').AsString());
      end;
    end;

    // Uses units (string array)
    if LJson.Has('uses_units') then
    begin
      for LItem in LJson.Get('uses_units') do
        AddUsesUnit(LItem.AsString());
    end;

    // Save preprocessed flag
    if LJson.Has('save_preprocessed') then
      SetSavePreprocessed(LJson.Get('save_preprocessed').AsBoolean());

    // Insertions (array of objects)
    if LJson.Has('insertions') then
    begin
      for LItem in LJson.Get('insertions') do
      begin
        if LItem.Has('file') and (LItem.Get('file').AsString() <> '') then
        begin
          if LItem.Get('position').AsString('after') = 'before' then
            InsertFileBefore(LItem.Get('target').AsString(), LItem.Get('file').AsString(),
              LItem.Get('occurrence').AsInt32(1))
          else
            InsertFileAfter(LItem.Get('target').AsString(), LItem.Get('file').AsString(),
              LItem.Get('occurrence').AsInt32(1));
        end
        else if LItem.Has('content') then
        begin
          if LItem.Get('position').AsString('after') = 'before' then
            InsertTextBefore(LItem.Get('target').AsString(), LItem.Get('content').AsString(),
              LItem.Get('occurrence').AsInt32(1))
          else
            InsertTextAfter(LItem.Get('target').AsString(), LItem.Get('content').AsString(),
              LItem.Get('occurrence').AsInt32(1));
        end;
      end;
    end;

    // Replacements (array of objects)
    if LJson.Has('replacements') then
    begin
      for LItem in LJson.Get('replacements') do
      begin
        if LItem.Has('old_text') then
          ReplaceText(LItem.Get('old_text').AsString(), LItem.Get('new_text').AsString(),
            LItem.Get('occurrence').AsInt32(0));
      end;
    end;

    // DLL name map (array of objects)
    if LJson.Has('dll_name_map') then
    begin
      for LItem in LJson.Get('dll_name_map') do
      begin
        if LItem.Has('path') and LItem.Has('dll_name') then
          AddDllNameMap(LItem.Get('path').AsString(), LItem.Get('dll_name').AsString(),
            LItem.Get('dll_path').AsString());
      end;
    end;

    // Dependency DLLs (array of objects)
    if LJson.Has('dep_dlls') then
    begin
      for LItem in LJson.Get('dep_dlls') do
      begin
        if LItem.Has('dll_name') then
          AddDepDll(LItem.Get('dll_name').AsString(), LItem.Get('dll_path').AsString());
      end;
    end;

    Result := True;
  finally
    LJson.Free();
  end;
end;

function TCImporter.SaveToConfig(const AFilename: string): Boolean;
var
  LJson: TJSON;
  LInsertion: TInsertionInfo;
  LReplacement: TReplacementInfo;
  LMapEntry: TDllMapEntry;
  LDepEntry: TDepDllInfo;
  LKey: string;
  LI: Integer;
begin
  Result := False;

  LJson := TJSON.Create();
  try
    try
      // Header
      if FHeader <> '' then
        LJson.Add('header', FHeader);

      // Module name
      if FModuleName <> '' then
        LJson.Add('module_name', FModuleName);

      // DLL name
      if FDllName <> '' then
        LJson.Add('dll_name', FDllName);

      // DLL path
      if FDllPath <> '' then
        LJson.Add('dll_path', FDllPath);

      // Output path
      if FOutputPath <> '' then
        LJson.Add('output_path', FOutputPath);

      // Binding mode
      if FBindingMode = bmDynamic then
        LJson.Add('binding_mode', 'dynamic')
      else
        LJson.Add('binding_mode', 'static');

      // Save preprocessed flag
      if FSavePreprocessed then
        LJson.Add('save_preprocessed', True);

      // Include paths (array of objects)
      if FIncludePaths.Count > 0 then
      begin
        LJson.BeginArray('include_paths');
        for LI := 0 to FIncludePaths.Count - 1 do
          LJson.BeginObject().Add('path', FIncludePaths[LI]).EndObject();
        LJson.EndArray();
      end;

      // Source paths (string array)
      if FSourcePaths.Count > 0 then
      begin
        LJson.BeginArray('source_paths');
        for LI := 0 to FSourcePaths.Count - 1 do
          LJson.Add(FSourcePaths[LI]);
        LJson.EndArray();
      end;

      // Excluded types (string array)
      if FExcludedTypes.Count > 0 then
      begin
        LJson.BeginArray('excluded_types');
        for LI := 0 to FExcludedTypes.Count - 1 do
          LJson.Add(FExcludedTypes[LI]);
        LJson.EndArray();
      end;

      // Excluded functions (string array)
      if FExcludedFunctions.Count > 0 then
      begin
        LJson.BeginArray('excluded_functions');
        for LI := 0 to FExcludedFunctions.Count - 1 do
          LJson.Add(FExcludedFunctions[LI]);
        LJson.EndArray();
      end;

      // Function renames (array of objects)
      if FFunctionRenames.Count > 0 then
      begin
        LJson.BeginArray('function_renames');
        for LKey in FFunctionRenames.Keys do
          LJson.BeginObject().Add('original', LKey).Add('rename_to', FFunctionRenames[LKey]).EndObject();
        LJson.EndArray();
      end;

      // Uses units (string array)
      if FUsesUnits.Count > 0 then
      begin
        LJson.BeginArray('uses_units');
        for LI := 0 to FUsesUnits.Count - 1 do
          LJson.Add(FUsesUnits[LI]);
        LJson.EndArray();
      end;

      // Insertions (array of objects)
      if FInsertions.Count > 0 then
      begin
        LJson.BeginArray('insertions');
        for LI := 0 to FInsertions.Count - 1 do
        begin
          LInsertion := FInsertions[LI];
          LJson.BeginObject()
            .Add('target', LInsertion.TargetLine)
            .Add('content', LInsertion.Content);
          if LInsertion.InsertBefore then
            LJson.Add('position', 'before')
          else
            LJson.Add('position', 'after');
          if LInsertion.Occurrence <> 1 then
            LJson.Add('occurrence', Int64(LInsertion.Occurrence));
          LJson.EndObject();
        end;
        LJson.EndArray();
      end;

      // Replacements (array of objects)
      if FReplacements.Count > 0 then
      begin
        LJson.BeginArray('replacements');
        for LI := 0 to FReplacements.Count - 1 do
        begin
          LReplacement := FReplacements[LI];
          LJson.BeginObject()
            .Add('old_text', LReplacement.OldText)
            .Add('new_text', LReplacement.NewText);
          if LReplacement.Occurrence <> 0 then
            LJson.Add('occurrence', Int64(LReplacement.Occurrence));
          LJson.EndObject();
        end;
        LJson.EndArray();
      end;

      // DLL name map (array of objects)
      if FDllNameMap.Count > 0 then
      begin
        LJson.BeginArray('dll_name_map');
        for LMapEntry in FDllNameMap do
          LJson.BeginObject()
            .Add('path', LMapEntry.Path)
            .Add('dll_name', LMapEntry.DllName)
            .Add('dll_path', LMapEntry.DllPath)
          .EndObject();
        LJson.EndArray();
      end;

      // Dependency DLLs (array of objects)
      if FDepDlls.Count > 0 then
      begin
        LJson.BeginArray('dep_dlls');
        for LDepEntry in FDepDlls do
          LJson.BeginObject()
            .Add('dll_name', LDepEntry.DllName)
            .Add('dll_path', LDepEntry.DllPath)
          .EndObject();
        LJson.EndArray();
      end;

      LJson.SaveToFile(AFilename);
      Result := True;
    except
      on E: Exception do
        FLastError := 'Failed to save config: ' + E.Message;
    end;
  finally
    LJson.Free();
  end;
end;

function TCImporter.GetLastError(): string;
begin
  Result := FLastError;
end;

procedure TCImporter.Clear();
begin
  FLexer.Clear();
  FOutput.Clear();
  FStructs.Clear();
  FEnums.Clear();
  FTypedefs.Clear();
  FDefines.Clear();
  FFunctions.Clear();
  FForwardDecls.Clear();
  FInsertions.Clear();
  FReplacements.Clear();
  FIncludePaths.Clear();
  FSourcePaths.Clear();
  FExcludedTypes.Clear();
  FExcludedFunctions.Clear();
  FFunctionRenames.Clear();
  FUsesUnits.Clear();
  FDllNameMap.Clear();
  FFuncDllMap.Clear();
  FDepDlls.Clear();
  FUserDefines.Clear();
  FUserUndefines.Clear();
  FSavePreprocessed := False;
  FModuleName := '';
  FDllName := '';
  FOutputPath := '';
  FHeader := '';
  FLastError := '';
  FCurrentSourceFile := '';
  FBindingMode := bmStatic;
  FPos := 0;
  FIndent := 0;
end;

end.
