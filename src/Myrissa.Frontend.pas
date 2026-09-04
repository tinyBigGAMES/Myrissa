{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Myrissa.Frontend - Consolidated frontend (Common, Lexer, AST, Parser, Semantics)

  Contains the complete Myrissa language frontend pipeline: token definitions,
  lexer, AST node hierarchy, parser, and semantic analysis. Consolidated into
  a single unit to resolve circular dependencies between components.

  Dependencies: StdApp.Base, StdApp.Utils, StdApp.Resources, Myrissa.Common
===============================================================================}

unit Myrissa.Frontend;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  System.Rtti,
  StdApp.Base,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Utils,
  StdApp.Resources,
  Myrissa.Common;

type

  { TMyrTokenCategory }
  TMyrTokenCategory = (
    tcKeyword,        // language reserved words
    tcPrimitive,      // built-in type names (int32, string, etc.)
    tcOperator,       // operators (+, -, :=, etc.)
    tcDelimiter,      // structural punctuation (; , . ( ) etc.)
    tcLiteral,        // integer, float, string, wstring literals
    tcIdentifier,     // user-defined identifiers
    tcDirective,      // @name directives
    tcSpecial         // EOF, unknown
  );

  { TMyrTokenKind }
  TMyrTokenKind = (

    // -- Special tokens --
    tkEOF,
    tkUnknown,
    tkIdentifier,
    tkDirective,

    // -- Literals --
    tkIntLiteral,
    tkFloatLiteral,
    tkStringLiteral,
    tkWStringLiteral,
    tkRawBlock,

    // -- Keywords (BNF Section 2 - Reserved Words) --
    tkAddress,
    tkAlign,
    tkAnd,
    tkArray,
    tkAssert,
    tkAssertEq,
    tkAssertEqF,
    tkAssertFalse,
    tkAssertFail,
    tkAssertNil,
    tkAssertNotNil,
    tkAssertTrue,
    tkBegin,
    tkBreak,
    tkChoices,
    tkCLink,
    tkConst,
    tkContinue,
    tkCpp,
    tkCppEnd,
    tkCppLink,
    tkCppStart,
    tkNew,
    tkCStr,
    tkDispose,
    tkDiv,
    tkDo,
    tkDownTo,
    tkElse,
    tkEnd,
    tkExcept,
    tkExcCode,
    tkExcMsg,
    tkExternal,
    tkFalse,
    tkFinalize,
    tkFinally,
    tkFor,
    tkForward,
    tkFreeMem,
    tkGetMem,
    tkGuard,

    tkIf,
    tkImport,
    tkIn,
    tkInitialize,
    tkIs,
    tkLen,
    tkMatch,
    tkMod,
    tkModule,
    tkNil,
    tkNot,
    tkOf,
    tkOr,
    tkOverlay,
    tkPacked,
    tkParamCount,
    tkParamStr,
    tkPointer,
    tkPrint,
    tkPrintLn,
    tkPublic,
    tkRecord,
    tkRepeat,
    tkResizeMem,
    tkReturn,
    tkRoutine,
    tkSet,
    tkSetLength,
    tkShl,
    tkShr,
    tkSize,
    tkTest,
    tkThen,
    tkThrow,
    tkThrowCode,
    tkTo,
    tkTrue,
    tkType,
    tkUntil,
    tkUtf8,
    tkVar,
    tkVarArgs,
    tkWhile,
    tkWStr,
    tkXor,

    // -- Primitive types (BNF Section 3 - Built-in Types) --
    // Registered as keywords with tcPrimitive category and C++23 mappings.
    // pointer is already listed above as a keyword; it is registered once
    // with tcPrimitive category so GetCppType works.
    tkInt8,
    tkInt16,
    tkInt32,
    tkInt64,
    tkUInt8,
    tkUInt16,
    tkUInt32,
    tkUInt64,
    tkFloat32,
    tkFloat64,
    tkBoolean,
    tkChar,
    tkWChar,
    tkString,
    tkWString,

    // -- Operators (BNF Section 4) --
    tkPlus,           // +
    tkMinus,          // -
    tkStar,           // *
    tkSlash,          // /
    tkEqual,          // =
    tkNotEqual,       // <>
    tkLess,           // <
    tkGreater,        // >
    tkLessEqual,      // <=
    tkGreaterEqual,   // >=
    tkAssign,         // :=
    tkPlusAssign,     // +=
    tkMinusAssign,    // -=
    tkStarAssign,     // *=
    tkSlashAssign,    // /=
    tkCaret,          // ^
    tkPipe,           // |
    tkAmpersand,      // &

    // -- Delimiters --
    tkColon,          // :
    tkSemicolon,      // ;
    tkComma,          // ,
    tkDot,            // .
    tkDotDot,         // ..
    tkEllipsis,       // ...
    tkLParen,         // (
    tkRParen,         // )
    tkLBracket,       // [
    tkRBracket        // ]
  );

  { TMyrToken }
  TMyrToken = record
    Kind: TMyrTokenKind;
    TokenText: string;        // canonical text (lowercased for keywords)
    RawText: string;          // exactly as it appeared in source
    LeadingTrivia: string;    // whitespace and comments preceding this token
    Location: TSourceRange;   // file, line, column
    Category: TMyrTokenCategory; // what family this token belongs to
    LiteralValue: TValue;     // parsed literal (Int64, UInt64, Double, or string)
    procedure Clear();
  end;

const

  { Lexer error codes }
  MYR_ERR_LEX_001 = 'LEX001';  // Unterminated string literal
  MYR_ERR_LEX_002 = 'LEX002';  // Unterminated block comment
  MYR_ERR_LEX_003 = 'LEX003';  // Invalid character
  MYR_ERR_LEX_004 = 'LEX004';  // Invalid hex literal
  MYR_ERR_LEX_005 = 'LEX005';  // Invalid escape sequence
  MYR_ERR_LEX_006 = 'LEX006';  // Invalid numeric literal
  MYR_ERR_LEX_007 = 'LEX007';  // Unexpected end of file
  MYR_ERR_LEX_008 = 'LEX008';  // Expected token
  MYR_ERR_LEX_009 = 'LEX009';  // File not found
  MYR_ERR_LEX_010 = 'LEX010';  // File read error

type

  { TMyrLexer }
  TMyrLexer = class(TBaseObject)
  private
    // Source state
    FSource: string;
    FFilename: string;
    FPos: UInt64;
    FLine: UInt64;
    FCol: UInt64;

    // Token storage and navigation
    FTokens: TList<TMyrToken>;
    FTokenIndex: UInt64;

    // Registration dictionaries
    FKeywords: TDictionary<string, TMyrTokenKind>;
    FCategories: TDictionary<TMyrTokenKind, TMyrTokenCategory>;
    FCppTypes: TDictionary<TMyrTokenKind, string>;

    // Source traversal
    function CurrentChar(): Char;
    function PeekChar(): Char;
    function PeekCharAt(const AOffset: Int64): Char;
    procedure Advance();
    function IsAtSourceEnd(): Boolean;
    function MakeLocation(const AStartLine: UInt64; const AStartCol: UInt64): TSourceRange;

    // Trivia and comment scanning
    function DoCollectTrivia(): string;
    procedure DoScanLineComment(var ATrivia: string);
    procedure DoScanBlockComment(var ATrivia: string);

    // Token scanning
    function DoScanToken(const ATrivia: string): TMyrToken;
    function DoScanIdentifier(): TMyrToken;
    function DoScanNumber(): TMyrToken;
    function DoScanStringLiteral(): TMyrToken;
    function DoScanWStringLiteral(): TMyrToken;
    function DoScanDirective(): TMyrToken;
    function DoScanOperator(): TMyrToken;
    procedure DoScanRawBlock();
    function DoProcessEscapeSeq(): Char;

    // Internal registration
    procedure RegisterKeywords();
    procedure RegisterPrimitives();
    procedure RegisterCategories();

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Tokenization
    function TokenizeString(const ASource: string; const AFilename: string): Boolean;
    function TokenizeFile(const AFilename: string): Boolean;

    // Keyword/type registration
    procedure AddKeyword(const AText: string; const AKind: TMyrTokenKind;
      const ACategory: TMyrTokenCategory); overload;
    procedure AddKeyword(const AText: string; const AKind: TMyrTokenKind;
      const ACategory: TMyrTokenCategory; const ACppType: string); overload;
    function IsKeyword(const AName: string): Boolean;

    // Navigation API (used by parser)
    function CurrentToken(): TMyrToken;
    function NextToken(): TMyrToken;
    function PeekToken(): TMyrToken;
    function PeekAt(const AOffset: Int64): TMyrToken;
    function Match(const AKind: TMyrTokenKind): Boolean;
    function Expect(const AKind: TMyrTokenKind): TMyrToken;
    function IsAtEnd(): Boolean;

    // Query helpers
    function IsDataType(const AKind: TMyrTokenKind): Boolean;
    function IsOperator(const AKind: TMyrTokenKind): Boolean;
    function GetCppType(const AKind: TMyrTokenKind): string;
    function GetCategory(const AKind: TMyrTokenKind): TMyrTokenCategory;
    function GetRegisteredWords(const ACategory: TMyrTokenCategory): TArray<string>;
    function TokenCount(): UInt64;
    function GetTokens(): TList<TMyrToken>;

    // Properties
    property SourceText: string read FSource;

    // Source reconstruction
    function ToSource(): string;
  end;

type

  // Forward declarations
  TMyrASTNode = class;
  TMyrDeclNode = class;
  TMyrExprNode = class;
  TMyrModuleNode = class;
  TMyrDirectiveNode = class;
  TMyrImportNode = class;
  TMyrTestBlockNode = class;
  TMyrConstDeclNode = class;
  TMyrTypeDeclNode = class;
  TMyrVarDeclNode = class;
  TMyrRoutineDeclNode = class;
  TMyrForwardTypeDeclNode = class;
  TMyrForwardRoutineDeclNode = class;
  TMyrParamDeclNode = class;
  TMyrRecordTypeNode = class;
  TMyrOverlayTypeNode = class;
  TMyrAnonRecordNode = class;
  TMyrAnonOverlayNode = class;
  TMyrFieldDeclNode = class;
  TMyrArrayTypeNode = class;
  TMyrPointerTypeNode = class;
  TMyrSetTypeNode = class;
  TMyrChoicesTypeNode = class;
  TMyrChoicesValueNode = class;
  TMyrRoutineTypeNode = class;
  TMyrTypeRefNode = class;
  TMyrOverloadGroupNode = class;
  TMyrAssignNode = class;
  TMyrCallStmtNode = class;
  TMyrIfNode = class;
  TMyrWhileNode = class;
  TMyrForNode = class;
  TMyrRepeatNode = class;
  TMyrBreakNode = class;
  TMyrContinueNode = class;
  TMyrMatchNode = class;
  TMyrMatchArmNode = class;
  TMyrMatchLabelNode = class;
  TMyrReturnNode = class;
  TMyrGuardNode = class;
  TMyrThrowNode = class;
  TMyrThrowCodeNode = class;
  TMyrCppBlockNode = class;
  TMyrCppExprNode = class;
  TMyrNewNode = class;
  TMyrDisposeNode = class;
  TMyrGetMemNode = class;
  TMyrFreeMemNode = class;
  TMyrResizeMemNode = class;
  TMyrSetLengthNode = class;
  TMyrPrintNode = class;
  TMyrAssertStmtNode = class;
  TMyrBinaryExprNode = class;
  TMyrUnaryExprNode = class;
  TMyrIntLiteralNode = class;
  TMyrFloatLiteralNode = class;
  TMyrStringLiteralNode = class;
  TMyrWStringLiteralNode = class;
  TMyrBoolLiteralNode = class;
  TMyrNilLiteralNode = class;
  TMyrIdentifierNode = class;
  TMyrDotAccessNode = class;
  TMyrIndexAccessNode = class;
  TMyrDerefNode = class;
  TMyrCallExprNode = class;
  TMyrSetLiteralExprNode = class;
  TMyrSetElementNode = class;
  TMyrRecordLiteralNode = class;
  TMyrFieldInitNode = class;
  TMyrTypeCastExprNode = class;
  TMyrIntrinsicExprNode = class;

  { TMyrModuleKind }
  TMyrModuleKind = (
    mkExe,
    mkDll,
    mkLib,
    mkUnit
  );

  { TMyrLinkage }
  TMyrLinkage = (
    lkDefault,          // no linkage spec given (defaults to C linkage)
    lkCLink,            // explicit clink
    lkCppLink           // explicit cpplink
  );

  { TMyrParamMode }
  TMyrParamMode = (
    pmConst,            // const (default per coding standards)
    pmVar,              // var (pass by reference, mutable)
    pmDefault           // no modifier specified in source
  );

  { TMyrAssignOp }
  TMyrAssignOp = (
    aoAssign,           // :=
    aoPlusAssign,       // +=
    aoMinusAssign,      // -=
    aoMulAssign,        // *=
    aoDivAssign         // /=
  );

  { TMyrBinaryOp }
  TMyrBinaryOp = (
    // Multiplicative (precedence 2)
    boMul,              // *
    boDiv,              // /
    boIntDiv,           // div
    boMod,              // mod
    boAnd,              // and
    boShl,              // shl
    boShr,              // shr
    // Additive (precedence 3)
    boAdd,              // +
    boSub,              // -
    boOr,               // or
    boXor,              // xor
    // Logical (disambiguated by semantics from bitwise boAnd/boOr)
    boLogicalAnd,       // and (when both operands are boolean)
    boLogicalOr,        // or  (when both operands are boolean)
    // Relational (precedence 4)
    boEq,               // =
    boNotEq,            // <>
    boLess,             // <
    boGreater,          // >
    boLessEq,           // <=
    boGreaterEq,        // >=
    boIn                // in
  );

  { TMyrUnaryOp }
  TMyrUnaryOp = (
    uoNot,              // not
    uoNegate,           // - (unary minus)
    uoPositive,         // + (unary plus)
    uoAddressOf         // address of
  );

  { TMyrAssertKind }
  TMyrAssertKind = (
    akAssert,           // assert(expr)
    akTrue,             // asserttrue(expr)
    akFalse,            // assertfalse(expr)
    akEq,               // asserteq(expected, actual)
    akEqF,              // asserteqf(expected, actual, epsilon)
    akNil,              // assertnil(expr)
    akNotNil,           // assertnotnil(expr)
    akFail              // assertfail("message")
  );

  { TMyrIntrinsicKind }
  TMyrIntrinsicKind = (
    ikLen,              // len(expr)
    ikSize,             // size(type_or_expr)
    ikUtf8,             // utf8(expr)
    ikCStr,             // cstr(expr)
    ikWStr,             // wstr(expr)
    ikParamCount,       // paramcount()
    ikParamStr,         // paramstr(expr)
    ikExcCode,          // exccode()
    ikExcMsg            // excmsg()
  );

  { TMyrASTNode }
  TMyrASTNode = class
  protected
    FLocation: TSourceRange;
  public
    constructor Create(); virtual;
    destructor Destroy(); override;
    procedure SetLocationEnd(const AEndLine: UInt64; const AEndColumn: UInt64);
    property Location: TSourceRange read FLocation write FLocation;
  end;

  { TMyrDeclNode }
  TMyrDeclNode = class(TMyrASTNode)
  protected
    FDeclName: string;
    FIsPublic: Boolean;
  public
    property DeclName: string read FDeclName write FDeclName;
    property IsPublic: Boolean read FIsPublic write FIsPublic;
  end;

  { TMyrExprNode }
  TMyrExprNode = class(TMyrASTNode)
  protected
    FResolvedType: TMyrASTNode;   // populated by semantic pass
  public
    property ResolvedType: TMyrASTNode read FResolvedType write FResolvedType;
  end;

  { TMyrModuleNode }
  TMyrModuleNode = class(TMyrASTNode)
  protected
    FModuleName: string;
    FModuleKind: TMyrModuleKind;
    FSourceFile: string;
    FDirectives: TObjectList<TMyrDirectiveNode>;
    FImports: TObjectList<TMyrImportNode>;
    FDeclarations: TObjectList<TMyrASTNode>;
    FInitBody: TObjectList<TMyrASTNode>;
    FFinalBody: TObjectList<TMyrASTNode>;
    FHasMainBody: Boolean;
    FMainBody: TObjectList<TMyrASTNode>;
    FTestBlocks: TObjectList<TMyrTestBlockNode>;
    FUnitTestMode: Boolean;
    FResolvedTarget: TMyrTargetKind;
    FResolvedTargetTriple: string;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property ModuleName: string read FModuleName write FModuleName;
    property ModuleKind: TMyrModuleKind read FModuleKind write FModuleKind;
    property SourceFile: string read FSourceFile write FSourceFile;
    property Directives: TObjectList<TMyrDirectiveNode> read FDirectives;
    property Imports: TObjectList<TMyrImportNode> read FImports;
    property Declarations: TObjectList<TMyrASTNode> read FDeclarations;
    property InitBody: TObjectList<TMyrASTNode> read FInitBody;
    property FinalBody: TObjectList<TMyrASTNode> read FFinalBody;
    property HasMainBody: Boolean read FHasMainBody write FHasMainBody;
    property MainBody: TObjectList<TMyrASTNode> read FMainBody;
    property TestBlocks: TObjectList<TMyrTestBlockNode> read FTestBlocks;
    property UnitTestMode: Boolean read FUnitTestMode write FUnitTestMode;
    property ResolvedTarget: TMyrTargetKind read FResolvedTarget write FResolvedTarget;
    property ResolvedTargetTriple: string read FResolvedTargetTriple write FResolvedTargetTriple;
  end;

  { TMyrDirectiveNode }
  TMyrDirectiveNode = class(TMyrASTNode)
  protected
    FDirectiveName: string;
    FDirectiveValue: string;
    FDirectiveValue2: string;
    FResolvedValue: string;
    FResolvedValue2: string;
  public
    property DirectiveName: string read FDirectiveName write FDirectiveName;
    property DirectiveValue: string read FDirectiveValue write FDirectiveValue;
    property DirectiveValue2: string read FDirectiveValue2 write FDirectiveValue2;
    property ResolvedValue: string read FResolvedValue write FResolvedValue;
    property ResolvedValue2: string read FResolvedValue2 write FResolvedValue2;
  end;

  { TMyrImportNode }
  TMyrImportNode = class(TMyrASTNode)
  protected
    FModuleName: string;
    FResolvedModule: TMyrModuleNode;  // populated by semantic pass
  public
    property ModuleName: string read FModuleName write FModuleName;
    property ResolvedModule: TMyrModuleNode read FResolvedModule write FResolvedModule;
  end;

  { TMyrTestBlockNode }
  TMyrTestBlockNode = class(TMyrASTNode)
  protected
    FTestName: string;
    FCppTestName: string;
    FLocals: TObjectList<TMyrVarDeclNode>;
    FBody: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property TestName: string read FTestName write FTestName;
    property CppTestName: string read FCppTestName write FCppTestName;
    property Locals: TObjectList<TMyrVarDeclNode> read FLocals;
    property Body: TObjectList<TMyrASTNode> read FBody;
  end;

  { TMyrConstDeclNode }
  TMyrConstDeclNode = class(TMyrDeclNode)
  protected
    FTypeExpr: TMyrASTNode;       // nil if type is inferred
    FValueExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property TypeExpr: TMyrASTNode read FTypeExpr write FTypeExpr;
    property ValueExpr: TMyrASTNode read FValueExpr write FValueExpr;
  end;

  { TMyrTypeDeclNode }
  TMyrTypeDeclNode = class(TMyrDeclNode)
  protected
    FTypeDef: TMyrASTNode;        // record/overlay/array/pointer/set/choices/routine/typeref
    FPrimitiveKind: TMyrTokenKind;  // tkChar, tkInt32, etc. for synthetic primitives; tkUnknown otherwise
    FCppTypeName: string;          // C++23 type name for primitives (e.g. 'int32_t', 'double')
    FByteSize: Integer;        // size in bytes (set by semantics for primitives; 0 = use backend TypeSize)
  public
    destructor Destroy(); override;
    property TypeDef: TMyrASTNode read FTypeDef write FTypeDef;
    property PrimitiveKind: TMyrTokenKind read FPrimitiveKind write FPrimitiveKind;
    property CppTypeName: string read FCppTypeName write FCppTypeName;
    property ByteSize: Integer read FByteSize write FByteSize;
  end;

  { TMyrVarDeclNode }
  TMyrVarDeclNode = class(TMyrDeclNode)
  protected
    FTypeExpr: TMyrASTNode;
    FInitExpr: TMyrASTNode;       // nil if no initializer
    FIsExternal: Boolean;
    FExternalLib: string;
    FResolvedExternalLib: string;
    FExternalName: string;
    FResolvedExternalName: string;
  public
    destructor Destroy(); override;
    property TypeExpr: TMyrASTNode read FTypeExpr write FTypeExpr;
    property InitExpr: TMyrASTNode read FInitExpr write FInitExpr;
    property IsExternal: Boolean read FIsExternal write FIsExternal;
    property ExternalLib: string read FExternalLib write FExternalLib;
    property ResolvedExternalLib: string read FResolvedExternalLib write FResolvedExternalLib;
    property ExternalName: string read FExternalName write FExternalName;
    property ResolvedExternalName: string read FResolvedExternalName write FResolvedExternalName;
  end;

  { TMyrRoutineDeclNode }
  TMyrRoutineDeclNode = class(TMyrDeclNode)
  protected
    FLinkage: TMyrLinkage;
    FParams: TObjectList<TMyrParamDeclNode>;
    FReturnType: TMyrASTNode;     // nil for procedures
    FIsExternal: Boolean;
    FExternalLib: string;
    FResolvedExternalLib: string;
    FExternalName: string;
    FResolvedExternalName: string;
    FIsVariadic: Boolean;
    FLocalTypes: TObjectList<TMyrTypeDeclNode>;
    FLocalConsts: TObjectList<TMyrConstDeclNode>;
    FLocalVars: TObjectList<TMyrVarDeclNode>;
    FBody: TObjectList<TMyrASTNode>;  // nil for external routines
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Linkage: TMyrLinkage read FLinkage write FLinkage;
    property Params: TObjectList<TMyrParamDeclNode> read FParams;
    property ReturnType: TMyrASTNode read FReturnType write FReturnType;
    property IsExternal: Boolean read FIsExternal write FIsExternal;
    property ExternalLib: string read FExternalLib write FExternalLib;
    property ResolvedExternalLib: string read FResolvedExternalLib write FResolvedExternalLib;
    property ExternalName: string read FExternalName write FExternalName;
    property ResolvedExternalName: string read FResolvedExternalName write FResolvedExternalName;
    property IsVariadic: Boolean read FIsVariadic write FIsVariadic;
    property LocalTypes: TObjectList<TMyrTypeDeclNode> read FLocalTypes;
    property LocalConsts: TObjectList<TMyrConstDeclNode> read FLocalConsts;
    property LocalVars: TObjectList<TMyrVarDeclNode> read FLocalVars;
    property Body: TObjectList<TMyrASTNode> read FBody;
  end;

  { TMyrOverloadGroupNode }
  // Groups multiple routines with the same name but different signatures.
  // Non-owning: routines are owned by the module's declaration list.
  TMyrOverloadGroupNode = class(TMyrDeclNode)
  protected
    FOverloads: TList<TMyrRoutineDeclNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Overloads: TList<TMyrRoutineDeclNode> read FOverloads;
  end;

  { TMyrForwardTypeDeclNode }
  // Forward type declaration: forward type TFoo;
  // Only valid in pointer-to contexts until full definition is seen
  TMyrForwardTypeDeclNode = class(TMyrDeclNode)
  protected
    FResolvedDecl: TMyrASTNode;   // populated by semantic pass -- points to full type decl
  public
    property ResolvedDecl: TMyrASTNode read FResolvedDecl write FResolvedDecl;
  end;

  { TMyrForwardRoutineDeclNode }
  // Forward routine declaration: forward routine Foo(x: int32): int32;
  // Carries full signature so calls are valid immediately
  TMyrForwardRoutineDeclNode = class(TMyrDeclNode)
  protected
    FLinkage: TMyrLinkage;
    FParams: TObjectList<TMyrParamDeclNode>;
    FReturnType: TMyrASTNode;
    FIsVariadic: Boolean;
    FResolvedDecl: TMyrASTNode;   // populated by semantic pass -- points to full routine decl
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Linkage: TMyrLinkage read FLinkage write FLinkage;
    property Params: TObjectList<TMyrParamDeclNode> read FParams;
    property ReturnType: TMyrASTNode read FReturnType write FReturnType;
    property IsVariadic: Boolean read FIsVariadic write FIsVariadic;
    property ResolvedDecl: TMyrASTNode read FResolvedDecl write FResolvedDecl;
  end;

  { TMyrParamDeclNode }
  TMyrParamDeclNode = class(TMyrASTNode)
  protected
    FParamName: string;
    FParamMode: TMyrParamMode;
    FTypeExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property ParamName: string read FParamName write FParamName;
    property ParamMode: TMyrParamMode read FParamMode write FParamMode;
    property TypeExpr: TMyrASTNode read FTypeExpr write FTypeExpr;
  end;

  { TMyrRecordTypeNode }
  TMyrRecordTypeNode = class(TMyrASTNode)
  protected
    FIsPacked: Boolean;
    FAlignment: Integer;         // 0 = default alignment
    FBaseType: TMyrASTNode;       // nil = no inheritance
    FFields: TObjectList<TMyrASTNode>;  // TMyrFieldDeclNode or TMyrAnonOverlayNode
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IsPacked: Boolean read FIsPacked write FIsPacked;
    property Alignment: Integer read FAlignment write FAlignment;
    property BaseType: TMyrASTNode read FBaseType write FBaseType;
    property Fields: TObjectList<TMyrASTNode> read FFields;
  end;

  { TMyrOverlayTypeNode }
  TMyrOverlayTypeNode = class(TMyrASTNode)
  protected
    FFields: TObjectList<TMyrASTNode>;  // TMyrFieldDeclNode or TMyrAnonRecordNode
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Fields: TObjectList<TMyrASTNode> read FFields;
  end;

  { TMyrAnonRecordNode }
  TMyrAnonRecordNode = class(TMyrASTNode)
  protected
    FIsPacked: Boolean;
    FFields: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IsPacked: Boolean read FIsPacked write FIsPacked;
    property Fields: TObjectList<TMyrASTNode> read FFields;
  end;

  { TMyrAnonOverlayNode }
  TMyrAnonOverlayNode = class(TMyrASTNode)
  protected
    FFields: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Fields: TObjectList<TMyrASTNode> read FFields;
  end;

  { TMyrFieldDeclNode }
  TMyrFieldDeclNode = class(TMyrASTNode)
  protected
    FFieldName: string;
    FTypeExpr: TMyrASTNode;
    FBitWidth: Integer;          // 0 = no bit field
  public
    destructor Destroy(); override;
    property FieldName: string read FFieldName write FFieldName;
    property TypeExpr: TMyrASTNode read FTypeExpr write FTypeExpr;
    property BitWidth: Integer read FBitWidth write FBitWidth;
  end;

  { TMyrArrayTypeNode }
  TMyrArrayTypeNode = class(TMyrASTNode)
  protected
    FElementType: TMyrASTNode;
    FIsDynamic: Boolean;         // true = no bounds specified
    FLowBound: Int64;
    FHighBound: Int64;
  public
    destructor Destroy(); override;
    property ElementType: TMyrASTNode read FElementType write FElementType;
    property IsDynamic: Boolean read FIsDynamic write FIsDynamic;
    property LowBound: Int64 read FLowBound write FLowBound;
    property HighBound: Int64 read FHighBound write FHighBound;
  end;

  { TMyrPointerTypeNode }
  TMyrPointerTypeNode = class(TMyrASTNode)
  protected
    FTargetType: TMyrASTNode;     // nil = untyped pointer
    FIsConstTarget: Boolean;
  public
    destructor Destroy(); override;
    property TargetType: TMyrASTNode read FTargetType write FTargetType;
    property IsConstTarget: Boolean read FIsConstTarget write FIsConstTarget;
  end;

  { TMyrSetTypeNode }
  TMyrSetTypeNode = class(TMyrASTNode)
  protected
    FElementType: TMyrASTNode;    // nil for bare "set"
    FIsRangeForm: Boolean;       // true = integer..integer form
    FRangeLow: Int64;
    FRangeHigh: Int64;
  public
    destructor Destroy(); override;
    property ElementType: TMyrASTNode read FElementType write FElementType;
    property IsRangeForm: Boolean read FIsRangeForm write FIsRangeForm;
    property RangeLow: Int64 read FRangeLow write FRangeLow;
    property RangeHigh: Int64 read FRangeHigh write FRangeHigh;
  end;

  { TMyrChoicesTypeNode }
  TMyrChoicesTypeNode = class(TMyrASTNode)
  protected
    FMembers: TObjectList<TMyrChoicesValueNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Members: TObjectList<TMyrChoicesValueNode> read FMembers;
  end;

  { TMyrChoicesValueNode }
  TMyrChoicesValueNode = class(TMyrASTNode)
  protected
    FMemberName: string;
    FValueExpr: TMyrASTNode;      // nil = auto-assigned
  public
    destructor Destroy(); override;
    property MemberName: string read FMemberName write FMemberName;
    property ValueExpr: TMyrASTNode read FValueExpr write FValueExpr;
  end;

  { TMyrRoutineTypeNode }
  TMyrRoutineTypeNode = class(TMyrASTNode)
  protected
    FLinkage: TMyrLinkage;
    FParams: TObjectList<TMyrParamDeclNode>;
    FReturnType: TMyrASTNode;     // nil for procedure type
    FIsVariadic: Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Linkage: TMyrLinkage read FLinkage write FLinkage;
    property Params: TObjectList<TMyrParamDeclNode> read FParams;
    property ReturnType: TMyrASTNode read FReturnType write FReturnType;
    property IsVariadic: Boolean read FIsVariadic write FIsVariadic;
  end;

  { TMyrTypeRefNode }
  TMyrTypeRefNode = class(TMyrExprNode)
  protected
    FTokenKind: TMyrTokenKind;    // tkInt32 etc. for primitives, tkIdentifier for user types
    FQualParts: TArray<string>;  // ['ModName', 'TypeName'] for qualified access
    FResolvedDecl: TMyrASTNode;   // populated by semantic pass
    FCppTypeText: string;        // C++23 type string, set by parser/semantics
  public
    property TokenKind: TMyrTokenKind read FTokenKind write FTokenKind;
    property QualParts: TArray<string> read FQualParts write FQualParts;
    property ResolvedDecl: TMyrASTNode read FResolvedDecl write FResolvedDecl;
    property CppTypeText: string read FCppTypeText write FCppTypeText;
  end;

  { TMyrAssignNode }
  TMyrAssignNode = class(TMyrASTNode)
  protected
    FTarget: TMyrASTNode;         // designator (expression node)
    FOp: TMyrAssignOp;
    FValueExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property Target: TMyrASTNode read FTarget write FTarget;
    property Op: TMyrAssignOp read FOp write FOp;
    property ValueExpr: TMyrASTNode read FValueExpr write FValueExpr;
  end;

  { TMyrCallStmtNode }
  TMyrCallStmtNode = class(TMyrASTNode)
  protected
    FCallExpr: TMyrASTNode;       // typically a TMyrCallExprNode
  public
    destructor Destroy(); override;
    property CallExpr: TMyrASTNode read FCallExpr write FCallExpr;
  end;

  { TMyrIfNode }
  TMyrIfNode = class(TMyrASTNode)
  protected
    FCondition: TMyrASTNode;
    FThenBody: TObjectList<TMyrASTNode>;
    FElseBody: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Condition: TMyrASTNode read FCondition write FCondition;
    property ThenBody: TObjectList<TMyrASTNode> read FThenBody;
    property ElseBody: TObjectList<TMyrASTNode> read FElseBody;
  end;

  { TMyrWhileNode }
  TMyrWhileNode = class(TMyrASTNode)
  protected
    FCondition: TMyrASTNode;
    FBody: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Condition: TMyrASTNode read FCondition write FCondition;
    property Body: TObjectList<TMyrASTNode> read FBody;
  end;

  { TMyrForNode }
  TMyrForNode = class(TMyrASTNode)
  protected
    FIteratorName: string;
    FStartExpr: TMyrASTNode;
    FEndExpr: TMyrASTNode;
    FIsDownTo: Boolean;
    FBody: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IteratorName: string read FIteratorName write FIteratorName;
    property StartExpr: TMyrASTNode read FStartExpr write FStartExpr;
    property EndExpr: TMyrASTNode read FEndExpr write FEndExpr;
    property IsDownTo: Boolean read FIsDownTo write FIsDownTo;
    property Body: TObjectList<TMyrASTNode> read FBody;
  end;

  { TMyrRepeatNode }
  TMyrRepeatNode = class(TMyrASTNode)
  protected
    FBody: TObjectList<TMyrASTNode>;
    FCondition: TMyrASTNode;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Body: TObjectList<TMyrASTNode> read FBody;
    property Condition: TMyrASTNode read FCondition write FCondition;
  end;

  { TMyrBreakNode }
  TMyrBreakNode = class(TMyrASTNode);

  { TMyrContinueNode }
  TMyrContinueNode = class(TMyrASTNode);

  { TMyrMatchNode }
  TMyrMatchNode = class(TMyrASTNode)
  protected
    FExpr: TMyrASTNode;
    FArms: TObjectList<TMyrMatchArmNode>;
    FElseBody: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Expr: TMyrASTNode read FExpr write FExpr;
    property Arms: TObjectList<TMyrMatchArmNode> read FArms;
    property ElseBody: TObjectList<TMyrASTNode> read FElseBody;
  end;

  { TMyrMatchArmNode }
  TMyrMatchArmNode = class(TMyrASTNode)
  protected
    FLabels: TObjectList<TMyrMatchLabelNode>;
    FBody: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Labels: TObjectList<TMyrMatchLabelNode> read FLabels;
    property Body: TObjectList<TMyrASTNode> read FBody;
  end;

  { TMyrMatchLabelNode }
  TMyrMatchLabelNode = class(TMyrASTNode)
  protected
    FLowExpr: TMyrASTNode;
    FHighExpr: TMyrASTNode;       // nil = single value, not a range
  public
    destructor Destroy(); override;
    property LowExpr: TMyrASTNode read FLowExpr write FLowExpr;
    property HighExpr: TMyrASTNode read FHighExpr write FHighExpr;
  end;

  { TMyrReturnNode }
  TMyrReturnNode = class(TMyrASTNode)
  protected
    FValueExpr: TMyrASTNode;      // nil = void return
  public
    destructor Destroy(); override;
    property ValueExpr: TMyrASTNode read FValueExpr write FValueExpr;
  end;

  { TMyrGuardNode }
  TMyrGuardNode = class(TMyrASTNode)
  protected
    FGuardBody: TObjectList<TMyrASTNode>;
    FExceptBody: TObjectList<TMyrASTNode>;   // nil = no except clause
    FFinallyBody: TObjectList<TMyrASTNode>;  // nil = no finally clause
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property GuardBody: TObjectList<TMyrASTNode> read FGuardBody;
    property ExceptBody: TObjectList<TMyrASTNode> read FExceptBody;
    property FinallyBody: TObjectList<TMyrASTNode> read FFinallyBody;
  end;

  { TMyrThrowNode }
  TMyrThrowNode = class(TMyrASTNode)
  protected
    FMessageExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property MessageExpr: TMyrASTNode read FMessageExpr write FMessageExpr;
  end;

  { TMyrThrowCodeNode }
  TMyrThrowCodeNode = class(TMyrASTNode)
  protected
    FCodeExpr: TMyrASTNode;
    FMessageExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property CodeExpr: TMyrASTNode read FCodeExpr write FCodeExpr;
    property MessageExpr: TMyrASTNode read FMessageExpr write FMessageExpr;
  end;

  { TMyrCppBlockNode }
  // cppstart header|source ... cppend -- injects raw C/C++ into output
  TMyrCppBlockNode = class(TMyrASTNode)
  protected
    FTarget: string;    // 'header' or 'source'
    FRawText: string;   // verbatim C/C++ text
  public
    property Target: string read FTarget write FTarget;
    property RawText: string read FRawText write FRawText;
  end;

  { TMyrCppExprNode }
  // cpp(expr) -- injects raw C/C++ expression inline
  TMyrCppExprNode = class(TMyrExprNode)
  protected
    FArgExpr: TMyrExprNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TMyrExprNode read FArgExpr write FArgExpr;
  end;

  { TMyrNewNode }
  TMyrNewNode = class(TMyrASTNode)
  protected
    FArgExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TMyrASTNode read FArgExpr write FArgExpr;
  end;

  { TMyrDisposeNode }
  TMyrDisposeNode = class(TMyrASTNode)
  protected
    FArgExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TMyrASTNode read FArgExpr write FArgExpr;
  end;

  { TMyrGetMemNode }
  TMyrGetMemNode = class(TMyrASTNode)
  protected
    FArgExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TMyrASTNode read FArgExpr write FArgExpr;
  end;

  { TMyrFreeMemNode }
  TMyrFreeMemNode = class(TMyrASTNode)
  protected
    FArgExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TMyrASTNode read FArgExpr write FArgExpr;
  end;

  { TMyrResizeMemNode }
  TMyrResizeMemNode = class(TMyrASTNode)
  protected
    FPtrExpr: TMyrASTNode;
    FSizeExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property PtrExpr: TMyrASTNode read FPtrExpr write FPtrExpr;
    property SizeExpr: TMyrASTNode read FSizeExpr write FSizeExpr;
  end;

  { TMyrSetLengthNode }
  TMyrSetLengthNode = class(TMyrASTNode)
  protected
    FTargetExpr: TMyrASTNode;
    FLengthExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property TargetExpr: TMyrASTNode read FTargetExpr write FTargetExpr;
    property LengthExpr: TMyrASTNode read FLengthExpr write FLengthExpr;
  end;

  { TMyrPrintNode }
  TMyrPrintNode = class(TMyrASTNode)
  protected
    FIsLn: Boolean;
    FArgs: TObjectList<TMyrASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IsLn: Boolean read FIsLn write FIsLn;
    property Args: TObjectList<TMyrASTNode> read FArgs;
  end;

  { TMyrAssertStmtNode }
  TMyrAssertStmtNode = class(TMyrASTNode)
  protected
    FAssertKind: TMyrAssertKind;
    FArgs: TObjectList<TMyrASTNode>;  // 1-3 args depending on kind
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property AssertKind: TMyrAssertKind read FAssertKind write FAssertKind;
    property Args: TObjectList<TMyrASTNode> read FArgs;
  end;

  { TMyrBinaryExprNode }
  TMyrBinaryExprNode = class(TMyrExprNode)
  protected
    FLeft: TMyrASTNode;
    FOp: TMyrBinaryOp;
    FRight: TMyrASTNode;
  public
    destructor Destroy(); override;
    property Left: TMyrASTNode read FLeft write FLeft;
    property Op: TMyrBinaryOp read FOp write FOp;
    property Right: TMyrASTNode read FRight write FRight;
  end;

  { TMyrUnaryExprNode }
  TMyrUnaryExprNode = class(TMyrExprNode)
  protected
    FOp: TMyrUnaryOp;
    FOperand: TMyrASTNode;
  public
    destructor Destroy(); override;
    property Op: TMyrUnaryOp read FOp write FOp;
    property Operand: TMyrASTNode read FOperand write FOperand;
  end;

  { TMyrIntLiteralNode }
  TMyrIntLiteralNode = class(TMyrExprNode)
  protected
    FIntValue: Int64;
  public
    property IntValue: Int64 read FIntValue write FIntValue;
  end;

  { TMyrFloatLiteralNode }
  TMyrFloatLiteralNode = class(TMyrExprNode)
  protected
    FFloatValue: Double;
    FHasSuffix: Boolean;         // true if f/F suffix present (forces float32)
  public
    property FloatValue: Double read FFloatValue write FFloatValue;
    property HasSuffix: Boolean read FHasSuffix write FHasSuffix;
  end;

  { TMyrStringLiteralNode }
  TMyrStringLiteralNode = class(TMyrExprNode)
  protected
    FStringValue: string;
  public
    property StringValue: string read FStringValue write FStringValue;
  end;

  { TMyrWStringLiteralNode }
  TMyrWStringLiteralNode = class(TMyrExprNode)
  protected
    FStringValue: string;
  public
    property StringValue: string read FStringValue write FStringValue;
  end;

  { TMyrBoolLiteralNode }
  TMyrBoolLiteralNode = class(TMyrExprNode)
  protected
    FBoolValue: Boolean;
  public
    property BoolValue: Boolean read FBoolValue write FBoolValue;
  end;

  { TMyrNilLiteralNode }
  TMyrNilLiteralNode = class(TMyrExprNode);

  { TMyrIdentifierNode }
  TMyrIdentifierNode = class(TMyrExprNode)
  protected
    FIdentName: string;
    FResolvedDecl: TMyrASTNode;   // populated by semantic pass
  public
    property IdentName: string read FIdentName write FIdentName;
    property ResolvedDecl: TMyrASTNode read FResolvedDecl write FResolvedDecl;
  end;

  { TMyrDotAccessKind }
  TMyrDotAccessKind = (
    dakField,           // record/struct field access: obj.field
    dakModule,          // module-qualified access: Module.Symbol
    dakChoices          // choices (enum) member: MyEnum.Value
  );

  { TMyrDotAccessNode }
  TMyrDotAccessNode = class(TMyrExprNode)
  protected
    FBaseExpr: TMyrASTNode;
    FMemberName: string;
    FResolvedDecl: TMyrASTNode;   // populated by semantic pass
    FAccessKind: TMyrDotAccessKind; // set by semantic pass
  public
    destructor Destroy(); override;
    property BaseExpr: TMyrASTNode read FBaseExpr write FBaseExpr;
    property MemberName: string read FMemberName write FMemberName;
    property ResolvedDecl: TMyrASTNode read FResolvedDecl write FResolvedDecl;
    property AccessKind: TMyrDotAccessKind read FAccessKind write FAccessKind;
  end;

  { TMyrIndexAccessNode }
  TMyrIndexAccessNode = class(TMyrExprNode)
  protected
    FBaseExpr: TMyrASTNode;
    FIndexExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property BaseExpr: TMyrASTNode read FBaseExpr write FBaseExpr;
    property IndexExpr: TMyrASTNode read FIndexExpr write FIndexExpr;
  end;

  { TMyrDerefNode }
  TMyrDerefNode = class(TMyrExprNode)
  protected
    FBaseExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property BaseExpr: TMyrASTNode read FBaseExpr write FBaseExpr;
  end;

  { TMyrCallExprNode }
  TMyrCallExprNode = class(TMyrExprNode)
  protected
    FCallee: TMyrASTNode;
    FArgs: TObjectList<TMyrASTNode>;
    FResolvedRoutine: TMyrASTNode;  // populated by semantic pass
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Callee: TMyrASTNode read FCallee write FCallee;
    property Args: TObjectList<TMyrASTNode> read FArgs;
    property ResolvedRoutine: TMyrASTNode read FResolvedRoutine write FResolvedRoutine;
  end;

  { TMyrSetLiteralExprNode }
  TMyrSetLiteralExprNode = class(TMyrExprNode)
  protected
    FElements: TObjectList<TMyrSetElementNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Elements: TObjectList<TMyrSetElementNode> read FElements;
  end;

  { TMyrSetElementNode }
  TMyrSetElementNode = class(TMyrASTNode)
  protected
    FLowExpr: TMyrASTNode;
    FHighExpr: TMyrASTNode;       // nil = single element, not a range
  public
    destructor Destroy(); override;
    property LowExpr: TMyrASTNode read FLowExpr write FLowExpr;
    property HighExpr: TMyrASTNode read FHighExpr write FHighExpr;
  end;

  { TMyrRecordLiteralNode }
  TMyrRecordLiteralNode = class(TMyrExprNode)
  protected
    FTypeName: string;
    FModuleName: string;
    FFieldInits: TObjectList<TMyrFieldInitNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property TypeName: string read FTypeName write FTypeName;
    property ModuleName: string read FModuleName write FModuleName;
    property FieldInits: TObjectList<TMyrFieldInitNode> read FFieldInits;
  end;

  { TMyrFieldInitNode }
  TMyrFieldInitNode = class(TMyrASTNode)
  protected
    FFieldName: string;
    FValueExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property FieldName: string read FFieldName write FFieldName;
    property ValueExpr: TMyrASTNode read FValueExpr write FValueExpr;
  end;

  { TMyrTypeCastExprNode }
  TMyrTypeCastExprNode = class(TMyrExprNode)
  protected
    FTargetType: TMyrASTNode;
    FExpr: TMyrASTNode;
  public
    destructor Destroy(); override;
    property TargetType: TMyrASTNode read FTargetType write FTargetType;
    property Expr: TMyrASTNode read FExpr write FExpr;
  end;

  { TMyrIntrinsicExprNode }
  TMyrIntrinsicExprNode = class(TMyrExprNode)
  protected
    FIntrinsicKind: TMyrIntrinsicKind;
    FArgs: TObjectList<TMyrASTNode>;  // 0-1 args depending on intrinsic
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IntrinsicKind: TMyrIntrinsicKind read FIntrinsicKind write FIntrinsicKind;
    property Args: TObjectList<TMyrASTNode> read FArgs;
  end;

  { TMyrMasterAST }
  TMyrMasterAST = class(TBaseObject)
  protected
    FModules: TObjectList<TMyrModuleNode>;
    FModuleMap: TDictionary<string, TMyrModuleNode>;
    FPendingQueue: TQueue<string>;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Add a parsed module to the master tree
    procedure AddModule(const AModule: TMyrModuleNode);

    // Check if a module has already been parsed
    function HasModule(const AModuleName: string): Boolean;

    // Retrieve a module by name
    function GetModule(const AModuleName: string): TMyrModuleNode;

    // Work queue management for import processing
    procedure EnqueuePending(const AModuleName: string);
    function DequeuePending(): string;
    function HasPending(): Boolean;

    // Module count
    function ModuleCount(): Integer;

    // Indexed access to modules (source order)
    function GetModuleAt(const AIndex: Integer): TMyrModuleNode;

    property Modules: TObjectList<TMyrModuleNode> read FModules;
  end;

{ Parser - Interface }

const
  MYR_ERR_PAR_001 = 'PAR001';  // Unexpected token
  MYR_ERR_PAR_002 = 'PAR002';  // Expected token not found
  MYR_ERR_PAR_003 = 'PAR003';  // Invalid module kind
  MYR_ERR_PAR_004 = 'PAR004';  // Duplicate import
  MYR_ERR_PAR_005 = 'PAR005';  // Invalid type definition
  MYR_ERR_PAR_006 = 'PAR006';  // Invalid statement
  MYR_ERR_PAR_007 = 'PAR007';  // Invalid expression
  MYR_ERR_PAR_008 = 'PAR008';  // Expected identifier
  MYR_ERR_PAR_009 = 'PAR009';  // Invalid directive
  MYR_ERR_PAR_010 = 'PAR010';  // Invalid match arm
  MYR_ERR_PAR_020 = 'PAR020';  // Conditional directive missing identifier
  MYR_ERR_PAR_021 = 'PAR021';  // Unmatched @elseif/@else/@endif
  MYR_ERR_PAR_022 = 'PAR022';  // Unterminated @ifdef/@ifndef block

type

  { TMyrCondState }
  TMyrCondState = record
    Active: Boolean;
    HadTrue: Boolean;
    HadElse: Boolean;
    ParentActive: Boolean;
  end;

  { TMyrParser }
  TMyrParser = class(TBaseObject)
  private
    FLexer: TMyrLexer;
    FMasterAST: TMyrMasterAST;
    FLastConsumedLoc: TSourceRange;

    // Conditional compilation
    FDefines: TDictionary<string, string>;
    FCondStack: TList<TMyrCondState>;
    procedure DoProcessConditionals();
    procedure DoSkipFalseBranch();
    procedure DoSetupPredefinedDefines(const AModuleKind: TMyrModuleKind);

    // Token helpers
    function PeekAt(const AOffset: Int64): TMyrToken;
    function Match(const AKind: TMyrTokenKind): Boolean;
    function Expect(const AKind: TMyrTokenKind): TMyrToken;
    function Check(const AKind: TMyrTokenKind): Boolean;
    procedure OptionalSemicolon();
    procedure ExpectBlockEnd(const AConstruct: string;
      const AStartLocation: TSourceRange);

    // Precedence
    function GetPrecedence(const AKind: TMyrTokenKind): Integer;
    function IsRelOp(const AKind: TMyrTokenKind): Boolean;
    function IsAddOp(const AKind: TMyrTokenKind): Boolean;
    function IsMulOp(const AKind: TMyrTokenKind): Boolean;
    function IsAssignOp(const AKind: TMyrTokenKind): Boolean;
    function IsStatementStart(const AKind: TMyrTokenKind): Boolean;
    function TokenToBinaryOp(const AKind: TMyrTokenKind): TMyrBinaryOp;
    function TokenToAssignOp(const AKind: TMyrTokenKind): TMyrAssignOp;

    // Module structure
    procedure DoParseDirectives(const AModule: TMyrModuleNode);
    procedure DoParseImportClause(const AModule: TMyrModuleNode);
    procedure DoParseDeclarations(const AModule: TMyrModuleNode);
    procedure DoParseInitializeBlock(const AModule: TMyrModuleNode);
    procedure DoParseFinalizeBlock(const AModule: TMyrModuleNode);
    procedure DoParseMainBody(const AModule: TMyrModuleNode);
    procedure DoParseTestBlocks(const AModule: TMyrModuleNode);

    // Declarations
    function DoParseConstDecl(const AIsPublic: Boolean): TMyrConstDeclNode;
    function DoParseTypeDecl(const AIsPublic: Boolean): TMyrTypeDeclNode;
    function DoParseVarDecl(const AIsPublic: Boolean): TMyrVarDeclNode;
    function DoParseRoutineDecl(const AIsPublic: Boolean): TMyrRoutineDeclNode;
    function DoParseForwardDecl(): TMyrASTNode;
    procedure DoParseFormalParams(const ARoutine: TMyrRoutineDeclNode);
    function DoParseParamDecl(): TMyrParamDeclNode;
    procedure DoParseRoutineBody(const ARoutine: TMyrRoutineDeclNode);

    // Type definitions
    function DoParseTypeDef(): TMyrASTNode;
    function DoParseRecordType(): TMyrRecordTypeNode;
    function DoParseOverlayType(): TMyrOverlayTypeNode;
    function DoParseArrayType(): TMyrArrayTypeNode;
    function DoParsePointerType(): TMyrPointerTypeNode;
    function DoParseSetType(): TMyrSetTypeNode;
    function DoParseChoicesType(): TMyrChoicesTypeNode;
    function DoParseRoutineTypeDef(): TMyrRoutineTypeNode;
    function DoParseTypeExpr(): TMyrASTNode;
    function DoParseFieldDecl(): TMyrFieldDeclNode;

    // Statements
    function DoParseStatementSeq(const ATerminators: array of TMyrTokenKind): TObjectList<TMyrASTNode>;
    function DoParseStatement(): TMyrASTNode;
    function DoParseAssignOrCall(): TMyrASTNode;
    function DoParseIfStmt(): TMyrIfNode;
    function DoParseWhileStmt(): TMyrWhileNode;
    function DoParseForStmt(): TMyrForNode;
    function DoParseRepeatStmt(): TMyrRepeatNode;
    function DoParseMatchStmt(): TMyrMatchNode;
    function DoParseMatchArm(): TMyrMatchArmNode;
    function DoParseReturnStmt(): TMyrReturnNode;
    function DoParseGuardStmt(): TMyrGuardNode;
    function DoParseThrowStmt(): TMyrASTNode;
    function DoParseNewStmt(): TMyrNewNode;
    function DoParseDisposeStmt(): TMyrDisposeNode;
    function DoParseGetMemStmt(): TMyrGetMemNode;
    function DoParseFreeMemStmt(): TMyrFreeMemNode;
    function DoParseResizeMemStmt(): TMyrResizeMemNode;
    function DoParseSetLengthStmt(): TMyrSetLengthNode;
    function DoParsePrintStmt(): TMyrPrintNode;
    function DoParseAssertStmt(): TMyrAssertStmtNode;
    function DoParseCppBlock(): TMyrCppBlockNode;
    function DoParseCppStmt(): TMyrASTNode;
    function DoParseCppExpr(): TMyrCppExprNode;

    // Expressions (Pratt parser)
    function DoParseExpression(): TMyrASTNode;
    function DoParsePrecedence(const AMinPrec: Integer): TMyrASTNode;
    function DoParsePrefix(): TMyrASTNode;
    function DoParseDesignator(const ABase: TMyrASTNode): TMyrASTNode;
    function DoParseSetLiteral(): TMyrSetLiteralExprNode;
    function DoParseIntrinsic(const AKind: TMyrIntrinsicKind): TMyrIntrinsicExprNode;
    function IsIntrinsicToken(const AKind: TMyrTokenKind): Boolean;
    function TokenToIntrinsicKind(const AKind: TMyrTokenKind): TMyrIntrinsicKind;

  protected
    function Current(): TMyrToken;
    function Consume(): TMyrToken;
    function DoParseModuleKind(): TMyrModuleKind; virtual;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    function ParseModule(const AFilename: string; const AMasterAST: TMyrMasterAST): TMyrModuleNode;
    function ParseModuleFromString(const ASource: string; const AFilename: string;
      const AMasterAST: TMyrMasterAST): TMyrModuleNode;
    procedure SetErrors(const AErrors: TErrors); override;
    procedure SetStatusCallback(const ACallback: TStatusCallback; const AUserData: Pointer = nil); override;

    // Conditional compilation defines
    procedure SetDefine(const AName: string; const AValue: string);
    procedure Undefine(const AName: string);
    function IsDefined(const AName: string): Boolean;

    property Lexer: TMyrLexer read FLexer;
    property MasterAST: TMyrMasterAST read FMasterAST;
  end;

{ Semantics - Interface }

const
  // Error codes for semantic analysis
  MYR_ERR_SEM_001 = 'SEM001';  // Undeclared identifier
  MYR_ERR_SEM_002 = 'SEM002';  // Duplicate declaration
  MYR_ERR_SEM_003 = 'SEM003';  // Type mismatch
  MYR_ERR_SEM_004 = 'SEM004';  // Wrong argument count
  MYR_ERR_SEM_005 = 'SEM005';  // Break/continue outside loop
  MYR_ERR_SEM_006 = 'SEM006';  // Return outside routine
  MYR_ERR_SEM_007 = 'SEM007';  // Missing return in function
  MYR_ERR_SEM_008 = 'SEM008';  // Visibility violation
  MYR_ERR_SEM_009 = 'SEM009';  // Unqualified import access
  MYR_ERR_SEM_010 = 'SEM010';  // Forward not resolved
  MYR_ERR_SEM_011 = 'SEM011';  // Forward signature mismatch
  MYR_ERR_SEM_012 = 'SEM012';  // Forward type used in non-pointer context
  MYR_ERR_SEM_013 = 'SEM013';  // Invalid operation on type
  MYR_ERR_SEM_014 = 'SEM014';  // Const expression required
  MYR_ERR_SEM_015 = 'SEM015';  // Invalid intrinsic argument
  MYR_ERR_SEM_016 = 'SEM016';  // Char literal length
  MYR_ERR_SEM_017 = 'SEM017';  // Invalid array bounds
  MYR_ERR_SEM_018 = 'SEM018';  // Duplicate field name
  MYR_ERR_SEM_019 = 'SEM019';  // Duplicate choices value
  MYR_ERR_SEM_020 = 'SEM020';  // External declaration error
  MYR_ERR_SEM_021 = 'SEM021';  // Invalid module kind
  MYR_ERR_SEM_022 = 'SEM022';  // Module body violation (missing or forbidden begin)
  MYR_ERR_SEM_023 = 'SEM023';  // Invalid directive value

type
  { TMyrScopeKind }
  TMyrScopeKind = (
    skModule,
    skRoutine,
    skBlock,
    skTest
  );

  { TMyrScope }
  TMyrScope = class(TBaseObject)
  protected
    FScopeKind: TMyrScopeKind;
    FParent: TMyrScope;
    FSymbols: TDictionary<string, TMyrASTNode>;
    FOwnedGroups: TObjectList<TMyrOverloadGroupNode>;  // owns overload groups created by Declare
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Declare(const AName: string; const ANode: TMyrASTNode;
      const ALocation: TSourceRange);
    function Lookup(const AName: string): TMyrASTNode;
    function LookupLocal(const AName: string): TMyrASTNode;
    property ScopeKind: TMyrScopeKind read FScopeKind write FScopeKind;
    property Parent: TMyrScope read FParent write FParent;
  end;

  { TMyrSemantics }
  TMyrSemantics = class(TBaseObject)
  protected
    FMasterAST: TMyrMasterAST;
    FCurrentScope: TMyrScope;
    FCurrentModule: TMyrModuleNode;
    FModuleScopes: TObjectDictionary<string, TMyrScope>;
    FPrimitiveTypes: TObjectDictionary<TMyrTokenKind, TMyrTypeDeclNode>;
    FPointerToChar: TMyrPointerTypeNode;
    FPointerToWChar: TMyrPointerTypeNode;
    FLoopDepth: Integer;
    FCurrentRoutine: TMyrRoutineDeclNode;

    // Primitive type initialization
    procedure InitPrimitiveTypes();
    function GetPrimitiveType(const AKind: TMyrTokenKind): TMyrTypeDeclNode;

    // Scope management
    function PushScope(const AKind: TMyrScopeKind): TMyrScope;
    procedure PopScope();

    // Module processing
    procedure DoAnalyzeModule(const AModule: TMyrModuleNode); virtual;

    // Declaration analysis
    procedure DoAnalyzeDeclaration(const ANode: TMyrASTNode);
    procedure DoAnalyzeConstDecl(const ANode: TMyrConstDeclNode);
    procedure DoAnalyzeTypeDecl(const ANode: TMyrTypeDeclNode);
    procedure DoAnalyzeVarDecl(const ANode: TMyrVarDeclNode);
    procedure DoAnalyzeRoutineDecl(const ANode: TMyrRoutineDeclNode);
    procedure DoAnalyzeForwardTypeDecl(const ANode: TMyrForwardTypeDeclNode);
    procedure DoAnalyzeForwardRoutineDecl(const ANode: TMyrForwardRoutineDeclNode);

    // Type definition analysis
    procedure DoAnalyzeTypeDef(const ANode: TMyrASTNode);
    procedure DoAnalyzeRecordType(const ANode: TMyrRecordTypeNode);
    procedure DoAnalyzeOverlayType(const ANode: TMyrOverlayTypeNode);
    procedure DoAnalyzeArrayType(const ANode: TMyrArrayTypeNode);
    procedure DoAnalyzePointerType(const ANode: TMyrPointerTypeNode);
    procedure DoAnalyzeSetType(const ANode: TMyrSetTypeNode);
    procedure DoAnalyzeChoicesType(const ANode: TMyrChoicesTypeNode);
    procedure DoAnalyzeRoutineType(const ANode: TMyrRoutineTypeNode);
    procedure DoAnalyzeAnonOverlay(const ANode: TMyrAnonOverlayNode);
    procedure DoAnalyzeAnonRecord(const ANode: TMyrAnonRecordNode);

    // External clause helpers
    function DoResolveExternalString(const ARawText: string;
      const ALocation: TSourceRange): string;

    // Statement analysis
    procedure DoAnalyzeStatement(const ANode: TMyrASTNode);
    procedure DoAnalyzeStatementSeq(const AList: TObjectList<TMyrASTNode>);
    procedure DoAnalyzeAssign(const ANode: TMyrAssignNode);
    procedure DoAnalyzeCallStmt(const ANode: TMyrCallStmtNode);
    procedure DoAnalyzeIf(const ANode: TMyrIfNode);
    procedure DoAnalyzeWhile(const ANode: TMyrWhileNode);
    procedure DoAnalyzeFor(const ANode: TMyrForNode);
    procedure DoAnalyzeRepeat(const ANode: TMyrRepeatNode);
    procedure DoAnalyzeMatch(const ANode: TMyrMatchNode);
    procedure DoAnalyzeReturn(const ANode: TMyrReturnNode);
    procedure DoAnalyzeGuard(const ANode: TMyrGuardNode);
    procedure DoAnalyzeThrow(const ANode: TMyrThrowNode);
    procedure DoAnalyzePrint(const ANode: TMyrPrintNode);
    procedure DoAnalyzeAssert(const ANode: TMyrAssertStmtNode);
    procedure DoAnalyzeBreak(const ANode: TMyrBreakNode);
    procedure DoAnalyzeContinue(const ANode: TMyrContinueNode);
    procedure DoAnalyzeCppBlock(const ANode: TMyrCppBlockNode);
    procedure DoAnalyzeNew(const ANode: TMyrNewNode);
    procedure DoAnalyzeDispose(const ANode: TMyrDisposeNode);
    procedure DoAnalyzeGetMem(const ANode: TMyrGetMemNode);
    procedure DoAnalyzeFreeMem(const ANode: TMyrFreeMemNode);
    procedure DoAnalyzeResizeMem(const ANode: TMyrResizeMemNode);
    procedure DoAnalyzeSetLength(const ANode: TMyrSetLengthNode);

    // Expression analysis
    procedure DoAnalyzeExpr(const ANode: TMyrExprNode);
    procedure DoAnalyzeBinaryExpr(const ANode: TMyrBinaryExprNode);
    procedure DoAnalyzeUnaryExpr(const ANode: TMyrUnaryExprNode);
    procedure DoAnalyzeIdentifier(const ANode: TMyrIdentifierNode);
    procedure DoAnalyzeDotAccess(const ANode: TMyrDotAccessNode);
    procedure DoAnalyzeIndexAccess(const ANode: TMyrIndexAccessNode);
    procedure DoAnalyzeDeref(const ANode: TMyrDerefNode);
    procedure DoAnalyzeCallExpr(const ANode: TMyrCallExprNode);
    procedure DoCoerceCallArgs(const ANode: TMyrCallExprNode);
    procedure DoAnalyzeTypeCast(const ANode: TMyrTypeCastExprNode);
    procedure DoAnalyzeIntrinsic(const ANode: TMyrIntrinsicExprNode);
    procedure DoAnalyzeSetLiteral(const ANode: TMyrSetLiteralExprNode);
    procedure DoAnalyzeRecordLiteral(const ANode: TMyrRecordLiteralNode);
    procedure DoAnalyzeTypeRef(const ANode: TMyrTypeRefNode);

    // Literal type assignment
    procedure DoResolveLiteralType(const ANode: TMyrExprNode);

    // Type helpers
    procedure ResolveTypeExpr(const ANode: TMyrASTNode);
    function GetResolvedTypeDecl(const ANode: TMyrASTNode): TMyrASTNode;
    function IsAssignableFrom(const ATarget: TMyrASTNode; const ASource: TMyrASTNode): Boolean;
    function PromoteTypes(const ALeft: TMyrASTNode; const ARight: TMyrASTNode): TMyrASTNode;
    function IsIntegerType(const AType: TMyrASTNode): Boolean;
    function IsFloatType(const AType: TMyrASTNode): Boolean;
    function IsNumericType(const AType: TMyrASTNode): Boolean;
    function IsBooleanType(const AType: TMyrASTNode): Boolean;
    function IsStringType(const AType: TMyrASTNode): Boolean;
    function IsPointerType(const AType: TMyrASTNode): Boolean;

    // Overload resolution helper
    function DoOverloadTypesMatch(const ARoutine: TMyrRoutineDeclNode;
      const ACall: TMyrCallExprNode): Boolean;

    // Single authority for the type a resolved declaration exposes.
    // Shared by identifier resolution and module-qualified dot access.
    function DoResolvedTypeOfDecl(const ADecl: TMyrASTNode): TMyrASTNode;

    // Forward declaration validation
    procedure DoValidateForwards();

    // Return path validation
    function DoCheckReturnPaths(const AList: TObjectList<TMyrASTNode>): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Analyze(const AMasterAST: TMyrMasterAST); virtual;
  end;
implementation

{ TMyrToken }
procedure TMyrToken.Clear();
begin
  Kind := tkUnknown;
  TokenText := '';
  RawText := '';
  LeadingTrivia := '';
  Location.Clear();
  Category := tcSpecial;
  LiteralValue := TValue.Empty;
end;


{ TMyrissaLexer }
constructor TMyrLexer.Create();
begin
  inherited;

  FTokens := TList<TMyrToken>.Create();
  FKeywords := TDictionary<string, TMyrTokenKind>.Create();
  FCategories := TDictionary<TMyrTokenKind, TMyrTokenCategory>.Create();
  FCppTypes := TDictionary<TMyrTokenKind, string>.Create();

  FTokenIndex := 0;
  FPos := 1;
  FLine := 1;
  FCol := 1;

  RegisterKeywords();
  RegisterPrimitives();
  RegisterCategories();
end;

destructor TMyrLexer.Destroy();
begin
  FCppTypes.Free();
  FCategories.Free();
  FKeywords.Free();
  FTokens.Free();

  inherited;
end;

procedure TMyrLexer.AddKeyword(const AText: string; const AKind: TMyrTokenKind;
  const ACategory: TMyrTokenCategory);
begin
  FKeywords.AddOrSetValue(AText.ToLower(), AKind);
  FCategories.AddOrSetValue(AKind, ACategory);
end;

procedure TMyrLexer.AddKeyword(const AText: string; const AKind: TMyrTokenKind;
  const ACategory: TMyrTokenCategory; const ACppType: string);
begin
  AddKeyword(AText, AKind, ACategory);
  FCppTypes.AddOrSetValue(AKind, ACppType);
end;

function TMyrLexer.IsKeyword(const AName: string): Boolean;
begin
  Result := FKeywords.ContainsKey(AName.ToLower());
end;

procedure TMyrLexer.RegisterKeywords();
begin
  // BNF Section 2 - Reserved Words (except pointer, registered in primitives)
  AddKeyword('address',      tkAddress,      tcKeyword);
  AddKeyword('align',        tkAlign,        tcKeyword);
  AddKeyword('and',          tkAnd,          tcKeyword);
  AddKeyword('array',        tkArray,        tcKeyword);
  AddKeyword('assert',       tkAssert,       tcKeyword);
  AddKeyword('asserteq',     tkAssertEq,     tcKeyword);
  AddKeyword('asserteqf',    tkAssertEqF,    tcKeyword);
  AddKeyword('assertfalse',  tkAssertFalse,  tcKeyword);
  AddKeyword('assertfail',   tkAssertFail,   tcKeyword);
  AddKeyword('assertnil',    tkAssertNil,    tcKeyword);
  AddKeyword('assertnotnil', tkAssertNotNil, tcKeyword);
  AddKeyword('asserttrue',   tkAssertTrue,   tcKeyword);
  AddKeyword('begin',        tkBegin,        tcKeyword);
  AddKeyword('break',        tkBreak,        tcKeyword);
  AddKeyword('choices',      tkChoices,      tcKeyword);
  AddKeyword('clink',        tkCLink,        tcKeyword);
  AddKeyword('const',        tkConst,        tcKeyword);
  AddKeyword('continue',     tkContinue,     tcKeyword);
  AddKeyword('cpp',          tkCpp,          tcKeyword);
  AddKeyword('cppend',       tkCppEnd,       tcKeyword);
  AddKeyword('cpplink',      tkCppLink,      tcKeyword);
  AddKeyword('cppstart',     tkCppStart,     tcKeyword);
  AddKeyword('new',       tkNew,       tcKeyword);
  AddKeyword('cstr',         tkCStr,         tcKeyword);
  AddKeyword('dispose',      tkDispose,      tcKeyword);
  AddKeyword('div',          tkDiv,          tcKeyword);
  AddKeyword('do',           tkDo,           tcKeyword);
  AddKeyword('downto',       tkDownTo,       tcKeyword);
  AddKeyword('else',         tkElse,         tcKeyword);
  AddKeyword('end',          tkEnd,          tcKeyword);
  AddKeyword('except',       tkExcept,       tcKeyword);
  AddKeyword('exccode',      tkExcCode,      tcKeyword);
  AddKeyword('excmsg',       tkExcMsg,       tcKeyword);
  AddKeyword('external',     tkExternal,     tcKeyword);

  AddKeyword('false',        tkFalse,        tcKeyword);
  AddKeyword('finalize',     tkFinalize,     tcKeyword);
  AddKeyword('finally',      tkFinally,      tcKeyword);
  AddKeyword('for',          tkFor,          tcKeyword);
  AddKeyword('forward',      tkForward,      tcKeyword);
  AddKeyword('freemem',      tkFreeMem,      tcKeyword);
  AddKeyword('getmem',       tkGetMem,       tcKeyword);
  AddKeyword('guard',        tkGuard,        tcKeyword);
  AddKeyword('if',           tkIf,           tcKeyword);
  AddKeyword('import',       tkImport,       tcKeyword);
  AddKeyword('in',           tkIn,           tcKeyword);
  AddKeyword('initialize',   tkInitialize,   tcKeyword);
  AddKeyword('is',           tkIs,           tcKeyword);
  AddKeyword('len',          tkLen,          tcKeyword);
  AddKeyword('match',        tkMatch,        tcKeyword);
  AddKeyword('mod',          tkMod,          tcKeyword);
  AddKeyword('module',       tkModule,       tcKeyword);
  AddKeyword('nil',          tkNil,          tcKeyword);
  AddKeyword('not',          tkNot,          tcKeyword);
  AddKeyword('of',           tkOf,           tcKeyword);
  AddKeyword('or',           tkOr,           tcKeyword);
  AddKeyword('overlay',      tkOverlay,      tcKeyword);
  AddKeyword('packed',       tkPacked,       tcKeyword);
  AddKeyword('paramcount',   tkParamCount,   tcKeyword);
  AddKeyword('paramstr',     tkParamStr,     tcKeyword);
  AddKeyword('print',        tkPrint,        tcKeyword);
  AddKeyword('println',      tkPrintLn,      tcKeyword);
  AddKeyword('public',       tkPublic,       tcKeyword);
  AddKeyword('record',       tkRecord,       tcKeyword);
  AddKeyword('repeat',       tkRepeat,       tcKeyword);
  AddKeyword('resizemem',    tkResizeMem,    tcKeyword);
  AddKeyword('return',       tkReturn,       tcKeyword);
  AddKeyword('routine',      tkRoutine,      tcKeyword);
  AddKeyword('set',          tkSet,          tcKeyword);
  AddKeyword('setlength',    tkSetLength,    tcKeyword);
  AddKeyword('shl',          tkShl,          tcKeyword);
  AddKeyword('shr',          tkShr,          tcKeyword);
  AddKeyword('size',         tkSize,         tcKeyword);
  AddKeyword('test',         tkTest,         tcKeyword);
  AddKeyword('then',         tkThen,         tcKeyword);
  AddKeyword('throw',        tkThrow,        tcKeyword);
  AddKeyword('throwcode',    tkThrowCode,    tcKeyword);
  AddKeyword('to',           tkTo,           tcKeyword);
  AddKeyword('true',         tkTrue,         tcKeyword);
  AddKeyword('type',         tkType,         tcKeyword);
  AddKeyword('until',        tkUntil,        tcKeyword);
  AddKeyword('utf8',         tkUtf8,         tcKeyword);
  AddKeyword('var',          tkVar,          tcKeyword);
  AddKeyword('varargs',      tkVarArgs,      tcKeyword);
  AddKeyword('while',        tkWhile,        tcKeyword);
  AddKeyword('wstr',         tkWStr,         tcKeyword);
  AddKeyword('xor',          tkXor,          tcKeyword);
end;

procedure TMyrLexer.RegisterPrimitives();
begin
  // BNF Section 3 - Built-in Types with C++23 mappings
  AddKeyword('int8',     tkInt8,     tcPrimitive, 'int8_t');
  AddKeyword('int16',    tkInt16,    tcPrimitive, 'int16_t');
  AddKeyword('int32',    tkInt32,    tcPrimitive, 'int32_t');
  AddKeyword('int64',    tkInt64,    tcPrimitive, 'int64_t');
  AddKeyword('uint8',    tkUInt8,    tcPrimitive, 'uint8_t');
  AddKeyword('uint16',   tkUInt16,   tcPrimitive, 'uint16_t');
  AddKeyword('uint32',   tkUInt32,   tcPrimitive, 'uint32_t');
  AddKeyword('uint64',   tkUInt64,   tcPrimitive, 'uint64_t');
  AddKeyword('float32',  tkFloat32,  tcPrimitive, 'float');
  AddKeyword('float64',  tkFloat64,  tcPrimitive, 'double');
  AddKeyword('boolean',  tkBoolean,  tcPrimitive, 'bool');
  AddKeyword('char',     tkChar,     tcPrimitive, 'char');
  AddKeyword('wchar',    tkWChar,    tcPrimitive, 'char16_t');
  AddKeyword('string',   tkString,   tcPrimitive, 'std::string');
  AddKeyword('wstring',  tkWString,  tcPrimitive, 'std::wstring');
  AddKeyword('pointer',  tkPointer,  tcPrimitive, 'void*');
end;

procedure TMyrLexer.RegisterCategories();
begin
  // Register categories for non-keyword token kinds (operators, delimiters, etc.)
  // Keywords and primitives are already registered via AddKeyword.

  // Operators
  FCategories.AddOrSetValue(tkPlus,         tcOperator);
  FCategories.AddOrSetValue(tkMinus,        tcOperator);
  FCategories.AddOrSetValue(tkStar,         tcOperator);
  FCategories.AddOrSetValue(tkSlash,        tcOperator);
  FCategories.AddOrSetValue(tkEqual,        tcOperator);
  FCategories.AddOrSetValue(tkNotEqual,     tcOperator);
  FCategories.AddOrSetValue(tkLess,         tcOperator);
  FCategories.AddOrSetValue(tkGreater,      tcOperator);
  FCategories.AddOrSetValue(tkLessEqual,    tcOperator);
  FCategories.AddOrSetValue(tkGreaterEqual, tcOperator);
  FCategories.AddOrSetValue(tkAssign,       tcOperator);
  FCategories.AddOrSetValue(tkPlusAssign,   tcOperator);
  FCategories.AddOrSetValue(tkMinusAssign,  tcOperator);
  FCategories.AddOrSetValue(tkStarAssign,   tcOperator);
  FCategories.AddOrSetValue(tkSlashAssign,  tcOperator);
  FCategories.AddOrSetValue(tkCaret,        tcOperator);
  FCategories.AddOrSetValue(tkPipe,         tcOperator);
  FCategories.AddOrSetValue(tkAmpersand,    tcOperator);

  // Delimiters
  FCategories.AddOrSetValue(tkColon,        tcDelimiter);
  FCategories.AddOrSetValue(tkSemicolon,    tcDelimiter);
  FCategories.AddOrSetValue(tkComma,        tcDelimiter);
  FCategories.AddOrSetValue(tkDot,          tcDelimiter);
  FCategories.AddOrSetValue(tkDotDot,       tcDelimiter);
  FCategories.AddOrSetValue(tkEllipsis,     tcDelimiter);
  FCategories.AddOrSetValue(tkLParen,       tcDelimiter);
  FCategories.AddOrSetValue(tkRParen,       tcDelimiter);
  FCategories.AddOrSetValue(tkLBracket,     tcDelimiter);
  FCategories.AddOrSetValue(tkRBracket,     tcDelimiter);

  // Literals
  FCategories.AddOrSetValue(tkIntLiteral,     tcLiteral);
  FCategories.AddOrSetValue(tkFloatLiteral,   tcLiteral);
  FCategories.AddOrSetValue(tkStringLiteral,  tcLiteral);
  FCategories.AddOrSetValue(tkWStringLiteral, tcLiteral);

  // Special
  FCategories.AddOrSetValue(tkIdentifier, tcIdentifier);
  FCategories.AddOrSetValue(tkDirective,  tcDirective);
  FCategories.AddOrSetValue(tkEOF,        tcSpecial);
  FCategories.AddOrSetValue(tkUnknown,    tcSpecial);
end;

function TMyrLexer.CurrentChar(): Char;
begin
  if FPos <= Length(FSource) then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function TMyrLexer.PeekChar(): Char;
begin
  Result := PeekCharAt(1);
end;

function TMyrLexer.PeekCharAt(const AOffset: Int64): Char;
var
  LIdx: UInt64;
begin
  if AOffset >= 0 then
    LIdx := FPos + UInt64(AOffset)
  else
  begin
    if UInt64(-AOffset) > FPos then
    begin
      Result := #0;
      Exit;
    end;
    LIdx := FPos - UInt64(-AOffset);
  end;
  if (LIdx >= 1) and (LIdx <= UInt64(Length(FSource))) then
    Result := FSource[LIdx]
  else
    Result := #0;
end;

procedure TMyrLexer.Advance();
var
  LCh: Char;
begin
  if FPos > Length(FSource) then
    Exit;
  LCh := FSource[FPos];
  Inc(FPos);
  if LCh = #10 then
  begin
    Inc(FLine);
    FCol := 1;
  end
  else if LCh <> #13 then
    Inc(FCol);
end;

function TMyrLexer.IsAtSourceEnd(): Boolean;
begin
  Result := FPos > Length(FSource);
end;

function TMyrLexer.MakeLocation(const AStartLine: UInt64;
  const AStartCol: UInt64): TSourceRange;
begin
  Result.Clear();
  Result.Filename := FFilename;
  Result.StartLine := AStartLine;
  Result.StartColumn := AStartCol;
  Result.EndLine := FLine;
  Result.EndColumn := FCol - 1;
end;

function TMyrLexer.DoCollectTrivia(): string;
begin
  Result := '';
  while not IsAtSourceEnd() do
  begin
    if CharInSet(CurrentChar(), [' ', #9, #13, #10]) then
    begin
      Result := Result + CurrentChar();
      Advance();
    end
    else if (CurrentChar() = '/') and (PeekChar() = '/') then
      DoScanLineComment(Result)
    else if (CurrentChar() = '/') and (PeekChar() = '*') then
      DoScanBlockComment(Result)
    else
      Break;
  end;
end;

procedure TMyrLexer.DoScanLineComment(var ATrivia: string);
begin
  // Consume // and everything until end of line
  while not IsAtSourceEnd() and (CurrentChar() <> #10) do
  begin
    ATrivia := ATrivia + CurrentChar();
    Advance();
  end;
  // Consume the newline as part of the comment trivia
  if not IsAtSourceEnd() then
  begin
    ATrivia := ATrivia + CurrentChar();
    Advance();
  end;
end;

procedure TMyrLexer.DoScanBlockComment(var ATrivia: string);
var
  LDepth: Integer;
  LStartLine: UInt64;
  LStartCol: UInt64;
begin
  LStartLine := FLine;
  LStartCol := FCol;
  LDepth := 1;

  // Consume /*
  ATrivia := ATrivia + CurrentChar();
  Advance();
  ATrivia := ATrivia + CurrentChar();
  Advance();

  while not IsAtSourceEnd() and (LDepth > 0) do
  begin
    if (CurrentChar() = '/') and (PeekChar() = '*') then
    begin
      Inc(LDepth);
      ATrivia := ATrivia + CurrentChar();
      Advance();
      ATrivia := ATrivia + CurrentChar();
      Advance();
    end
    else if (CurrentChar() = '*') and (PeekChar() = '/') then
    begin
      Dec(LDepth);
      ATrivia := ATrivia + CurrentChar();
      Advance();
      ATrivia := ATrivia + CurrentChar();
      Advance();
    end
    else
    begin
      ATrivia := ATrivia + CurrentChar();
      Advance();
    end;
  end;

  if LDepth > 0 then
    FErrors.Add(FFilename, LStartLine, LStartCol, esError, MYR_ERR_LEX_002,
      RSLexUnterminatedComment);
end;

function TMyrLexer.DoProcessEscapeSeq(): Char;
var
  LHexStr: string;
  LHexVal: Integer;
begin
  // Current position is on the character after '\'
  Result := #0;

  if IsAtSourceEnd() then
  begin
    FErrors.Add(FFilename, FLine, FCol, esError, MYR_ERR_LEX_005,
      RSLexInvalidEscape, ['EOF']);
    Exit;
  end;

  if CurrentChar() = 'n' then
  begin
    Result := #10;
    Advance();
  end
  else if CurrentChar() = 't' then
  begin
    Result := #9;
    Advance();
  end
  else if CurrentChar() = 'r' then
  begin
    Result := #13;
    Advance();
  end
  else if CurrentChar() = '0' then
  begin
    Result := #0;
    Advance();
  end
  else if CurrentChar() = '\' then
  begin
    Result := '\';
    Advance();
  end
  else if CurrentChar() = '''' then
  begin
    Result := '''';
    Advance();
  end
  else if CurrentChar() = '"' then
  begin
    Result := '"';
    Advance();
  end
  else if CurrentChar() = 'x' then
  begin
    // \xHH - two hex digits required
    Advance(); // skip 'x'
    if IsAtSourceEnd() or not CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      FErrors.Add(FFilename, FLine, FCol, esError, MYR_ERR_LEX_005,
        RSLexInvalidEscape, ['x']);
      Exit;
    end;
    LHexStr := CurrentChar();
    Advance();
    if IsAtSourceEnd() or not CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      FErrors.Add(FFilename, FLine, FCol, esError, MYR_ERR_LEX_005,
        RSLexInvalidEscape, ['x' + LHexStr]);
      Exit;
    end;
    LHexStr := LHexStr + CurrentChar();
    Advance();
    if TryStrToInt('$' + LHexStr, LHexVal) then
      Result := Char(LHexVal)
    else
      FErrors.Add(FFilename, FLine, FCol, esError, MYR_ERR_LEX_005,
        RSLexInvalidEscape, ['x' + LHexStr]);
  end
  else
  begin
    FErrors.Add(FFilename, FLine, FCol, esError, MYR_ERR_LEX_005,
      RSLexInvalidEscape, [CurrentChar()]);
    Advance();
  end;
end;

function TMyrLexer.DoScanIdentifier(): TMyrToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LText: string;
  LLower: string;
  LKind: TMyrTokenKind;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  while not IsAtSourceEnd() and
    CharInSet(CurrentChar(), ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Advance();

  LText := FSource.Substring(LStart - 1, FPos - LStart);
  LLower := LText.ToLower();

  if FKeywords.TryGetValue(LLower, LKind) then
  begin
    Result.Kind := LKind;
    Result.TokenText := LLower;
    Result.Category := FCategories[LKind];
  end
  else
  begin
    Result.Kind := tkIdentifier;
    Result.TokenText := LText;
    Result.Category := tcIdentifier;
  end;

  Result.RawText := LText;
  Result.Location := MakeLocation(LStartLine, LStartCol);
end;

function TMyrLexer.DoScanNumber(): TMyrToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LText: string;
  LParseText: string;
  LFloatVal: Double;
  LUIntVal: UInt64;
  LIsFloat: Boolean;
  LIsHex: Boolean;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;
  LIsFloat := False;
  LIsHex := False;

  // Check for hex: 0x or 0X
  if (CurrentChar() = '0') and CharInSet(PeekChar(), ['x', 'X']) then
  begin
    LIsHex := True;
    Advance(); // 0
    Advance(); // x
    if IsAtSourceEnd() or
      not CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, MYR_ERR_LEX_004,
        RSLexInvalidHexLiteral);
      LText := FSource.Substring(LStart - 1, FPos - LStart);
      Result.Kind := tkUnknown;
      Result.TokenText := LText;
      Result.RawText := LText;
      Result.Location := MakeLocation(LStartLine, LStartCol);
      Result.Category := tcSpecial;
      Exit;
    end;
    while not IsAtSourceEnd() and
      CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) do
      Advance();
  end
  else
  begin
    // Decimal digits
    while not IsAtSourceEnd() and CharInSet(CurrentChar(), ['0'..'9']) do
      Advance();

    // Check for decimal point (not '..' range operator)
    if not IsAtSourceEnd() and (CurrentChar() = '.') and (PeekChar() <> '.') then
    begin
      LIsFloat := True;
      Advance();
      while not IsAtSourceEnd() and CharInSet(CurrentChar(), ['0'..'9']) do
        Advance();
    end;

    // Check for exponent
    if not IsAtSourceEnd() and CharInSet(CurrentChar(), ['e', 'E']) then
    begin
      LIsFloat := True;
      Advance();
      if not IsAtSourceEnd() and CharInSet(CurrentChar(), ['+', '-']) then
        Advance();
      while not IsAtSourceEnd() and CharInSet(CurrentChar(), ['0'..'9']) do
        Advance();
    end;

    // Check for f/F suffix (always makes it float)
    if not IsAtSourceEnd() and CharInSet(CurrentChar(), ['f', 'F']) then
    begin
      LIsFloat := True;
      Advance();
    end;
  end;

  LText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.RawText := LText;
  Result.Location := MakeLocation(LStartLine, LStartCol);

  if LIsFloat then
  begin
    Result.Kind := tkFloatLiteral;
    Result.Category := tcLiteral;
    Result.TokenText := LText;
    // Strip f/F suffix for parsing
    LParseText := LText;
    if LParseText.EndsWith('f', True) then
      LParseText := LParseText.Substring(0, LParseText.Length - 1);
    if TryStrToFloat(LParseText, LFloatVal, TFormatSettings.Invariant) then
      Result.LiteralValue := TValue.From<Double>(LFloatVal)
    else
    begin
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, MYR_ERR_LEX_006,
        RSLexInvalidNumber);
      Exit;
    end;
  end
  else
  begin
    Result.Kind := tkIntLiteral;
    Result.Category := tcLiteral;
    Result.TokenText := LText;
    if LIsHex then
      LParseText := '$' + LText.Substring(2)
    else
      LParseText := LText;
    if TryStrToUInt64(LParseText, LUIntVal) then
      Result.LiteralValue := TValue.From<UInt64>(LUIntVal)
    else
    begin
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, MYR_ERR_LEX_006,
        RSLexInvalidNumber);
      Exit;
    end;
  end;
end;

function TMyrLexer.DoScanStringLiteral(): TMyrToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LContent: string;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  Advance(); // consume opening "

  LContent := '';
  while not IsAtSourceEnd() and (CurrentChar() <> '"') and (CurrentChar() <> #10) do
  begin
    if CurrentChar() = '\' then
    begin
      Advance(); // skip backslash
      LContent := LContent + DoProcessEscapeSeq();
    end
    else
    begin
      LContent := LContent + CurrentChar();
      Advance();
    end;
  end;

  if IsAtSourceEnd() or (CurrentChar() = #10) then
  begin
    FErrors.Add(FFilename, LStartLine, LStartCol, esError, MYR_ERR_LEX_001,
      RSLexUnterminatedString);
    Result.Kind := tkUnknown;
    Result.Category := tcSpecial;
    Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
    Result.RawText := Result.TokenText;
    Result.Location := MakeLocation(LStartLine, LStartCol);
    Exit;
  end;

  Advance(); // consume closing "

  Result.Kind := tkStringLiteral;
  Result.Category := tcLiteral;
  Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.RawText := Result.TokenText;
  Result.Location := MakeLocation(LStartLine, LStartCol);
  Result.LiteralValue := TValue.From<string>(LContent);
end;

function TMyrLexer.DoScanWStringLiteral(): TMyrToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LContent: string;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  Advance(); // consume 'w'
  Advance(); // consume opening "

  LContent := '';
  while not IsAtSourceEnd() and (CurrentChar() <> '"') and (CurrentChar() <> #10) do
  begin
    if CurrentChar() = '\' then
    begin
      Advance();
      LContent := LContent + DoProcessEscapeSeq();
    end
    else
    begin
      LContent := LContent + CurrentChar();
      Advance();
    end;
  end;

  if IsAtSourceEnd() or (CurrentChar() = #10) then
  begin
    FErrors.Add(FFilename, LStartLine, LStartCol, esError, MYR_ERR_LEX_001,
      RSLexUnterminatedString);
    Result.Kind := tkUnknown;
    Result.Category := tcSpecial;
    Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
    Result.RawText := Result.TokenText;
    Result.Location := MakeLocation(LStartLine, LStartCol);
    Exit;
  end;

  Advance(); // consume closing "

  Result.Kind := tkWStringLiteral;
  Result.Category := tcLiteral;
  Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.RawText := Result.TokenText;
  Result.Location := MakeLocation(LStartLine, LStartCol);
  Result.LiteralValue := TValue.From<string>(LContent);
end;

function TMyrLexer.DoScanDirective(): TMyrToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LName: string;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  Advance(); // consume '@'

  // Scan the directive identifier
  LName := '';
  while not IsAtSourceEnd() and
    CharInSet(CurrentChar(), ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    LName := LName + CurrentChar();
    Advance();
  end;

  Result.Kind := tkDirective;
  Result.Category := tcDirective;
  Result.TokenText := LName.ToLower();
  Result.RawText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.Location := MakeLocation(LStartLine, LStartCol);
end;

function TMyrLexer.DoScanOperator(): TMyrToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LCh: Char;
  LNext: Char;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LCh := CurrentChar();
  LNext := PeekChar();

  // Multi-character operators first
  if (LCh = ':') and (LNext = '=') then
  begin
    Result.Kind := tkAssign;
    Result.TokenText := ':=';
    Advance(); Advance();
  end
  else if (LCh = '+') and (LNext = '=') then
  begin
    Result.Kind := tkPlusAssign;
    Result.TokenText := '+=';
    Advance(); Advance();
  end
  else if (LCh = '-') and (LNext = '=') then
  begin
    Result.Kind := tkMinusAssign;
    Result.TokenText := '-=';
    Advance(); Advance();
  end
  else if (LCh = '*') and (LNext = '=') then
  begin
    Result.Kind := tkStarAssign;
    Result.TokenText := '*=';
    Advance(); Advance();
  end
  else if (LCh = '/') and (LNext = '=') then
  begin
    Result.Kind := tkSlashAssign;
    Result.TokenText := '/=';
    Advance(); Advance();
  end
  else if (LCh = '<') and (LNext = '>') then
  begin
    Result.Kind := tkNotEqual;
    Result.TokenText := '<>';
    Advance(); Advance();
  end
  else if (LCh = '<') and (LNext = '=') then
  begin
    Result.Kind := tkLessEqual;
    Result.TokenText := '<=';
    Advance(); Advance();
  end
  else if (LCh = '>') and (LNext = '=') then
  begin
    Result.Kind := tkGreaterEqual;
    Result.TokenText := '>=';
    Advance(); Advance();
  end
  // ... (triple dot) must be checked before .. (double dot)
  else if (LCh = '.') and (LNext = '.') and (PeekCharAt(2) = '.') then
  begin
    Result.Kind := tkEllipsis;
    Result.TokenText := '...';
    Advance(); Advance(); Advance();
  end
  else if (LCh = '.') and (LNext = '.') then
  begin
    Result.Kind := tkDotDot;
    Result.TokenText := '..';
    Advance(); Advance();
  end

  // Single-character operators and delimiters
  else
  begin
    Advance();
    if LCh = '+' then
    begin
      Result.Kind := tkPlus;
      Result.TokenText := '+';
    end
    else if LCh = '-' then
    begin
      Result.Kind := tkMinus;
      Result.TokenText := '-';
    end
    else if LCh = '*' then
    begin
      Result.Kind := tkStar;
      Result.TokenText := '*';
    end
    else if LCh = '/' then
    begin
      Result.Kind := tkSlash;
      Result.TokenText := '/';
    end
    else if LCh = '=' then
    begin
      Result.Kind := tkEqual;
      Result.TokenText := '=';
    end
    else if LCh = '<' then
    begin
      Result.Kind := tkLess;
      Result.TokenText := '<';
    end
    else if LCh = '>' then
    begin
      Result.Kind := tkGreater;
      Result.TokenText := '>';
    end
    else if LCh = '^' then
    begin
      Result.Kind := tkCaret;
      Result.TokenText := '^';
    end
    else if LCh = '|' then
    begin
      Result.Kind := tkPipe;
      Result.TokenText := '|';
    end
    else if LCh = '&' then
    begin
      Result.Kind := tkAmpersand;
      Result.TokenText := '&';
    end
    else if LCh = ':' then
    begin
      Result.Kind := tkColon;
      Result.TokenText := ':';
    end
    else if LCh = ';' then
    begin
      Result.Kind := tkSemicolon;
      Result.TokenText := ';';
    end
    else if LCh = ',' then
    begin
      Result.Kind := tkComma;
      Result.TokenText := ',';
    end
    else if LCh = '.' then
    begin
      Result.Kind := tkDot;
      Result.TokenText := '.';
    end
    else if LCh = '(' then
    begin
      Result.Kind := tkLParen;
      Result.TokenText := '(';
    end
    else if LCh = ')' then
    begin
      Result.Kind := tkRParen;
      Result.TokenText := ')';
    end
    else if LCh = '[' then
    begin
      Result.Kind := tkLBracket;
      Result.TokenText := '[';
    end
    else if LCh = ']' then
    begin
      Result.Kind := tkRBracket;
      Result.TokenText := ']';
    end
    else
    begin
      Result.Kind := tkUnknown;
      Result.TokenText := LCh;
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, MYR_ERR_LEX_003,
        RSLexInvalidCharacter, [LCh]);
    end;
  end;

  Result.RawText := Result.TokenText;
  Result.Category := FCategories[Result.Kind];
  Result.Location := MakeLocation(LStartLine, LStartCol);
end;

procedure TMyrLexer.DoScanRawBlock();
var
  LRawBuf: string;
  LRawStartLine: UInt64;
  LRawStartCol: UInt64;
  LEndWord: string;
  LEndLen: UInt64;
  LFoundEnd: Boolean;
  LI: UInt64;
  LAfterEnd: Char;
  LEndKwLine: UInt64;
  LEndKwCol: UInt64;
  LToken: TMyrToken;
begin
  LEndWord := 'cppend';
  LEndLen := Length(LEndWord);

  // Skip whitespace before raw content
  while not IsAtSourceEnd() and CharInSet(CurrentChar(), [' ', #9, #13, #10]) do
  begin
    if CurrentChar() = #10 then
    begin
      Inc(FLine);
      FCol := 1;
    end
    else
      Inc(FCol);
    Inc(FPos);
  end;

  LRawBuf := '';
  LRawStartLine := FLine;
  LRawStartCol := FCol;

  while not IsAtSourceEnd() do
  begin
    // Check if current position starts with the end keyword
    LFoundEnd := True;
    for LI := 0 to LEndLen - 1 do
    begin
      if (FPos + LI > Length(FSource)) or
         (FSource[FPos + LI] <> LEndWord[LI + 1]) then
      begin
        LFoundEnd := False;
        Break;
      end;
    end;

    // Verify end keyword is a standalone word
    if LFoundEnd then
    begin
      if (FPos + LEndLen) <= Length(FSource) then
        LAfterEnd := FSource[FPos + LEndLen]
      else
        LAfterEnd := ' ';

      if not CharInSet(LAfterEnd, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      begin
        // Emit the raw block token with trimmed text
        LToken.Clear();
        LToken.Kind := tkRawBlock;
        LToken.TokenText := LRawBuf.TrimRight();
        LToken.RawText := LRawBuf;
        LToken.LeadingTrivia := '';
        LToken.Location := MakeLocation(LRawStartLine, LRawStartCol);
        LToken.Category := tcLiteral;
        FTokens.Add(LToken);

        // Emit the cppend keyword token
        LEndKwLine := FLine;
        LEndKwCol := FCol;
        for LI := 1 to LEndLen do
          Advance();

        LToken.Clear();
        LToken.Kind := tkCppEnd;
        LToken.TokenText := LEndWord;
        LToken.RawText := LEndWord;
        LToken.LeadingTrivia := '';
        LToken.Location := MakeLocation(LEndKwLine, LEndKwCol);
        LToken.Category := tcKeyword;
        FTokens.Add(LToken);
        Exit;
      end;
    end;

    // Accumulate raw character
    LRawBuf := LRawBuf + CurrentChar();
    Advance();
  end;

  // Reached end of source without finding cppend
  FErrors.Add(FFilename, LRawStartLine, LRawStartCol, esError,
    MYR_ERR_LEX_003, 'Unterminated cppstart block, expected ''cppend''', []);
end;

function TMyrLexer.DoScanToken(const ATrivia: string): TMyrToken;
var
  LCh: Char;
begin
  LCh := CurrentChar();

  // Identifier or keyword (check for w"..." wstring first)
  if CharInSet(LCh, ['A'..'Z', 'a'..'z', '_']) then
  begin
    if (LCh = 'w') and (PeekChar() = '"') then
      Result := DoScanWStringLiteral()
    else
      Result := DoScanIdentifier();
  end
  // Numeric literal
  else if CharInSet(LCh, ['0'..'9']) then
    Result := DoScanNumber()
  // String literal
  else if LCh = '"' then
    Result := DoScanStringLiteral()
  // Directive
  else if LCh = '@' then
    Result := DoScanDirective()
  // Operator or delimiter
  else
    Result := DoScanOperator();

  Result.LeadingTrivia := ATrivia;
end;

function TMyrLexer.TokenizeFile(const AFilename: string): Boolean;
var
  LSource: string;
  LFilename: string;
begin
  Result := False;

  LFilename := TPath.ChangeExtension(TUtils.ResolvePath(AFilename), MYR_SRCFILE_EXT);

  if not TFile.Exists(LFilename) then
  begin
    FErrors.Add(esFatal, MYR_ERR_LEX_009, RSFatalFileNotFound, [LFilename]);
    Exit;
  end;

  try
    LSource := TFile.ReadAllText(LFilename);
  except
    on E: Exception do
    begin
      FErrors.Add(esFatal, MYR_ERR_LEX_010, RSFatalFileReadError, [LFilename, E.Message]);
      Exit;
    end;
  end;

  Result := TokenizeString(LSource, LFilename);
end;

function TMyrLexer.TokenizeString(const ASource: string;
  const AFilename: string): Boolean;
var
  LTrivia: string;
  LToken: TMyrToken;
begin
  // Reset state
  FSource := ASource;
  FFilename := AFilename;
  FPos := 1;
  FLine := 1;
  FCol := 1;
  FTokenIndex := 0;
  FTokens.Clear();

  while not IsAtSourceEnd() do
  begin
    LTrivia := DoCollectTrivia();
    if IsAtSourceEnd() then
    begin
      // Trailing trivia goes on the EOF token
      LToken.Clear();
      LToken.Kind := tkEOF;
      LToken.TokenText := '';
      LToken.RawText := '';
      LToken.LeadingTrivia := LTrivia;
      LToken.Location := MakeLocation(FLine, FCol);
      LToken.Category := tcSpecial;
      FTokens.Add(LToken);
      Result := not FErrors.HasErrors();
      Exit;
    end;
    LToken := DoScanToken(LTrivia);
    FTokens.Add(LToken);

    // Raw block capture: when cppstart is encountered, collect verbatim
    // text until cppend appears as a standalone word
    if LToken.Kind = tkCppStart then
      DoScanRawBlock();
  end;

  // Ensure EOF token always present
  LToken.Clear();
  LToken.Kind := tkEOF;
  LToken.TokenText := '';
  LToken.RawText := '';
  LToken.LeadingTrivia := '';
  LToken.Location := MakeLocation(FLine, FCol);
  LToken.Category := tcSpecial;
  FTokens.Add(LToken);

  Result := not FErrors.HasErrors();
end;

function TMyrLexer.CurrentToken(): TMyrToken;
begin
  if FTokenIndex < FTokens.Count then
    Result := FTokens[FTokenIndex]
  else
  begin
    Result.Clear();
    Result.Kind := tkEOF;
    Result.Category := tcSpecial;
  end;
end;

function TMyrLexer.NextToken(): TMyrToken;
begin
  if FTokenIndex < FTokens.Count - 1 then
    Inc(FTokenIndex);
  Result := CurrentToken();
end;

function TMyrLexer.PeekToken(): TMyrToken;
begin
  Result := PeekAt(1);
end;

function TMyrLexer.PeekAt(const AOffset: Int64): TMyrToken;
var
  LIdx: UInt64;
begin
  if AOffset >= 0 then
    LIdx := FTokenIndex + UInt64(AOffset)
  else
  begin
    if UInt64(-AOffset) > FTokenIndex then
    begin
      Result.Clear();
      Result.Kind := tkEOF;
      Result.Category := tcSpecial;
      Exit;
    end;
    LIdx := FTokenIndex - UInt64(-AOffset);
  end;
  if LIdx < UInt64(FTokens.Count) then
    Result := FTokens[LIdx]
  else
  begin
    Result.Clear();
    Result.Kind := tkEOF;
    Result.Category := tcSpecial;
  end;
end;

function TMyrLexer.Match(const AKind: TMyrTokenKind): Boolean;
begin
  Result := CurrentToken().Kind = AKind;
  if Result then
    NextToken();
end;

function TMyrLexer.Expect(const AKind: TMyrTokenKind): TMyrToken;
var
  LExpected: string;
  LPair: TPair<string, TMyrTokenKind>;
begin
  Result := CurrentToken();
  if Result.Kind <> AKind then
  begin
    // Build a readable description of the expected token
    LExpected := '';
    for LPair in FKeywords do
    begin
      if LPair.Value = AKind then
      begin
        LExpected := '''' + LPair.Key + '''';
        Break;
      end;
    end;
    if LExpected = '' then
      LExpected := 'token';
    FErrors.Add(Result.Location, esError, MYR_ERR_LEX_008,
      RSLexExpected, [LExpected, Result.RawText]);
  end
  else
    NextToken();
end;

function TMyrLexer.IsAtEnd(): Boolean;
begin
  Result := CurrentToken().Kind = tkEOF;
end;

function TMyrLexer.IsDataType(const AKind: TMyrTokenKind): Boolean;
var
  LCategory: TMyrTokenCategory;
begin
  Result := FCategories.TryGetValue(AKind, LCategory) and
    (LCategory = tcPrimitive);
end;

function TMyrLexer.IsOperator(const AKind: TMyrTokenKind): Boolean;
var
  LCategory: TMyrTokenCategory;
begin
  Result := FCategories.TryGetValue(AKind, LCategory) and
    (LCategory = tcOperator);
end;

function TMyrLexer.GetCppType(const AKind: TMyrTokenKind): string;
begin
  if not FCppTypes.TryGetValue(AKind, Result) then
    Result := '';
end;

function TMyrLexer.GetCategory(const AKind: TMyrTokenKind): TMyrTokenCategory;
begin
  if not FCategories.TryGetValue(AKind, Result) then
    Result := tcSpecial;
end;

{ TMyrLexer.GetRegisteredWords }
function TMyrLexer.GetRegisteredWords(
  const ACategory: TMyrTokenCategory): TArray<string>;
var
  LPair: TPair<string, TMyrTokenKind>;
  LCat: TMyrTokenCategory;
  LList: TList<string>;
begin
  LList := TList<string>.Create();
  try
    for LPair in FKeywords do
    begin
      if FCategories.TryGetValue(LPair.Value, LCat) and (LCat = ACategory) then
        LList.Add(LPair.Key);
    end;
    LList.Sort();
    Result := LList.ToArray();
  finally
    LList.Free();
  end;
end;

function TMyrLexer.TokenCount(): UInt64;
begin
  Result := FTokens.Count;
end;

{ TMyrLexer.GetTokens }
function TMyrLexer.GetTokens(): TList<TMyrToken>;
begin
  Result := FTokens;
end;

function TMyrLexer.ToSource(): string;
var
  LBuilder: TStringBuilder;
  LIdx: Int64;
begin
  LBuilder := TStringBuilder.Create();
  try
    for LIdx := 0 to FTokens.Count - 1 do
    begin
      LBuilder.Append(FTokens[LIdx].LeadingTrivia);
      LBuilder.Append(FTokens[LIdx].RawText);
    end;
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

{ AST - Implementation }

{ TMyrASTNode }
constructor TMyrASTNode.Create();
begin
  inherited;

  FLocation.Clear();
end;

destructor TMyrASTNode.Destroy();
begin
  inherited;
end;

{ TMyrASTNode.SetLocationEnd }
procedure TMyrASTNode.SetLocationEnd(const AEndLine: UInt64;
  const AEndColumn: UInt64);
begin
  FLocation.EndLine := AEndLine;
  FLocation.EndColumn := AEndColumn;
end;

{ TMyrModuleNode }
constructor TMyrModuleNode.Create();
begin
  inherited;

  FModuleKind := mkExe;
  FDirectives := TObjectList<TMyrDirectiveNode>.Create(True);
  FImports := TObjectList<TMyrImportNode>.Create(True);
  FDeclarations := TObjectList<TMyrASTNode>.Create(True);
  FInitBody := TObjectList<TMyrASTNode>.Create(True);
  FFinalBody := TObjectList<TMyrASTNode>.Create(True);
  FMainBody := TObjectList<TMyrASTNode>.Create(True);
  FTestBlocks := TObjectList<TMyrTestBlockNode>.Create(True);
end;

destructor TMyrModuleNode.Destroy();
begin
  FTestBlocks.Free();
  FMainBody.Free();
  FFinalBody.Free();
  FInitBody.Free();
  FDeclarations.Free();
  FImports.Free();
  FDirectives.Free();

  inherited;
end;

{ TMyrTestBlockNode }
constructor TMyrTestBlockNode.Create();
begin
  inherited;

  FLocals := TObjectList<TMyrVarDeclNode>.Create(True);
  FBody := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrTestBlockNode.Destroy();
begin
  FBody.Free();
  FLocals.Free();

  inherited;
end;

{ TMyrRoutineDeclNode }
constructor TMyrRoutineDeclNode.Create();
begin
  inherited;

  FLinkage := lkDefault;
  FParams := TObjectList<TMyrParamDeclNode>.Create(True);
  FLocalTypes := TObjectList<TMyrTypeDeclNode>.Create(True);
  FLocalConsts := TObjectList<TMyrConstDeclNode>.Create(True);
  FLocalVars := TObjectList<TMyrVarDeclNode>.Create(True);
  FBody := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrRoutineDeclNode.Destroy();
begin
  if FReturnType <> nil then
    FReturnType.Free();
  FBody.Free();
  FLocalVars.Free();
  FLocalConsts.Free();
  FLocalTypes.Free();
  FParams.Free();

  inherited;
end;

{ TMyrOverloadGroupNode }
constructor TMyrOverloadGroupNode.Create();
begin
  inherited;

  FOverloads := TList<TMyrRoutineDeclNode>.Create();
end;

destructor TMyrOverloadGroupNode.Destroy();
begin
  FOverloads.Free();

  inherited;
end;

{ TMyrForwardRoutineDeclNode }
constructor TMyrForwardRoutineDeclNode.Create();
begin
  inherited;

  FParams := TObjectList<TMyrParamDeclNode>.Create(True);
end;

destructor TMyrForwardRoutineDeclNode.Destroy();
begin
  if FReturnType <> nil then
    FReturnType.Free();
  FParams.Free();

  inherited;
end;

{ TMyrRecordTypeNode }
constructor TMyrRecordTypeNode.Create();
begin
  inherited;

  FFields := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrRecordTypeNode.Destroy();
begin
  if FBaseType <> nil then
    FBaseType.Free();
  FFields.Free();

  inherited;
end;

{ TMyrOverlayTypeNode }
constructor TMyrOverlayTypeNode.Create();
begin
  inherited;

  FFields := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrOverlayTypeNode.Destroy();
begin
  FFields.Free();

  inherited;
end;

{ TMyrAnonRecordNode }
constructor TMyrAnonRecordNode.Create();
begin
  inherited;

  FFields := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrAnonRecordNode.Destroy();
begin
  FFields.Free();

  inherited;
end;

{ TMyrAnonOverlayNode }
constructor TMyrAnonOverlayNode.Create();
begin
  inherited;

  FFields := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrAnonOverlayNode.Destroy();
begin
  FFields.Free();

  inherited;
end;

{ TMyrChoicesTypeNode }
constructor TMyrChoicesTypeNode.Create();
begin
  inherited;

  FMembers := TObjectList<TMyrChoicesValueNode>.Create(True);
end;

destructor TMyrChoicesTypeNode.Destroy();
begin
  FMembers.Free();

  inherited;
end;

{ TMyrRoutineTypeNode }
constructor TMyrRoutineTypeNode.Create();
begin
  inherited;

  FLinkage := lkDefault;
  FParams := TObjectList<TMyrParamDeclNode>.Create(True);
end;

destructor TMyrRoutineTypeNode.Destroy();
begin
  if FReturnType <> nil then
    FReturnType.Free();
  FParams.Free();

  inherited;
end;

{ TMyrIfNode }
constructor TMyrIfNode.Create();
begin
  inherited;

  FThenBody := TObjectList<TMyrASTNode>.Create(True);
  FElseBody := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrIfNode.Destroy();
begin
  FCondition.Free();
  FElseBody.Free();
  FThenBody.Free();

  inherited;
end;

{ TMyrWhileNode }
constructor TMyrWhileNode.Create();
begin
  inherited;

  FBody := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrWhileNode.Destroy();
begin
  FCondition.Free();
  FBody.Free();

  inherited;
end;

{ TMyrForNode }
constructor TMyrForNode.Create();
begin
  inherited;

  FBody := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrForNode.Destroy();
begin
  FStartExpr.Free();
  FEndExpr.Free();
  FBody.Free();

  inherited;
end;

{ TMyrRepeatNode }
constructor TMyrRepeatNode.Create();
begin
  inherited;

  FBody := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrRepeatNode.Destroy();
begin
  FCondition.Free();
  FBody.Free();

  inherited;
end;

{ TMyrMatchNode }
constructor TMyrMatchNode.Create();
begin
  inherited;

  FArms := TObjectList<TMyrMatchArmNode>.Create(True);
  FElseBody := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrMatchNode.Destroy();
begin
  FExpr.Free();
  FElseBody.Free();
  FArms.Free();

  inherited;
end;

{ TMyrMatchArmNode }
constructor TMyrMatchArmNode.Create();
begin
  inherited;

  FLabels := TObjectList<TMyrMatchLabelNode>.Create(True);
  FBody := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrMatchArmNode.Destroy();
begin
  FBody.Free();
  FLabels.Free();

  inherited;
end;

{ TMyrGuardNode }
constructor TMyrGuardNode.Create();
begin
  inherited;

  FGuardBody := TObjectList<TMyrASTNode>.Create(True);
  FExceptBody := TObjectList<TMyrASTNode>.Create(True);
  FFinallyBody := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrGuardNode.Destroy();
begin
  FFinallyBody.Free();
  FExceptBody.Free();
  FGuardBody.Free();

  inherited;
end;

{ TMyrPrintNode }
constructor TMyrPrintNode.Create();
begin
  inherited;

  FArgs := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrPrintNode.Destroy();
begin
  FArgs.Free();
  inherited;
end;

{ TMyrAssertStmtNode }
constructor TMyrAssertStmtNode.Create();
begin
  inherited;

  FArgs := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrAssertStmtNode.Destroy();
begin
  FArgs.Free();

  inherited;
end;

{ TMyrCallExprNode }
constructor TMyrCallExprNode.Create();
begin
  inherited;

  FArgs := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrCallExprNode.Destroy();
begin
  FCallee.Free();
  FArgs.Free();

  inherited;
end;

{ TMyrSetLiteralExprNode }
constructor TMyrSetLiteralExprNode.Create();
begin
  inherited;

  FElements := TObjectList<TMyrSetElementNode>.Create(True);
end;

destructor TMyrSetLiteralExprNode.Destroy();
begin
  FElements.Free();

  inherited;
end;

{ TMyrRecordLiteralNode }
constructor TMyrRecordLiteralNode.Create();
begin
  inherited;

  FFieldInits := TObjectList<TMyrFieldInitNode>.Create(True);
end;

destructor TMyrRecordLiteralNode.Destroy();
begin
  FFieldInits.Free();

  inherited;
end;

{ TMyrIntrinsicExprNode }
constructor TMyrIntrinsicExprNode.Create();
begin
  inherited;

  FArgs := TObjectList<TMyrASTNode>.Create(True);
end;

destructor TMyrIntrinsicExprNode.Destroy();
begin
  FArgs.Free();

  inherited;
end;

{ TMyrConstDeclNode }
destructor TMyrConstDeclNode.Destroy();
begin
  if FTypeExpr <> nil then
    FTypeExpr.Free();
  FValueExpr.Free();

  inherited;
end;

{ TMyrTypeDeclNode }
destructor TMyrTypeDeclNode.Destroy();
begin
  FTypeDef.Free();

  inherited;
end;

{ TMyrVarDeclNode }
destructor TMyrVarDeclNode.Destroy();
begin
  if FTypeExpr <> nil then
    FTypeExpr.Free();
  FInitExpr.Free();

  inherited;
end;

{ TMyrParamDeclNode }
destructor TMyrParamDeclNode.Destroy();
begin
  if FTypeExpr <> nil then
    FTypeExpr.Free();

  inherited;
end;

{ TMyrFieldDeclNode }
destructor TMyrFieldDeclNode.Destroy();
begin
  if FTypeExpr <> nil then
    FTypeExpr.Free();

  inherited;
end;

{ TMyrArrayTypeNode }
destructor TMyrArrayTypeNode.Destroy();
begin
  if FElementType <> nil then
    FElementType.Free();

  inherited;
end;

{ TMyrPointerTypeNode }
destructor TMyrPointerTypeNode.Destroy();
begin
  if FTargetType <> nil then
    FTargetType.Free();

  inherited;
end;

{ TMyrSetTypeNode }
destructor TMyrSetTypeNode.Destroy();
begin
  if FElementType <> nil then
    FElementType.Free();

  inherited;
end;

{ TMyrChoicesValueNode }
destructor TMyrChoicesValueNode.Destroy();
begin
  FValueExpr.Free();

  inherited;
end;

{ TMyrAssignNode }
destructor TMyrAssignNode.Destroy();
begin
  FTarget.Free();
  FValueExpr.Free();

  inherited;
end;

{ TMyrCallStmtNode }
destructor TMyrCallStmtNode.Destroy();
begin
  FCallExpr.Free();

  inherited;
end;

{ TMyrMatchLabelNode }
destructor TMyrMatchLabelNode.Destroy();
begin
  FLowExpr.Free();
  FHighExpr.Free();

  inherited;
end;

{ TMyrReturnNode }
destructor TMyrReturnNode.Destroy();
begin
  FValueExpr.Free();

  inherited;
end;

{ TMyrThrowNode }
destructor TMyrThrowNode.Destroy();
begin
  FMessageExpr.Free();

  inherited;
end;

{ TMyrThrowCodeNode }
destructor TMyrThrowCodeNode.Destroy();
begin
  FCodeExpr.Free();
  FMessageExpr.Free();

  inherited;
end;

{ TMyrCppExprNode }
destructor TMyrCppExprNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TMyrNewNode }
destructor TMyrNewNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TMyrDisposeNode }
destructor TMyrDisposeNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TMyrGetMemNode }
destructor TMyrGetMemNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TMyrFreeMemNode }
destructor TMyrFreeMemNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TMyrResizeMemNode }
destructor TMyrResizeMemNode.Destroy();
begin
  FPtrExpr.Free();
  FSizeExpr.Free();

  inherited;
end;

{ TMyrSetLengthNode }
destructor TMyrSetLengthNode.Destroy();
begin
  FTargetExpr.Free();
  FLengthExpr.Free();

  inherited;
end;

{ TMyrBinaryExprNode }
destructor TMyrBinaryExprNode.Destroy();
begin
  FLeft.Free();
  FRight.Free();

  inherited;
end;

{ TMyrUnaryExprNode }
destructor TMyrUnaryExprNode.Destroy();
begin
  FOperand.Free();

  inherited;
end;

{ TMyrDotAccessNode }
destructor TMyrDotAccessNode.Destroy();
begin
  FBaseExpr.Free();

  inherited;
end;

{ TMyrIndexAccessNode }
destructor TMyrIndexAccessNode.Destroy();
begin
  FBaseExpr.Free();
  FIndexExpr.Free();

  inherited;
end;

{ TMyrDerefNode }
destructor TMyrDerefNode.Destroy();
begin
  FBaseExpr.Free();

  inherited;
end;

{ TMyrSetElementNode }
destructor TMyrSetElementNode.Destroy();
begin
  FLowExpr.Free();
  FHighExpr.Free();

  inherited;
end;

{ TMyrFieldInitNode }
destructor TMyrFieldInitNode.Destroy();
begin
  FValueExpr.Free();

  inherited;
end;

{ TMyrTypeCastExprNode }
destructor TMyrTypeCastExprNode.Destroy();
begin
  if FTargetType <> nil then
    FTargetType.Free();
  FExpr.Free();

  inherited;
end;
{ TMyrMasterAST }
constructor TMyrMasterAST.Create();
begin
  inherited;

  FModules := TObjectList<TMyrModuleNode>.Create(True);
  FModuleMap := TDictionary<string, TMyrModuleNode>.Create();
  FPendingQueue := TQueue<string>.Create();
end;

destructor TMyrMasterAST.Destroy();
begin
  FPendingQueue.Free();
  FModuleMap.Free();
  FModules.Free();

  inherited;
end;

procedure TMyrMasterAST.AddModule(const AModule: TMyrModuleNode);
begin
  FModules.Add(AModule);
  FModuleMap.AddOrSetValue(AModule.ModuleName, AModule);
end;

function TMyrMasterAST.HasModule(const AModuleName: string): Boolean;
begin
  Result := FModuleMap.ContainsKey(AModuleName);
end;

function TMyrMasterAST.GetModule(const AModuleName: string): TMyrModuleNode;
begin
  if not FModuleMap.TryGetValue(AModuleName, Result) then
    Result := nil;
end;

procedure TMyrMasterAST.EnqueuePending(const AModuleName: string);
begin
  FPendingQueue.Enqueue(AModuleName);
end;

function TMyrMasterAST.DequeuePending(): string;
begin
  Result := FPendingQueue.Dequeue();
end;

function TMyrMasterAST.HasPending(): Boolean;
begin
  Result := FPendingQueue.Count > 0;
end;

function TMyrMasterAST.ModuleCount(): Integer;
begin
  Result := FModules.Count;
end;

function TMyrMasterAST.GetModuleAt(const AIndex: Integer): TMyrModuleNode;
begin
  Result := FModules[AIndex];
end;


{ TMyrParser }
constructor TMyrParser.Create();
begin
  inherited;

  FLexer := TMyrLexer.Create();
  FLexer.SetErrors(FErrors);
  FDefines := TDictionary<string, string>.Create();
  FCondStack := TList<TMyrCondState>.Create();
end;

destructor TMyrParser.Destroy();
begin
  FCondStack.Free();
  FDefines.Free();
  FLexer.Free();

  inherited;
end;

procedure TMyrParser.SetErrors(const AErrors: TErrors);
begin
  inherited;

  FLexer.SetErrors(AErrors);
end;

procedure TMyrParser.SetStatusCallback(const ACallback: TStatusCallback; const AUserData: Pointer);
begin
  inherited;

  FLexer.SetStatusCallback(ACallback, AUserData);
end;

function TMyrParser.Current(): TMyrToken;
begin
  Result := FLexer.CurrentToken();
end;

function TMyrParser.PeekAt(const AOffset: Int64): TMyrToken;
begin
  Result := FLexer.PeekAt(AOffset);
end;

function TMyrParser.Consume(): TMyrToken;
begin
  Result := FLexer.CurrentToken();
  FLastConsumedLoc := Result.Location;
  FLexer.NextToken();
  DoProcessConditionals();
end;

function TMyrParser.Match(const AKind: TMyrTokenKind): Boolean;
begin
  Result := Current().Kind = AKind;
  if Result then
  begin
    FLastConsumedLoc := Current().Location;
    FLexer.NextToken();
    DoProcessConditionals();
  end;
end;

function TMyrParser.Expect(const AKind: TMyrTokenKind): TMyrToken;
begin
  Result := Current();
  if Result.Kind = AKind then
  begin
    FLastConsumedLoc := Result.Location;
    FLexer.NextToken();
    DoProcessConditionals();
  end
  else
    FLexer.Expect(AKind);
end;

function TMyrParser.Check(const AKind: TMyrTokenKind): Boolean;
begin
  Result := Current().Kind = AKind;
end;

procedure TMyrParser.OptionalSemicolon();
begin
  Match(tkSemicolon);
end;

procedure TMyrParser.ExpectBlockEnd(const AConstruct: string;
  const AStartLocation: TSourceRange);
begin
  if not Match(tkEnd) then
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_002,
      'Expected "end" to close "%s" started at line %d',
      [AConstruct, AStartLocation.StartLine]);
end;

function TMyrParser.GetPrecedence(const AKind: TMyrTokenKind): Integer;
begin
  if IsRelOp(AKind) then
    Result := 1
  else if IsAddOp(AKind) then
    Result := 2
  else if IsMulOp(AKind) then
    Result := 3
  else
    Result := 0;
end;

function TMyrParser.IsRelOp(const AKind: TMyrTokenKind): Boolean;
begin
  Result := (AKind = tkEqual) or (AKind = tkNotEqual) or
            (AKind = tkLess) or (AKind = tkGreater) or
            (AKind = tkLessEqual) or (AKind = tkGreaterEqual) or
            (AKind = tkIn);
end;

function TMyrParser.IsAddOp(const AKind: TMyrTokenKind): Boolean;
begin
  Result := (AKind = tkPlus) or (AKind = tkMinus) or
            (AKind = tkOr) or (AKind = tkXor);
end;

function TMyrParser.IsMulOp(const AKind: TMyrTokenKind): Boolean;
begin
  Result := (AKind = tkStar) or (AKind = tkSlash) or
            (AKind = tkDiv) or (AKind = tkMod) or
            (AKind = tkAnd) or (AKind = tkShl) or (AKind = tkShr);
end;

function TMyrParser.IsAssignOp(const AKind: TMyrTokenKind): Boolean;
begin
  Result := (AKind = tkAssign) or (AKind = tkPlusAssign) or
            (AKind = tkMinusAssign) or (AKind = tkStarAssign) or
            (AKind = tkSlashAssign);
end;

function TMyrParser.IsStatementStart(const AKind: TMyrTokenKind): Boolean;
begin
  Result :=
    (AKind = tkIf) or (AKind = tkWhile) or (AKind = tkFor) or
    (AKind = tkRepeat) or (AKind = tkMatch) or (AKind = tkReturn) or
    (AKind = tkGuard) or (AKind = tkThrow) or (AKind = tkThrowCode) or
    (AKind = tkBreak) or (AKind = tkContinue) or
    (AKind = tkNew) or (AKind = tkDispose) or
    (AKind = tkGetMem) or (AKind = tkFreeMem) or
    (AKind = tkResizeMem) or (AKind = tkSetLength) or
    (AKind = tkPrint) or (AKind = tkPrintLn) or
    (AKind = tkAssert) or (AKind = tkAssertTrue) or (AKind = tkAssertFalse) or
    (AKind = tkAssertEq) or (AKind = tkAssertEqF) or (AKind = tkAssertNil) or
    (AKind = tkAssertNotNil) or (AKind = tkAssertFail) or
    (AKind = tkCppStart) or (AKind = tkCpp) or
    (AKind = tkDirective) or (AKind = tkVar) or
    (AKind = tkIdentifier) or (AKind = tkVarArgs);
end;

function TMyrParser.TokenToBinaryOp(const AKind: TMyrTokenKind): TMyrBinaryOp;
begin
  if AKind = tkPlus then Result := boAdd
  else if AKind = tkMinus then Result := boSub
  else if AKind = tkStar then Result := boMul
  else if AKind = tkSlash then Result := boDiv
  else if AKind = tkDiv then Result := boIntDiv
  else if AKind = tkMod then Result := boMod
  else if AKind = tkAnd then Result := boAnd
  else if AKind = tkOr then Result := boOr
  else if AKind = tkXor then Result := boXor
  else if AKind = tkShl then Result := boShl
  else if AKind = tkShr then Result := boShr
  else if AKind = tkEqual then Result := boEq
  else if AKind = tkNotEqual then Result := boNotEq
  else if AKind = tkLess then Result := boLess
  else if AKind = tkGreater then Result := boGreater
  else if AKind = tkLessEqual then Result := boLessEq
  else if AKind = tkGreaterEqual then Result := boGreaterEq
  else if AKind = tkIn then Result := boIn
  else
    Result := boAdd;  // should never reach here
end;

function TMyrParser.TokenToAssignOp(const AKind: TMyrTokenKind): TMyrAssignOp;
begin
  if AKind = tkAssign then Result := aoAssign
  else if AKind = tkPlusAssign then Result := aoPlusAssign
  else if AKind = tkMinusAssign then Result := aoMinusAssign
  else if AKind = tkStarAssign then Result := aoMulAssign
  else if AKind = tkSlashAssign then Result := aoDivAssign
  else
    Result := aoAssign;  // should never reach here
end;

function TMyrParser.IsIntrinsicToken(const AKind: TMyrTokenKind): Boolean;
begin
  Result := (AKind = tkLen) or (AKind = tkSize) or (AKind = tkUtf8) or
            (AKind = tkCStr) or (AKind = tkWStr) or
            (AKind = tkParamCount) or (AKind = tkParamStr) or
            (AKind = tkExcCode) or (AKind = tkExcMsg);
end;

function TMyrParser.TokenToIntrinsicKind(const AKind: TMyrTokenKind): TMyrIntrinsicKind;
begin
  if AKind = tkLen then Result := ikLen
  else if AKind = tkSize then Result := ikSize
  else if AKind = tkUtf8 then Result := ikUtf8
  else if AKind = tkCStr then Result := ikCStr
  else if AKind = tkWStr then Result := ikWStr
  else if AKind = tkParamCount then Result := ikParamCount
  else if AKind = tkParamStr then Result := ikParamStr
  else if AKind = tkExcCode then Result := ikExcCode
  else if AKind = tkExcMsg then Result := ikExcMsg
  else
    Result := ikLen;  // should never reach here
end;

procedure TMyrParser.SetDefine(const AName: string; const AValue: string);
begin
  FDefines.AddOrSetValue(AName, AValue);
end;

procedure TMyrParser.Undefine(const AName: string);
begin
  FDefines.Remove(AName);
end;

function TMyrParser.IsDefined(const AName: string): Boolean;
begin
  Result := FDefines.ContainsKey(AName);
end;

procedure TMyrParser.DoProcessConditionals();
var
  LTok: TMyrToken;
  LDirName: string;
  LSymbol: string;
  LState: TMyrCondState;
  LActive: Boolean;
begin
  while Current().Kind = tkDirective do
  begin
    LTok := Current();
    LDirName := LTok.TokenText;

    // @define SYMBOL
    if LDirName = 'define' then
    begin
      FLexer.NextToken(); // consume @define
      if Current().Kind = tkIdentifier then
      begin
        SetDefine(Current().TokenText, '1');
        FLexer.NextToken(); // consume symbol
      end
      else
        FErrors.Add(LTok.Location, esError, MYR_ERR_PAR_020,
          '@define requires an identifier argument');
    end

    // @undef SYMBOL
    else if LDirName = 'undef' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        Undefine(Current().TokenText);
        FLexer.NextToken();
      end
      else
        FErrors.Add(LTok.Location, esError, MYR_ERR_PAR_020,
          '@undef requires an identifier argument');
    end

    // @ifdef SYMBOL
    else if LDirName = 'ifdef' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        LSymbol := Current().TokenText;
        FLexer.NextToken();
      end
      else
      begin
        FErrors.Add(LTok.Location, esError, MYR_ERR_PAR_020,
          '@ifdef requires an identifier argument');
        LSymbol := '';
      end;
      LActive := IsDefined(LSymbol);
      LState := Default(TMyrCondState);
      LState.Active := LActive;
      LState.HadTrue := LActive;
      LState.HadElse := False;
      LState.ParentActive := True;
      FCondStack.Add(LState);
      if not LActive then
        DoSkipFalseBranch();
    end

    // @ifndef SYMBOL
    else if LDirName = 'ifndef' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        LSymbol := Current().TokenText;
        FLexer.NextToken();
      end
      else
      begin
        FErrors.Add(LTok.Location, esError, MYR_ERR_PAR_020,
          '@ifndef requires an identifier argument');
        LSymbol := '';
      end;
      LActive := not IsDefined(LSymbol);
      LState := Default(TMyrCondState);
      LState.Active := LActive;
      LState.HadTrue := LActive;
      LState.HadElse := False;
      LState.ParentActive := True;
      FCondStack.Add(LState);
      if not LActive then
        DoSkipFalseBranch();
    end

    // @elseif SYMBOL
    else if LDirName = 'elseif' then
    begin
      if FCondStack.Count = 0 then
      begin
        FErrors.Add(LTok.Location, esError, MYR_ERR_PAR_021,
          '@elseif without matching @ifdef');
        FLexer.NextToken();
      end
      else
      begin
        // We were in a true branch that just ended -- skip until @endif
        LState := FCondStack[FCondStack.Count - 1];
        LState.HadTrue := True;
        FCondStack[FCondStack.Count - 1] := LState;
        DoSkipFalseBranch();
      end;
    end

    // @else
    else if LDirName = 'else' then
    begin
      if FCondStack.Count = 0 then
      begin
        FErrors.Add(LTok.Location, esError, MYR_ERR_PAR_021,
          '@else without matching @ifdef');
        FLexer.NextToken();
      end
      else
      begin
        // We were in a true branch that just ended -- skip until @endif
        LState := FCondStack[FCondStack.Count - 1];
        LState.HadTrue := True;
        LState.HadElse := True;
        FCondStack[FCondStack.Count - 1] := LState;
        DoSkipFalseBranch();
      end;
    end

    // @endif
    else if LDirName = 'endif' then
    begin
      if FCondStack.Count = 0 then
        FErrors.Add(LTok.Location, esError, MYR_ERR_PAR_021,
          '@endif without matching @ifdef')
      else
        FCondStack.Delete(FCondStack.Count - 1);
      FLexer.NextToken();
    end

    // Not a conditional directive -- stop processing, let parser handle it
    else
      Break;
  end;
end;

procedure TMyrParser.DoSkipFalseBranch();
var
  LDepth: Integer;
  LDirName: string;
  LState: TMyrCondState;
  LSymbol: string;
begin
  // Skip tokens until we find a matching @else/@elseif/@endif at depth 0
  LDepth := 0;
  while Current().Kind <> tkEOF do
  begin
    if Current().Kind = tkDirective then
    begin
      LDirName := Current().TokenText;

      // Nested @ifdef/@ifndef increase depth
      if (LDirName = 'ifdef') or (LDirName = 'ifndef') then
      begin
        Inc(LDepth);
        FLexer.NextToken();
        // Skip the symbol argument too
        if Current().Kind = tkIdentifier then
          FLexer.NextToken();
        Continue;
      end;

      // @endif at our level means the conditional block is done
      if LDirName = 'endif' then
      begin
        if LDepth > 0 then
        begin
          Dec(LDepth);
          FLexer.NextToken();
          Continue;
        end;
        // Our @endif -- pop the stack and advance past it
        if FCondStack.Count > 0 then
          FCondStack.Delete(FCondStack.Count - 1);
        FLexer.NextToken();
        Exit;
      end;

      // @else at our level -- check if we should start emitting
      if (LDirName = 'else') and (LDepth = 0) then
      begin
        if FCondStack.Count > 0 then
        begin
          LState := FCondStack[FCondStack.Count - 1];
          if not LState.HadTrue then
          begin
            // This @else branch is active
            LState.Active := True;
            LState.HadTrue := True;
            LState.HadElse := True;
            FCondStack[FCondStack.Count - 1] := LState;
            FLexer.NextToken();
            Exit;
          end;
        end;
        FLexer.NextToken();
        Continue;
      end;

      // @elseif at our level -- evaluate the condition
      if (LDirName = 'elseif') and (LDepth = 0) then
      begin
        FLexer.NextToken(); // consume @elseif
        LSymbol := '';
        if Current().Kind = tkIdentifier then
        begin
          LSymbol := Current().TokenText;
          FLexer.NextToken();
        end;
        if FCondStack.Count > 0 then
        begin
          LState := FCondStack[FCondStack.Count - 1];
          if (not LState.HadTrue) and IsDefined(LSymbol) then
          begin
            // This @elseif branch is active
            LState.Active := True;
            LState.HadTrue := True;
            FCondStack[FCondStack.Count - 1] := LState;
            Exit;
          end;
        end;
        Continue;
      end;
    end;

    // Non-conditional token in false branch -- skip it
    FLexer.NextToken();
  end;

  // Reached EOF without @endif
  if FCondStack.Count > 0 then
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_022,
      'Unterminated @ifdef/@ifndef block');
end;

{ TMyrParser.DoSetupPredefinedDefines }
procedure TMyrParser.DoSetupPredefinedDefines(const AModuleKind: TMyrModuleKind);
begin
  // Always defined
  SetDefine('MYRISSA', '1');
  SetDefine('CPUX64', '1');

  // Module kind
  Undefine('BUILD_EXE');
  Undefine('BUILD_DLL');
  Undefine('BUILD_LIB');
  if AModuleKind = mkExe then
    SetDefine('BUILD_EXE', '1')
  else if AModuleKind = mkDll then
    SetDefine('BUILD_DLL', '1')
  else if AModuleKind = mkLib then
    SetDefine('BUILD_LIB', '1');

  // App type -- always console for now
  SetDefine('APPTYPE_CONSOLE', '1');
end;

function TMyrParser.ParseModule(const AFilename: string; const AMasterAST: TMyrMasterAST): TMyrModuleNode;
var
  LModule: TMyrModuleNode;
  LNormalized: string;
begin
  Result := nil;
  FMasterAST := AMasterAST;

  // Normalize filename with .cpas extension
  LNormalized := TPath.ChangeExtension(AFilename, MYR_SRCFILE_EXT);

  // Tokenize the source file
  if not FLexer.TokenizeFile(LNormalized) then
    Exit;

  // Prime conditional processing for the first token position
  DoProcessConditionals();

  // Create module node -- try/finally ensures cleanup on any failure path
  LModule := TMyrModuleNode.Create();
  try
    LModule.Location := Current().Location;
    LModule.SourceFile := LNormalized;

    // module ModuleKind name;
    Expect(tkModule);
    LModule.ModuleKind := DoParseModuleKind();

    // Set up predefined defines now that module kind is known
    DoSetupPredefinedDefines(LModule.ModuleKind);

    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
        'Expected module name identifier');
      Exit;
    end;
    LModule.ModuleName := Consume().TokenText;

    // Expect semicolon but advance without DoProcessConditionals so that
    // any @ifdef block in the directive section is left for DoParseDirectives
    if Current().Kind = tkSemicolon then
      FLexer.NextToken()
    else
      FLexer.Expect(tkSemicolon);

    // Directives, imports, declarations
    DoParseDirectives(LModule);
    DoParseImportClause(LModule);
    DoParseDeclarations(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Optional initialize/finalize blocks
    DoParseInitializeBlock(LModule);
    DoParseFinalizeBlock(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Main body: begin...end.
    DoParseMainBody(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Test blocks after end.
    DoParseTestBlocks(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Finalize module range to cover entire file
    LModule.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);

    // Success -- transfer ownership to caller
    Result := LModule;
    LModule := nil;
  finally
    LModule.Free();
  end;
end;

{ TMyrParser.ParseModuleFromString }
function TMyrParser.ParseModuleFromString(const ASource: string;
  const AFilename: string; const AMasterAST: TMyrMasterAST): TMyrModuleNode;
var
  LModule: TMyrModuleNode;
begin
  Result := nil;
  FMasterAST := AMasterAST;

  // Tokenize from string instead of file
  if not FLexer.TokenizeString(ASource, AFilename) then
    Exit;

  // Prime conditional processing for the first token position
  DoProcessConditionals();

  // Create module node -- try/finally ensures cleanup on any failure path
  LModule := TMyrModuleNode.Create();
  try
    LModule.Location := Current().Location;
    LModule.SourceFile := AFilename;

    // module ModuleKind name;
    Expect(tkModule);
    LModule.ModuleKind := DoParseModuleKind();

    // Set up predefined defines now that module kind is known
    DoSetupPredefinedDefines(LModule.ModuleKind);

    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
        'Expected module name identifier');
      Exit;
    end;
    LModule.ModuleName := Consume().TokenText;

    // Expect semicolon but advance without DoProcessConditionals so that
    // any @ifdef block in the directive section is left for DoParseDirectives
    if Current().Kind = tkSemicolon then
      FLexer.NextToken()
    else
      FLexer.Expect(tkSemicolon);

    // Directives, imports, declarations
    DoParseDirectives(LModule);
    DoParseImportClause(LModule);
    DoParseDeclarations(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Optional initialize/finalize blocks
    DoParseInitializeBlock(LModule);
    DoParseFinalizeBlock(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Main body: begin...end.
    DoParseMainBody(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Test blocks after end.
    DoParseTestBlocks(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Finalize module range to cover entire file
    LModule.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);

    // Success -- transfer ownership to caller
    Result := LModule;
    LModule := nil;
  finally
    LModule.Free();
  end;
end;

function TMyrParser.DoParseModuleKind(): TMyrModuleKind;
var
  LText: string;
begin
  // Module kind is a contextual keyword -- exe, dll, lib, unit are identifiers
  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_003,
      'Expected module kind (exe, dll, lib, unit)');
    Result := mkExe;
    Exit;
  end;

  LText := Current().TokenText;
  if LText = 'exe' then
    Result := mkExe
  else if LText = 'dll' then
    Result := mkDll
  else if LText = 'lib' then
    Result := mkLib
  else if LText = 'unit' then
    Result := mkUnit
  else
  begin
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_003,
      'Invalid module kind: %s (expected exe, dll, lib, unit)', [LText]);
    Result := mkExe;
  end;
  Consume();
end;

procedure TMyrParser.DoParseDirectives(const AModule: TMyrModuleNode);
var
  LDirective: TMyrDirectiveNode;
  LName: string;
begin
  // Directives start with @ (tkDirective)
  while Current().Kind = tkDirective do
  begin
    LName := Current().TokenText;

    // Conditional compilation directives are handled by DoProcessConditionals,
    // which manages the condition stack and skips inactive branches.
    if LName.StartsWith('define') or LName.StartsWith('undef') or
       LName.StartsWith('ifdef') or LName.StartsWith('ifndef') or
       LName.StartsWith('elseif') or
       (LName = 'else') or (LName = 'endif') then
    begin
      DoProcessConditionals();
      Continue;
    end;

    // Content directive (copydll, librarypath, target, etc.)
    LDirective := TMyrDirectiveNode.Create();
    LDirective.Location := Current().Location;
    LDirective.DirectiveName := LName;
    Consume();

    // Directive value: string, integer, float, or identifier
    if (Current().Kind = tkStringLiteral) or
       (Current().Kind = tkIntLiteral) or
       (Current().Kind = tkFloatLiteral) or
       (Current().Kind = tkIdentifier) then
    begin
      LDirective.DirectiveValue := Current().TokenText;
      Consume();

      // Second value for @message: severity followed by text
      if (LDirective.DirectiveName = 'message') and
         (Current().Kind = tkStringLiteral) then
      begin
        LDirective.DirectiveValue2 := Current().TokenText;
        Consume();
      end;
    end;

    Expect(tkSemicolon);
    AModule.Directives.Add(LDirective);
  end;
end;

procedure TMyrParser.DoParseImportClause(const AModule: TMyrModuleNode);
var
  LImport: TMyrImportNode;
  LName: string;
begin
  if not Match(tkImport) then
    Exit;

  // import name1, name2, name3;
  repeat
    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
        'Expected module name in import clause');
      Exit;
    end;

    LName := Current().TokenText;

    LImport := TMyrImportNode.Create();
    LImport.Location := Current().Location;
    LImport.ModuleName := LName;
    AModule.Imports.Add(LImport);

    // Enqueue for parsing if not already on the master AST
    if Assigned(FMasterAST) and not FMasterAST.HasModule(LName) then
      FMasterAST.EnqueuePending(LName);

    Consume();
  until not Match(tkComma);

  Expect(tkSemicolon);
end;

procedure TMyrParser.DoParseDeclarations(const AModule: TMyrModuleNode);
var
  LIsPublic: Boolean;
begin
  // Parse declarations until we hit initialize, finalize, begin, or EOF
  while not (Check(tkInitialize) or Check(tkFinalize) or Check(tkBegin) or
             Check(tkEnd) or Check(tkEOF)) do
  begin
    // Check for public modifier
    LIsPublic := Match(tkPublic);

    if Check(tkConst) then
    begin
      Consume();
      // Parse multiple const declarations in the section
      // Note: public followed by a section keyword (const/type/var/routine)
      // starts a new section -- don't consume it here
      while (Current().Kind = tkIdentifier) or
            ((Current().Kind = tkPublic) and (PeekAt(1).Kind = tkIdentifier)) do
      begin
        if Current().Kind = tkPublic then
        begin
          Consume();
          AModule.Declarations.Add(DoParseConstDecl(True));
        end
        else
          AModule.Declarations.Add(DoParseConstDecl(LIsPublic));
      end;
    end
    else if Check(tkType) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) or
            ((Current().Kind = tkPublic) and (PeekAt(1).Kind = tkIdentifier)) do
      begin
        if Current().Kind = tkPublic then
        begin
          Consume();
          AModule.Declarations.Add(DoParseTypeDecl(True));
        end
        else
          AModule.Declarations.Add(DoParseTypeDecl(LIsPublic));
      end;
    end
    else if Check(tkVar) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) or
            ((Current().Kind = tkPublic) and (PeekAt(1).Kind = tkIdentifier)) do
      begin
        if Current().Kind = tkPublic then
        begin
          Consume();
          AModule.Declarations.Add(DoParseVarDecl(True));
        end
        else
          AModule.Declarations.Add(DoParseVarDecl(LIsPublic));
      end;
    end
    else if Check(tkRoutine) then
    begin
      AModule.Declarations.Add(DoParseRoutineDecl(LIsPublic));
    end
    else if Check(tkForward) then
    begin
      AModule.Declarations.Add(DoParseForwardDecl());
    end
    else if Check(tkCppStart) then
    begin
      AModule.Declarations.Add(DoParseCppBlock());
    end
    else if Current().Kind = tkDirective then
    begin
      // Statement-level directives within declarations
      DoParseDirectives(AModule);
    end
    else
    begin
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_001,
        'Unexpected token in declarations: %s', [Current().TokenText]);
      Consume();  // skip to avoid infinite loop
    end;

    // Bail on error -- everything after is unreliable
    if FErrors.HasErrors() then
      Break;
  end;
end;

procedure TMyrParser.DoParseInitializeBlock(const AModule: TMyrModuleNode);
var
  LBody: TObjectList<TMyrASTNode>;
begin
  if not Match(tkInitialize) then
    Exit;

  LBody := DoParseStatementSeq([tkEnd]);
  AModule.InitBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  Expect(tkEnd);
  Expect(tkSemicolon);
end;

procedure TMyrParser.DoParseFinalizeBlock(const AModule: TMyrModuleNode);
var
  LBody: TObjectList<TMyrASTNode>;
begin
  if not Match(tkFinalize) then
    Exit;

  LBody := DoParseStatementSeq([tkEnd]);
  AModule.FinalBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  Expect(tkEnd);
  Expect(tkSemicolon);
end;

procedure TMyrParser.DoParseMainBody(const AModule: TMyrModuleNode);
var
  LBody: TObjectList<TMyrASTNode>;
begin
  // Unit modules have no begin block -- just end.
  if not Check(tkBegin) then
  begin
    Expect(tkEnd);
    Expect(tkDot);
    Exit;
  end;

  AModule.HasMainBody := True;
  Consume(); // consume 'begin'

  LBody := DoParseStatementSeq([tkEnd]);
  AModule.MainBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  Expect(tkEnd);
  Expect(tkDot);
end;

procedure TMyrParser.DoParseTestBlocks(const AModule: TMyrModuleNode);
var
  LTest: TMyrTestBlockNode;
  LBody: TObjectList<TMyrASTNode>;
begin
  while Check(tkTest) do
  begin
    LTest := TMyrTestBlockNode.Create();
    LTest.Location := Current().Location;
    Consume();

    // test "name"
    if Current().Kind <> tkStringLiteral then
    begin
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_002,
        'Expected string literal for test name');
      LTest.Free();
      Exit;
    end;
    LTest.TestName := Current().LiteralValue.AsString();
    Consume();

    // Optional var section
    if Match(tkVar) then
    begin
      while Current().Kind = tkIdentifier do
        LTest.Locals.Add(DoParseVarDecl(False));
    end;

    // begin...end;
    Expect(tkBegin);
    LBody := DoParseStatementSeq([tkEnd]);
    LTest.Body.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();
    Expect(tkEnd);
    Expect(tkSemicolon);

    // Finalize test block range
    LTest.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);

    AModule.TestBlocks.Add(LTest);
  end;
end;

function TMyrParser.DoParseConstDecl(const AIsPublic: Boolean): TMyrConstDeclNode;
begin
  Result := TMyrConstDeclNode.Create();
  Result.Location := Current().Location;
  Result.IsPublic := AIsPublic;

  // name [: type] = value;
  Result.DeclName := Current().TokenText;
  Consume();

  // Optional type annotation
  if Match(tkColon) then
    Result.TypeExpr := DoParseTypeExpr();

  Expect(tkEqual);
  Result.ValueExpr := DoParseExpression();
  Expect(tkSemicolon);
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseTypeDecl(const AIsPublic: Boolean): TMyrTypeDeclNode;
begin
  Result := TMyrTypeDeclNode.Create();
  Result.Location := Current().Location;
  Result.IsPublic := AIsPublic;

  // name = typedef;
  Result.DeclName := Current().TokenText;
  Consume();

  Expect(tkEqual);
  Result.TypeDef := DoParseTypeDef();
  Expect(tkSemicolon);
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseVarDecl(const AIsPublic: Boolean): TMyrVarDeclNode;
begin
  Result := TMyrVarDeclNode.Create();
  Result.Location := Current().Location;
  Result.IsPublic := AIsPublic;

  // name: type [= value]; [external lib;]
  Result.DeclName := Current().TokenText;
  Consume();

  Expect(tkColon);
  Result.TypeExpr := DoParseTypeExpr();

  // Optional initializer
  if Match(tkEqual) then
    Result.InitExpr := DoParseExpression();

  Expect(tkSemicolon);

  // Optional external clause
  if Match(tkExternal) then
  begin
    Result.IsExternal := True;
    // Optional library: string literal or identifier (but not "name" followed by string)
    if Current().Kind = tkStringLiteral then
    begin
      Result.ExternalLib := Current().TokenText;
      Consume();
    end
    else if (Current().Kind = tkIdentifier) and
            not ((Current().TokenText = 'name') and (PeekAt(1).Kind = tkStringLiteral)) then
    begin
      Result.ExternalLib := Current().TokenText;
      Consume();
    end;
    // Optional name clause: name "symbol"
    if (Current().Kind = tkIdentifier) and (Current().TokenText = 'name') then
    begin
      Consume();
      if Current().Kind = tkStringLiteral then
      begin
        Result.ExternalName := Current().TokenText;
        Consume();
      end
      else
        FErrors.Add(Current().Location, esError, MYR_ERR_PAR_002,
          'Expected string literal after "name"');
    end;
    Expect(tkSemicolon);
  end;
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseRoutineDecl(const AIsPublic: Boolean): TMyrRoutineDeclNode;
begin
  Result := TMyrRoutineDeclNode.Create();
  Result.Location := Current().Location;
  Result.IsPublic := AIsPublic;

  // routine [linkage] name(params) [: returntype];
  Expect(tkRoutine);

  // Optional linkage spec
  if Check(tkCLink) then
  begin
    Result.Linkage := lkCLink;
    Consume();
  end
  else if Check(tkCppLink) then
  begin
    Result.Linkage := lkCppLink;
    Consume();
  end;

  // Routine name
  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
      'Expected routine name');
    Result.Free();
    Result := nil;
    Exit;
  end;
  Result.DeclName := Current().TokenText;
  Consume();

  // Optional formal parameters
  if Check(tkLParen) then
    DoParseFormalParams(Result);

  // Optional return type
  if Match(tkColon) then
    Result.ReturnType := DoParseTypeExpr();

  Expect(tkSemicolon);

  // External clause or body
  if Match(tkExternal) then
  begin
    Result.IsExternal := True;
    // Optional library: string literal or identifier (but not "name" followed by string)
    if Current().Kind = tkStringLiteral then
    begin
      Result.ExternalLib := Current().TokenText;
      Consume();
    end
    else if (Current().Kind = tkIdentifier) and
            not ((Current().TokenText = 'name') and (PeekAt(1).Kind = tkStringLiteral)) then
    begin
      Result.ExternalLib := Current().TokenText;
      Consume();
    end;
    // Optional name clause: name "symbol"
    if (Current().Kind = tkIdentifier) and (Current().TokenText = 'name') then
    begin
      Consume();
      if Current().Kind = tkStringLiteral then
      begin
        Result.ExternalName := Current().TokenText;
        Consume();
      end
      else
        FErrors.Add(Current().Location, esError, MYR_ERR_PAR_002,
          'Expected string literal after "name"');
    end;
    Expect(tkSemicolon);
  end
  else
    DoParseRoutineBody(Result);

  // Finalize routine range
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseForwardDecl(): TMyrASTNode;
var
  LForwardType: TMyrForwardTypeDeclNode;
  LForwardRoutine: TMyrForwardRoutineDeclNode;
begin
  Result := nil;
  Expect(tkForward);

  if Check(tkType) then
  begin
    // forward type TFoo;
    Consume();
    LForwardType := TMyrForwardTypeDeclNode.Create();
    LForwardType.Location := Current().Location;

    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
        'Expected type name after forward type');
      LForwardType.Free();
      Exit;
    end;
    LForwardType.DeclName := Current().TokenText;
    Consume();
    Expect(tkSemicolon);
    Result := LForwardType;
  end
  else if Check(tkRoutine) then
  begin
    // forward routine Foo(params): ReturnType;
    Consume();
    LForwardRoutine := TMyrForwardRoutineDeclNode.Create();
    LForwardRoutine.Location := Current().Location;

    // Optional linkage spec
    if Check(tkCLink) then
    begin
      LForwardRoutine.Linkage := lkCLink;
      Consume();
    end
    else if Check(tkCppLink) then
    begin
      LForwardRoutine.Linkage := lkCppLink;
      Consume();
    end;

    // Routine name
    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
        'Expected routine name after forward routine');
      LForwardRoutine.Free();
      Exit;
    end;
    LForwardRoutine.DeclName := Current().TokenText;
    Consume();

    // Optional formal parameters
    if Check(tkLParen) then
    begin
      Expect(tkLParen);

      if not Check(tkRParen) then
      begin
        // Lone ellipsis
        if Check(tkEllipsis) then
        begin
          LForwardRoutine.IsVariadic := True;
          Consume();
        end
        else
        begin
          LForwardRoutine.Params.Add(DoParseParamDecl());
          while Match(tkSemicolon) do
          begin
            if Check(tkEllipsis) then
            begin
              LForwardRoutine.IsVariadic := True;
              Consume();
              Break;
            end;
            LForwardRoutine.Params.Add(DoParseParamDecl());
          end;
        end;
      end;

      Expect(tkRParen);
    end;

    // Optional return type
    if Match(tkColon) then
      LForwardRoutine.ReturnType := DoParseTypeExpr();

    Expect(tkSemicolon);
    Result := LForwardRoutine;
  end
  else
  begin
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_001,
      'Expected "type" or "routine" after "forward"');
  end;
end;

procedure TMyrParser.DoParseFormalParams(const ARoutine: TMyrRoutineDeclNode);
begin
  Expect(tkLParen);

  // Empty params
  if Check(tkRParen) then
  begin
    Consume();
    Exit;
  end;

  // Lone ellipsis: routine foo(...);
  if Check(tkEllipsis) then
  begin
    ARoutine.IsVariadic := True;
    Consume();
    Expect(tkRParen);
    Exit;
  end;

  // Parse parameter declarations
  ARoutine.Params.Add(DoParseParamDecl());
  while Match(tkSemicolon) do
  begin
    // Check for trailing ellipsis: routine foo(a: int32; ...);
    if Check(tkEllipsis) then
    begin
      ARoutine.IsVariadic := True;
      Consume();
      Break;
    end;
    ARoutine.Params.Add(DoParseParamDecl());
  end;

  Expect(tkRParen);
end;

function TMyrParser.DoParseParamDecl(): TMyrParamDeclNode;
begin
  Result := TMyrParamDeclNode.Create();
  Result.Location := Current().Location;

  // [var | const] name: type
  if Match(tkVar) then
    Result.ParamMode := pmVar
  else if Match(tkConst) then
    Result.ParamMode := pmConst
  else
    Result.ParamMode := pmDefault;

  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
      'Expected parameter name');
    Result.Free();
    Result := nil;
    Exit;
  end;
  Result.ParamName := Current().TokenText;
  Consume();

  Expect(tkColon);
  Result.TypeExpr := DoParseTypeExpr();
end;

procedure TMyrParser.DoParseRoutineBody(const ARoutine: TMyrRoutineDeclNode);
var
  LBody: TObjectList<TMyrASTNode>;
begin
  // Optional local type/const/var sections
  if Match(tkType) then
  begin
    while Current().Kind = tkIdentifier do
      ARoutine.LocalTypes.Add(DoParseTypeDecl(False));
  end;

  if Match(tkConst) then
  begin
    while Current().Kind = tkIdentifier do
      ARoutine.LocalConsts.Add(DoParseConstDecl(False));
  end;

  if Match(tkVar) then
  begin
    while Current().Kind = tkIdentifier do
      ARoutine.LocalVars.Add(DoParseVarDecl(False));
  end;

  // begin...end;
  Expect(tkBegin);
  LBody := DoParseStatementSeq([tkEnd]);
  ARoutine.Body.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();
  Expect(tkEnd);
  Expect(tkSemicolon);
end;

function TMyrParser.DoParseTypeDef(): TMyrASTNode;
begin
  if Check(tkRecord) then
    Result := DoParseRecordType()
  else if Check(tkOverlay) then
    Result := DoParseOverlayType()
  else if Check(tkArray) then
    Result := DoParseArrayType()
  else if Check(tkPointer) then
    Result := DoParsePointerType()
  else if Check(tkSet) then
    Result := DoParseSetType()
  else if Check(tkChoices) then
    Result := DoParseChoicesType()
  else if Check(tkRoutine) then
    Result := DoParseRoutineTypeDef()
  else
    Result := DoParseTypeExpr();
end;

function TMyrParser.DoParseRecordType(): TMyrRecordTypeNode;
var
  LAnon: TMyrAnonOverlayNode;
begin
  Result := TMyrRecordTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'record'

  // Optional packed
  if Match(tkPacked) then
    Result.IsPacked := True;

  // Optional align(n)
  if Match(tkAlign) then
  begin
    Expect(tkLParen);
    if Current().Kind = tkIntLiteral then
    begin
      Result.Alignment := StrToIntDef(Current().TokenText, 0);
      Consume();
    end;
    Expect(tkRParen);
  end;

  // Optional base type: record(BaseType)
  if Match(tkLParen) then
  begin
    Result.BaseType := DoParseTypeExpr();
    Expect(tkRParen);
  end;

  // Fields and anonymous overlays until 'end'
  while not (Check(tkEnd) or Check(tkEOF)) do
  begin
    if Check(tkOverlay) then
    begin
      LAnon := TMyrAnonOverlayNode.Create();
      LAnon.Location := Current().Location;
      Consume();  // consume 'overlay'
      while not (Check(tkEnd) or Check(tkEOF)) do
      begin
        if Check(tkRecord) then
        begin
          // Nested anonymous record inside anonymous overlay
          LAnon.Fields.Add(DoParseRecordType());
          Expect(tkSemicolon);
        end
        else
          LAnon.Fields.Add(DoParseFieldDecl());

        if FErrors.HasErrors() then
          Break;
      end;
      Expect(tkEnd);
      Expect(tkSemicolon);
      Result.Fields.Add(LAnon);
    end
    else
      Result.Fields.Add(DoParseFieldDecl());

    if FErrors.HasErrors() then
      Break;
  end;

  Expect(tkEnd);
end;

function TMyrParser.DoParseOverlayType(): TMyrOverlayTypeNode;
var
  LAnon: TMyrAnonRecordNode;
begin
  Result := TMyrOverlayTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'overlay'

  while not (Check(tkEnd) or Check(tkEOF)) do
  begin
    if Check(tkRecord) then
    begin
      LAnon := TMyrAnonRecordNode.Create();
      LAnon.Location := Current().Location;
      Consume();  // consume 'record'
      if Match(tkPacked) then
        LAnon.IsPacked := True;
      while not (Check(tkEnd) or Check(tkEOF)) do
      begin
        LAnon.Fields.Add(DoParseFieldDecl());
        if FErrors.HasErrors() then
          Break;
      end;
      Expect(tkEnd);
      Expect(tkSemicolon);
      Result.Fields.Add(LAnon);
    end
    else
      Result.Fields.Add(DoParseFieldDecl());

    if FErrors.HasErrors() then
      Break;
  end;

  Expect(tkEnd);
end;

function TMyrParser.DoParseFieldDecl(): TMyrFieldDeclNode;
begin
  Result := TMyrFieldDeclNode.Create();
  Result.Location := Current().Location;

  // name: type [: bitwidth];
  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
      'Expected field name');
    Result.Free();
    Result := nil;
    Exit;
  end;
  Result.FieldName := Current().TokenText;
  Consume();

  Expect(tkColon);
  Result.TypeExpr := DoParseTypeExpr();

  // Optional bit width
  if Match(tkColon) then
  begin
    if Current().Kind = tkIntLiteral then
    begin
      Result.BitWidth := StrToIntDef(Current().TokenText, 0);
      Consume();
    end;
  end;

  Expect(tkSemicolon);
end;

function TMyrParser.DoParseArrayType(): TMyrArrayTypeNode;
begin
  Result := TMyrArrayTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'array'

  // Optional bounds: [low..high]
  if Match(tkLBracket) then
  begin
    if Check(tkRBracket) then
    begin
      // Dynamic array: array[] of type
      Result.IsDynamic := True;
    end
    else
    begin
      // Static array: array[low..high] of type
      Result.IsDynamic := False;
      if Current().Kind = tkIntLiteral then
      begin
        Result.LowBound := StrToInt64Def(Current().TokenText, 0);
        Consume();
      end;
      Expect(tkDotDot);
      if Current().Kind = tkIntLiteral then
      begin
        Result.HighBound := StrToInt64Def(Current().TokenText, 0);
        Consume();
      end;
    end;
    Expect(tkRBracket);
  end
  else
    Result.IsDynamic := True;  // array of type (no brackets)

  Expect(tkOf);
  Result.ElementType := DoParseTypeExpr();
end;

function TMyrParser.DoParsePointerType(): TMyrPointerTypeNode;
begin
  Result := TMyrPointerTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'pointer'

  // Optional: pointer to [const] type
  if Current().Kind = tkTo then
  begin
    Consume();
    if Match(tkConst) then
      Result.IsConstTarget := True;
    Result.TargetType := DoParseTypeExpr();
  end;
end;

function TMyrParser.DoParseSetType(): TMyrSetTypeNode;
begin
  Result := TMyrSetTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'set'

  // Optional: set of (range | type)
  if Match(tkOf) then
  begin
    // Check if it's integer..integer range form
    if (Current().Kind = tkIntLiteral) and (PeekAt(1).Kind = tkDotDot) then
    begin
      Result.IsRangeForm := True;
      Result.RangeLow := StrToInt64Def(Current().TokenText, 0);
      Consume();
      Expect(tkDotDot);
      Result.RangeHigh := StrToInt64Def(Current().TokenText, 0);
      Consume();
    end
    else
      Result.ElementType := DoParseTypeExpr();
  end;
end;

function TMyrParser.DoParseChoicesType(): TMyrChoicesTypeNode;
var
  LValue: TMyrChoicesValueNode;
begin
  Result := TMyrChoicesTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'choices'

  Expect(tkLParen);

  repeat
    LValue := TMyrChoicesValueNode.Create();
    LValue.Location := Current().Location;

    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
        'Expected choices member name');
      LValue.Free();
      Break;
    end;
    LValue.MemberName := Current().TokenText;
    Consume();

    // Optional explicit value: = expr
    if Match(tkEqual) then
      LValue.ValueExpr := DoParseExpression();

    Result.Members.Add(LValue);
  until not Match(tkComma);

  Expect(tkRParen);
end;

function TMyrParser.DoParseRoutineTypeDef(): TMyrRoutineTypeNode;
begin
  Result := TMyrRoutineTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'routine'

  // Optional linkage
  if Check(tkCLink) then
  begin
    Result.Linkage := lkCLink;
    Consume();
  end
  else if Check(tkCppLink) then
  begin
    Result.Linkage := lkCppLink;
    Consume();
  end;

  // Parameters
  Expect(tkLParen);
  if not Check(tkRParen) then
  begin
    // Check for lone ellipsis
    if Check(tkEllipsis) then
    begin
      Result.IsVariadic := True;
      Consume();
    end
    else
    begin
      Result.Params.Add(DoParseParamDecl());
      while Match(tkSemicolon) do
      begin
        if Check(tkEllipsis) then
        begin
          Result.IsVariadic := True;
          Consume();
          Break;
        end;
        Result.Params.Add(DoParseParamDecl());
      end;
    end;
  end;
  Expect(tkRParen);

  // Optional return type
  if Match(tkColon) then
    Result.ReturnType := DoParseTypeExpr();
end;

function TMyrParser.DoParseTypeExpr(): TMyrASTNode;
var
  LRef: TMyrTypeRefNode;
  LParts: TList<string>;
begin
  // Inline type expressions: pointer, array, set, or named type reference
  // Bare 'pointer' is a primitive (void*); 'pointer to T' is a typed pointer
  if Check(tkPointer) and (PeekAt(1).Kind = tkTo) then
  begin
    Result := DoParsePointerType();
    Exit;
  end;

  if Check(tkArray) then
  begin
    Result := DoParseArrayType();
    Exit;
  end;

  if Check(tkSet) then
  begin
    Result := DoParseSetType();
    Exit;
  end;

  // Primitive type keyword or qualified identifier
  LRef := TMyrTypeRefNode.Create();
  LRef.Location := Current().Location;

  if FLexer.IsDataType(Current().Kind) then
  begin
    // Primitive type: int32, float64, string, etc.
    LRef.TokenKind := Current().Kind;
    LRef.CppTypeText := FLexer.GetCppType(Current().Kind);
    LRef.QualParts := [Current().TokenText];
    Consume();
  end
  else if Current().Kind = tkIdentifier then
  begin
    // User type, possibly qualified: ModName.TypeName
    LRef.TokenKind := tkIdentifier;
    LParts := TList<string>.Create();
    try
      LParts.Add(Current().TokenText);
      Consume();
      while Match(tkDot) do
      begin
        if Current().Kind <> tkIdentifier then
        begin
          FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
            'Expected identifier after "."');
          Break;
        end;
        LParts.Add(Current().TokenText);
        Consume();
      end;
      LRef.QualParts := LParts.ToArray();
    finally
      LParts.Free();
    end;
  end
  else
  begin
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_005,
      'Expected type expression, got: %s', [Current().TokenText]);
    LRef.Free();
    Result := nil;
    Exit;
  end;

  Result := LRef;
end;

function TMyrParser.DoParseStatementSeq(const ATerminators: array of TMyrTokenKind): TObjectList<TMyrASTNode>;
var
  LStmt: TMyrASTNode;
  LKind: TMyrTokenKind;
  LIsTerminator: Boolean;
begin
  Result := TObjectList<TMyrASTNode>.Create(True);

  while not Check(tkEOF) do
  begin
    // Check if current token is a terminator
    LIsTerminator := False;
    for LKind in ATerminators do
    begin
      if Check(LKind) then
      begin
        LIsTerminator := True;
        Break;
      end;
    end;
    if LIsTerminator then
      Break;

    // Skip lone semicolons
    if Match(tkSemicolon) then
      Continue;

    LStmt := DoParseStatement();
    if Assigned(LStmt) then
      Result.Add(LStmt);

    // Bail on error -- everything after is unreliable
    if FErrors.HasErrors() then
      Break;
  end;
end;

function TMyrParser.DoParseStatement(): TMyrASTNode;
begin
  Result := nil;

  if Check(tkIf) then
    Result := DoParseIfStmt()
  else if Check(tkWhile) then
    Result := DoParseWhileStmt()
  else if Check(tkFor) then
    Result := DoParseForStmt()
  else if Check(tkRepeat) then
    Result := DoParseRepeatStmt()
  else if Check(tkMatch) then
    Result := DoParseMatchStmt()
  else if Check(tkReturn) then
    Result := DoParseReturnStmt()
  else if Check(tkGuard) then
    Result := DoParseGuardStmt()
  else if Check(tkThrow) or Check(tkThrowCode) then
    Result := DoParseThrowStmt()
  else if Check(tkBreak) then
  begin
    Result := TMyrBreakNode.Create();
    Result.Location := Current().Location;
    Consume();
    OptionalSemicolon();
  end
  else if Check(tkContinue) then
  begin
    Result := TMyrContinueNode.Create();
    Result.Location := Current().Location;
    Consume();
    OptionalSemicolon();
  end
  else if Check(tkNew) then
    Result := DoParseNewStmt()
  else if Check(tkDispose) then
    Result := DoParseDisposeStmt()
  else if Check(tkGetMem) then
    Result := DoParseGetMemStmt()
  else if Check(tkFreeMem) then
    Result := DoParseFreeMemStmt()
  else if Check(tkResizeMem) then
    Result := DoParseResizeMemStmt()
  else if Check(tkSetLength) then
    Result := DoParseSetLengthStmt()
  else if Check(tkPrint) or Check(tkPrintLn) then
    Result := DoParsePrintStmt()
  else if Check(tkAssert) or Check(tkAssertTrue) or Check(tkAssertFalse) or
          Check(tkAssertEq) or Check(tkAssertEqF) or Check(tkAssertNil) or
          Check(tkAssertNotNil) or Check(tkAssertFail) then
    Result := DoParseAssertStmt()
  else if Check(tkCppStart) then
    Result := DoParseCppBlock()
  else if Check(tkCpp) then
    Result := DoParseCppStmt()
  else if Check(tkDirective) then
  begin
    // Statement-level directive (@breakpoint, @message)
    Result := TMyrDirectiveNode.Create();
    Result.Location := Current().Location;
    TMyrDirectiveNode(Result).DirectiveName := Current().TokenText;
    Consume();
    if (Current().Kind = tkIdentifier) or (Current().Kind = tkStringLiteral) then
    begin
      TMyrDirectiveNode(Result).DirectiveValue := Current().TokenText;
      Consume();
      // @message has severity + string, consume the string too
      if Current().Kind = tkStringLiteral then
      begin
        TMyrDirectiveNode(Result).DirectiveValue :=
          TMyrDirectiveNode(Result).DirectiveValue + ' ' + Current().TokenText;
        Consume();
      end;
    end;
    OptionalSemicolon();
  end
  else if Check(tkVar) then
  begin
    // Inline var declaration in statement position
    Consume(); // consume 'var'
    Result := DoParseVarDecl(False);
  end
  else if Check(tkIdentifier) or Check(tkVarArgs) then
    Result := DoParseAssignOrCall()
  else
  begin
    if Check(tkDot) then
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_006,
        'Unexpected end of module -- likely a missing "end" for an if, while, for, match, or guard block')
    else
      FErrors.Add(Current().Location, esError, MYR_ERR_PAR_006,
        'Unexpected token in statement: %s', [Current().TokenText]);
    Consume();
  end;
end;

function TMyrParser.DoParseAssignOrCall(): TMyrASTNode;
var
  LLeft: TMyrASTNode;
  LAssign: TMyrAssignNode;
  LCallStmt: TMyrCallStmtNode;
begin
  // Parse the left side as an expression (designator chain)
  LLeft := DoParseExpression();

  // Check for assignment operator
  if IsAssignOp(Current().Kind) then
  begin
    LAssign := TMyrAssignNode.Create();
    LAssign.Location := LLeft.Location;
    LAssign.Target := LLeft;
    LAssign.Op := TokenToAssignOp(Current().Kind);
    Consume();
    LAssign.ValueExpr := DoParseExpression();
    OptionalSemicolon();
    LAssign.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
    Result := LAssign;
  end
  else
  begin
    // Treat as call statement
    LCallStmt := TMyrCallStmtNode.Create();
    LCallStmt.Location := LLeft.Location;
    LCallStmt.CallExpr := LLeft;
    OptionalSemicolon();
    LCallStmt.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
    Result := LCallStmt;
  end;
end;

function TMyrParser.DoParseIfStmt(): TMyrIfNode;
var
  LBody: TObjectList<TMyrASTNode>;
begin
  Result := TMyrIfNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'if'

  Result.Condition := DoParseExpression();
  Expect(tkThen);

  LBody := DoParseStatementSeq([tkElse, tkEnd]);
  Result.ThenBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  if Match(tkElse) then
  begin
    LBody := DoParseStatementSeq([tkEnd]);
    Result.ElseBody.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();
  end;

  ExpectBlockEnd('if', Result.Location);
  OptionalSemicolon();
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseWhileStmt(): TMyrWhileNode;
var
  LBody: TObjectList<TMyrASTNode>;
begin
  Result := TMyrWhileNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'while'

  Result.Condition := DoParseExpression();
  Expect(tkDo);

  LBody := DoParseStatementSeq([tkEnd]);
  Result.Body.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  ExpectBlockEnd('while', Result.Location);
  OptionalSemicolon();
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseForStmt(): TMyrForNode;
var
  LBody: TObjectList<TMyrASTNode>;
begin
  Result := TMyrForNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'for'

  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
      'Expected iterator variable name');
    Result.Free();
    Result := nil;
    Exit;
  end;
  Result.IteratorName := Current().TokenText;
  Consume();

  Expect(tkAssign);
  Result.StartExpr := DoParseExpression();

  if Match(tkDownTo) then
    Result.IsDownTo := True
  else
    Expect(tkTo);

  Result.EndExpr := DoParseExpression();
  Expect(tkDo);

  LBody := DoParseStatementSeq([tkEnd]);
  Result.Body.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  ExpectBlockEnd('for', Result.Location);
  OptionalSemicolon();
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseRepeatStmt(): TMyrRepeatNode;
var
  LBody: TObjectList<TMyrASTNode>;
begin
  Result := TMyrRepeatNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'repeat'

  LBody := DoParseStatementSeq([tkUntil]);
  Result.Body.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  Expect(tkUntil);
  Result.Condition := DoParseExpression();
  OptionalSemicolon();
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseMatchStmt(): TMyrMatchNode;
var
  LBody: TObjectList<TMyrASTNode>;
begin
  Result := TMyrMatchNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'match'

  Result.Expr := DoParseExpression();
  Expect(tkOf);

  // Parse match arms until else or end
  while not (Check(tkElse) or Check(tkEnd) or Check(tkEOF)) do
    Result.Arms.Add(DoParseMatchArm());

  if Match(tkElse) then
  begin
    LBody := DoParseStatementSeq([tkEnd]);
    Result.ElseBody.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();
  end;

  ExpectBlockEnd('match', Result.Location);
  OptionalSemicolon();
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseMatchArm(): TMyrMatchArmNode;
var
  LLabel: TMyrMatchLabelNode;
  LStmt: TMyrASTNode;
begin
  Result := TMyrMatchArmNode.Create();
  Result.Location := Current().Location;

  // label1, label2, ...: body
  repeat
    LLabel := TMyrMatchLabelNode.Create();
    LLabel.Location := Current().Location;
    LLabel.LowExpr := DoParseExpression();

    // Check for range: expr..expr
    if Match(tkDotDot) then
      LLabel.HighExpr := DoParseExpression();

    Result.Labels.Add(LLabel);
  until not Match(tkComma);

  Expect(tkColon);

  // Parse body statements until we leave this arm's scope.
  // We're in match state -- each iteration checks: is this a statement,
  // or the start of the next arm / else / end?
  while not (Check(tkEnd) or Check(tkElse) or Check(tkEOF)) do
  begin
    // Skip lone semicolons
    if Match(tkSemicolon) then
      Continue;

    // If the current token is not a valid statement start, this arm is done.
    // The match loop in DoParseMatchStmt will pick it up as a new label.
    if not IsStatementStart(Current().Kind) then
      Break;

    LStmt := DoParseStatement();
    if Assigned(LStmt) then
      Result.Body.Add(LStmt);

    if FErrors.HasErrors() then
      Break;
  end;
end;

function TMyrParser.DoParseReturnStmt(): TMyrReturnNode;
begin
  Result := TMyrReturnNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'return'

  // Optional return value -- return is followed by expression unless
  // we see a statement terminator
  if not (Check(tkSemicolon) or Check(tkEnd) or Check(tkElse) or
          Check(tkFinally) or Check(tkExcept) or Check(tkUntil) or Check(tkEOF)) then
    Result.ValueExpr := DoParseExpression();

  OptionalSemicolon();
end;

function TMyrParser.DoParseGuardStmt(): TMyrGuardNode;
var
  LBody: TObjectList<TMyrASTNode>;
begin
  Result := TMyrGuardNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'guard'

  // Guard body
  LBody := DoParseStatementSeq([tkExcept, tkFinally]);
  Result.GuardBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  if Match(tkExcept) then
  begin
    LBody := DoParseStatementSeq([tkFinally, tkEnd]);
    Result.ExceptBody.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();

    // Optional finally after except
    if Match(tkFinally) then
    begin
      LBody := DoParseStatementSeq([tkEnd]);
      Result.FinallyBody.AddRange(LBody.ToArray());
      LBody.OwnsObjects := False;
      LBody.Free();
    end;
  end
  else if Match(tkFinally) then
  begin
    LBody := DoParseStatementSeq([tkEnd]);
    Result.FinallyBody.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();
  end;

  ExpectBlockEnd('guard', Result.Location);
  OptionalSemicolon();
  Result.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
end;

function TMyrParser.DoParseThrowStmt(): TMyrASTNode;
var
  LThrow: TMyrThrowNode;
  LThrowCode: TMyrThrowCodeNode;
begin
  if Check(tkThrowCode) then
  begin
    LThrowCode := TMyrThrowCodeNode.Create();
    LThrowCode.Location := Current().Location;
    Consume();
    Expect(tkLParen);
    LThrowCode.CodeExpr := DoParseExpression();
    Expect(tkComma);
    LThrowCode.MessageExpr := DoParseExpression();
    Expect(tkRParen);
    OptionalSemicolon();
    Result := LThrowCode;
  end
  else
  begin
    LThrow := TMyrThrowNode.Create();
    LThrow.Location := Current().Location;
    Consume();
    Expect(tkLParen);
    LThrow.MessageExpr := DoParseExpression();
    Expect(tkRParen);
    OptionalSemicolon();
    Result := LThrow;
  end;
end;

function TMyrParser.DoParseNewStmt(): TMyrNewNode;
begin
  Result := TMyrNewNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.ArgExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TMyrParser.DoParseDisposeStmt(): TMyrDisposeNode;
begin
  Result := TMyrDisposeNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.ArgExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TMyrParser.DoParseGetMemStmt(): TMyrGetMemNode;
begin
  Result := TMyrGetMemNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.ArgExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TMyrParser.DoParseFreeMemStmt(): TMyrFreeMemNode;
begin
  Result := TMyrFreeMemNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.ArgExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TMyrParser.DoParseResizeMemStmt(): TMyrResizeMemNode;
begin
  Result := TMyrResizeMemNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.PtrExpr := DoParseExpression();
  Expect(tkComma);
  Result.SizeExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TMyrParser.DoParseSetLengthStmt(): TMyrSetLengthNode;
begin
  Result := TMyrSetLengthNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.TargetExpr := DoParseExpression();
  Expect(tkComma);
  Result.LengthExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TMyrParser.DoParsePrintStmt(): TMyrPrintNode;
begin
  Result := TMyrPrintNode.Create();
  Result.Location := Current().Location;
  Result.IsLn := Check(tkPrintLn);
  Consume();

  Expect(tkLParen);
  if not Check(tkRParen) then
  begin
    Result.Args.Add(DoParseExpression());
    while Match(tkComma) do
      Result.Args.Add(DoParseExpression());
  end;
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TMyrParser.DoParseAssertStmt(): TMyrAssertStmtNode;
var
  LKind: TMyrTokenKind;
begin
  Result := TMyrAssertStmtNode.Create();
  Result.Location := Current().Location;

  LKind := Current().Kind;
  if LKind = tkAssert then Result.AssertKind := akAssert
  else if LKind = tkAssertTrue then Result.AssertKind := akTrue
  else if LKind = tkAssertFalse then Result.AssertKind := akFalse
  else if LKind = tkAssertEq then Result.AssertKind := akEq
  else if LKind = tkAssertEqF then Result.AssertKind := akEqF
  else if LKind = tkAssertNil then Result.AssertKind := akNil
  else if LKind = tkAssertNotNil then Result.AssertKind := akNotNil
  else if LKind = tkAssertFail then Result.AssertKind := akFail;

  Consume();
  Expect(tkLParen);

  // All asserts have at least one argument
  Result.Args.Add(DoParseExpression());

  // asserteq has 2 args, asserteqf has 3
  if Match(tkComma) then
  begin
    Result.Args.Add(DoParseExpression());
    if Match(tkComma) then
      Result.Args.Add(DoParseExpression());
  end;

  Expect(tkRParen);
  OptionalSemicolon();
end;

{ TMyrParser.DoParseCppBlock }
function TMyrParser.DoParseCppBlock(): TMyrCppBlockNode;
var
  LRaw: string;
  LTarget: string;
  LText: string;
  LSplitPos: Integer;
begin
  Result := TMyrCppBlockNode.Create();
  Result.Location := Current().Location;
  Consume(); // consume tkCppStart

  // The raw block token contains "target\ntext" -- first word is header|source
  if Current().Kind <> tkRawBlock then
  begin
    FErrors.Add(Current().Location, esError, MYR_ERR_PAR_001,
      'Expected raw block content after cppstart', []);
    Exit;
  end;

  LRaw := Current().TokenText;
  Consume(); // consume tkRawBlock

  // Split target from text at first whitespace/newline
  LSplitPos := 0;
  while LSplitPos < Length(LRaw) do
  begin
    Inc(LSplitPos);
    if CharInSet(LRaw[LSplitPos], [' ', #9, #10, #13]) then
      Break;
  end;

  if LSplitPos <= Length(LRaw) then
  begin
    LTarget := LRaw.Substring(0, LSplitPos - 1).Trim();
    LText := LRaw.Substring(LSplitPos).Trim();
  end
  else
  begin
    LTarget := LRaw.Trim();
    LText := '';
  end;

  Result.Target := LTarget;
  Result.RawText := LText;

  Expect(tkCppEnd);
end;

{ TMyrParser.DoParseCppStmt }
function TMyrParser.DoParseCppStmt(): TMyrASTNode;
var
  LExpr: TMyrCppExprNode;
begin
  // cpp("...") as a statement -- parse as expression, wrap in call stmt
  LExpr := DoParseCppExpr();
  Result := TMyrCallStmtNode.Create();
  Result.Location := LExpr.Location;
  TMyrCallStmtNode(Result).CallExpr := LExpr;
  OptionalSemicolon();
end;

{ TMyrParser.DoParseCppExpr }
function TMyrParser.DoParseCppExpr(): TMyrCppExprNode;
begin
  Result := TMyrCppExprNode.Create();
  Result.Location := Current().Location;
  Consume(); // consume tkCpp

  Expect(tkLParen);
  Result.ArgExpr := TMyrExprNode(DoParseExpression());
  Expect(tkRParen);
end;

function TMyrParser.DoParseExpression(): TMyrASTNode;
begin
  Result := DoParsePrecedence(1);
end;

function TMyrParser.DoParsePrecedence(const AMinPrec: Integer): TMyrASTNode;
var
  LLeft: TMyrASTNode;
  LBinary: TMyrBinaryExprNode;
  LPrec: Integer;
begin
  LLeft := DoParsePrefix();

  while True do
  begin
    LPrec := GetPrecedence(Current().Kind);
    if (LPrec = 0) or (LPrec < AMinPrec) then
      Break;

    LBinary := TMyrBinaryExprNode.Create();
    LBinary.Location := Current().Location;
    LBinary.Left := LLeft;
    LBinary.Op := TokenToBinaryOp(Current().Kind);
    Consume();
    // Right-associativity not needed for Myrissa ops, so use AMinPrec = LPrec + 1
    LBinary.Right := DoParsePrecedence(LPrec + 1);
    LLeft := LBinary;
  end;

  Result := LLeft;
end;

function TMyrParser.DoParsePrefix(): TMyrASTNode;
var
  LUnary: TMyrUnaryExprNode;
  LLit: TMyrIntLiteralNode;
  LFLit: TMyrFloatLiteralNode;
  LSLit: TMyrStringLiteralNode;
  LWSLit: TMyrWStringLiteralNode;
  LBLit: TMyrBoolLiteralNode;
  LIdent: TMyrIdentifierNode;
begin
  // Unary operators
  if Check(tkNot) then
  begin
    LUnary := TMyrUnaryExprNode.Create();
    LUnary.Location := Current().Location;
    LUnary.Op := uoNot;
    Consume();
    LUnary.Operand := DoParsePrefix();
    Result := LUnary;
    Exit;
  end;

  if Check(tkMinus) then
  begin
    LUnary := TMyrUnaryExprNode.Create();
    LUnary.Location := Current().Location;
    LUnary.Op := uoNegate;
    Consume();
    LUnary.Operand := DoParsePrefix();
    Result := LUnary;
    Exit;
  end;

  if Check(tkPlus) then
  begin
    LUnary := TMyrUnaryExprNode.Create();
    LUnary.Location := Current().Location;
    LUnary.Op := uoPositive;
    Consume();
    LUnary.Operand := DoParsePrefix();
    Result := LUnary;
    Exit;
  end;

  // address of expr
  if Check(tkAddress) then
  begin
    LUnary := TMyrUnaryExprNode.Create();
    LUnary.Location := Current().Location;
    LUnary.Op := uoAddressOf;
    Consume();
    Expect(tkOf);
    LUnary.Operand := DoParsePrefix();
    Result := LUnary;
    Exit;
  end;

  // Literals
  if Check(tkIntLiteral) then
  begin
    LLit := TMyrIntLiteralNode.Create();
    LLit.Location := Current().Location;
    if Current().LiteralValue.IsType<UInt64>() then
      LLit.IntValue := Int64(Current().LiteralValue.AsUInt64())
    else if Current().LiteralValue.IsType<Int64>() then
      LLit.IntValue := Current().LiteralValue.AsInt64()
    else
      LLit.IntValue := StrToInt64Def(Current().TokenText, 0);
    Consume();
    Result := LLit;
    Exit;
  end;

  if Check(tkFloatLiteral) then
  begin
    LFLit := TMyrFloatLiteralNode.Create();
    LFLit.Location := Current().Location;
    if Current().LiteralValue.IsType<Double>() then
      LFLit.FloatValue := Current().LiteralValue.AsType<Double>()
    else
      LFLit.FloatValue := StrToFloatDef(Current().TokenText, 0.0);
    LFLit.HasSuffix := Current().TokenText.EndsWith('f', True) or
                        Current().TokenText.EndsWith('F', True);
    Consume();
    Result := LFLit;
    Exit;
  end;

  if Check(tkStringLiteral) then
  begin
    LSLit := TMyrStringLiteralNode.Create();
    LSLit.Location := Current().Location;
    if Current().LiteralValue.IsType<string>() then
      LSLit.StringValue := Current().LiteralValue.AsString()
    else
      LSLit.StringValue := Current().TokenText;
    Consume();
    Result := LSLit;
    Exit;
  end;

  if Check(tkWStringLiteral) then
  begin
    LWSLit := TMyrWStringLiteralNode.Create();
    LWSLit.Location := Current().Location;
    if Current().LiteralValue.IsType<string>() then
      LWSLit.StringValue := Current().LiteralValue.AsString()
    else
      LWSLit.StringValue := Current().TokenText;
    Consume();
    Result := LWSLit;
    Exit;
  end;

  if Check(tkTrue) or Check(tkFalse) then
  begin
    LBLit := TMyrBoolLiteralNode.Create();
    LBLit.Location := Current().Location;
    LBLit.BoolValue := Check(tkTrue);
    Consume();
    Result := LBLit;
    Exit;
  end;

  if Check(tkNil) then
  begin
    Result := TMyrNilLiteralNode.Create();
    Result.Location := Current().Location;
    Consume();
    Exit;
  end;

  // Parenthesized expression
  if Check(tkLParen) then
  begin
    Consume();
    Result := DoParseExpression();
    Expect(tkRParen);
    // Continue with designator chain (selectors after parens)
    Result := DoParseDesignator(Result);
    Exit;
  end;

  // Set literal [...]
  if Check(tkLBracket) then
  begin
    Result := DoParseSetLiteral();
    Exit;
  end;

  // cpp() inline expression
  if Check(tkCpp) then
  begin
    Result := DoParseCppExpr();
    Exit;
  end;

  // Intrinsics
  if IsIntrinsicToken(Current().Kind) then
  begin
    Result := DoParseIntrinsic(TokenToIntrinsicKind(Current().Kind));
    Exit;
  end;

  // Identifier -- start of designator chain, possibly type cast or record literal
  if Check(tkIdentifier) or Check(tkVarArgs) then
  begin
    LIdent := TMyrIdentifierNode.Create();
    LIdent.Location := Current().Location;
    LIdent.IdentName := Current().TokenText;
    Consume();
    Result := DoParseDesignator(LIdent);
    Exit;
  end;

  // Primitive type as expression (for type casts like int32(x))
  if FLexer.IsDataType(Current().Kind) then
  begin
    Result := DoParseTypeExpr();
    // If followed by (, it's a type cast
    if Check(tkLParen) then
      Result := DoParseDesignator(Result);
    Exit;
  end;

  // Nothing matched
  FErrors.Add(Current().Location, esError, MYR_ERR_PAR_007,
    'Expected expression, got: %s', [Current().TokenText]);
  Result := nil;
end;

function TMyrParser.DoParseDesignator(const ABase: TMyrASTNode): TMyrASTNode;
var
  LResult: TMyrASTNode;
  LDot: TMyrDotAccessNode;
  LIndex: TMyrIndexAccessNode;
  LDeref: TMyrDerefNode;
  LCall: TMyrCallExprNode;
  LCast: TMyrTypeCastExprNode;
  LRecLit: TMyrRecordLiteralNode;
  LFieldInit: TMyrFieldInitNode;
begin
  LResult := ABase;

  while True do
  begin
    // .member
    if Check(tkDot) then
    begin
      Consume();
      LDot := TMyrDotAccessNode.Create();
      LDot.Location := Current().Location;
      LDot.BaseExpr := LResult;
      if Current().Kind <> tkIdentifier then
      begin
        FErrors.Add(Current().Location, esError, MYR_ERR_PAR_008,
          'Expected member name after "."');
        LDot.BaseExpr := nil;  // detach before free to prevent double-free of LResult
        LDot.Free();
        Break;
      end;
      LDot.MemberName := Current().TokenText;
      Consume();
      LResult := LDot;
    end
    // [index]
    else if Check(tkLBracket) then
    begin
      Consume();
      LIndex := TMyrIndexAccessNode.Create();
      LIndex.Location := LResult.Location;
      LIndex.BaseExpr := LResult;
      LIndex.IndexExpr := DoParseExpression();
      Expect(tkRBracket);
      LResult := LIndex;
    end
    // ^ dereference
    else if Check(tkCaret) then
    begin
      LDeref := TMyrDerefNode.Create();
      LDeref.Location := Current().Location;
      LDeref.BaseExpr := LResult;
      Consume();
      LResult := LDeref;
    end
    // (args) -- call, type cast, or record literal
    else if Check(tkLParen) then
    begin
      // Check for record literal: ident(fieldname: expr, ...)
      // Record literal is when base is an identifier or module-qualified dot access
      // and first arg is ident followed by colon
      if ((LResult is TMyrIdentifierNode) or
          ((LResult is TMyrDotAccessNode) and (TMyrDotAccessNode(LResult).BaseExpr is TMyrIdentifierNode))) and
         (PeekAt(1).Kind = tkIdentifier) and (PeekAt(2).Kind = tkColon) then
      begin
        LRecLit := TMyrRecordLiteralNode.Create();
        LRecLit.Location := LResult.Location;
        if LResult is TMyrDotAccessNode then
        begin
          // Module-qualified: probeunit.TPoint(x: 10, y: 20)
          LRecLit.ModuleName := TMyrIdentifierNode(TMyrDotAccessNode(LResult).BaseExpr).IdentName;
          LRecLit.TypeName := TMyrDotAccessNode(LResult).MemberName;
        end
        else
          LRecLit.TypeName := TMyrIdentifierNode(LResult).IdentName;
        LResult.Free();
        Consume();  // consume (

        repeat
          LFieldInit := TMyrFieldInitNode.Create();
          LFieldInit.Location := Current().Location;
          LFieldInit.FieldName := Current().TokenText;
          Consume();  // consume field name
          Expect(tkColon);
          LFieldInit.ValueExpr := DoParseExpression();
          LRecLit.FieldInits.Add(LFieldInit);
        until not Match(tkComma);

        Expect(tkRParen);
        LResult := LRecLit;
      end
      // Check for type cast: primitive_type(expr)
      else if LResult is TMyrTypeRefNode then
      begin
        LCast := TMyrTypeCastExprNode.Create();
        LCast.Location := LResult.Location;
        LCast.TargetType := LResult;
        Consume();  // consume (
        LCast.Expr := DoParseExpression();
        Expect(tkRParen);
        LCast.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
        LResult := LCast;
      end
      // Regular function call
      else
      begin
        LCall := TMyrCallExprNode.Create();
        LCall.Location := LResult.Location;
        LCall.Callee := LResult;
        Consume();  // consume (
        if not Check(tkRParen) then
        begin
          LCall.Args.Add(DoParseExpression());
          while Match(tkComma) do
            LCall.Args.Add(DoParseExpression());
        end;
        Expect(tkRParen);
        LCall.SetLocationEnd(FLastConsumedLoc.EndLine, FLastConsumedLoc.EndColumn);
        LResult := LCall;
      end;
    end
    else
      Break;
  end;

  Result := LResult;
end;

function TMyrParser.DoParseSetLiteral(): TMyrSetLiteralExprNode;
var
  LElement: TMyrSetElementNode;
begin
  Result := TMyrSetLiteralExprNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume [

  if not Check(tkRBracket) then
  begin
    repeat
      LElement := TMyrSetElementNode.Create();
      LElement.Location := Current().Location;
      LElement.LowExpr := DoParseExpression();

      // Range: expr..expr
      if Match(tkDotDot) then
        LElement.HighExpr := DoParseExpression();

      Result.Elements.Add(LElement);
    until not Match(tkComma);
  end;

  Expect(tkRBracket);
end;

function TMyrParser.DoParseIntrinsic(const AKind: TMyrIntrinsicKind): TMyrIntrinsicExprNode;
begin
  Result := TMyrIntrinsicExprNode.Create();
  Result.Location := Current().Location;
  Result.IntrinsicKind := AKind;
  Consume();  // consume intrinsic keyword

  Expect(tkLParen);

  // paramcount() and exccode() and excmsg() have no args
  if not Check(tkRParen) then
  begin
    Result.Args.Add(DoParseExpression());
    // size() can take a type expression too, but it's parsed as expression
  end;

  Expect(tkRParen);
end;


{ TMyrScope }
constructor TMyrScope.Create();
begin
  inherited;

  FSymbols := TDictionary<string, TMyrASTNode>.Create();
  FOwnedGroups := TObjectList<TMyrOverloadGroupNode>.Create(True);
end;

destructor TMyrScope.Destroy();
begin
  FOwnedGroups.Free();
  FSymbols.Free();

  inherited;
end;

procedure TMyrScope.Declare(const AName: string; const ANode: TMyrASTNode;
  const ALocation: TSourceRange);
var
  LExisting: TMyrASTNode;
  LGroup: TMyrOverloadGroupNode;
  LExistingRoutine: TMyrRoutineDeclNode;
  LNewRoutine: TMyrRoutineDeclNode;
begin
  if FSymbols.TryGetValue(AName, LExisting) then
  begin
    // Overload: existing is a routine, new is a routine
    if (LExisting is TMyrRoutineDeclNode) and (ANode is TMyrRoutineDeclNode) then
    begin
      LExistingRoutine := TMyrRoutineDeclNode(LExisting);
      LNewRoutine := TMyrRoutineDeclNode(ANode);

      // Promote to cpplink with warning if needed
      if LExistingRoutine.Linkage in [lkDefault, lkCLink] then
      begin
        FErrors.Add(LExistingRoutine.Location, esWarning, MYR_ERR_SEM_002,
          'Overloaded routine "%s" defaulting to cpplink (clink does not support overloading)',
          [AName]);
        LExistingRoutine.Linkage := lkCppLink;
      end;
      if LNewRoutine.Linkage in [lkDefault, lkCLink] then
      begin
        FErrors.Add(ALocation, esWarning, MYR_ERR_SEM_002,
          'Overloaded routine "%s" defaulting to cpplink (clink does not support overloading)',
          [AName]);
        LNewRoutine.Linkage := lkCppLink;
      end;

      // Create overload group with both routines
      LGroup := TMyrOverloadGroupNode.Create();
      LGroup.DeclName := AName;
      LGroup.IsPublic := LExistingRoutine.IsPublic or LNewRoutine.IsPublic;
      LGroup.Overloads.Add(LExistingRoutine);
      LGroup.Overloads.Add(LNewRoutine);
      FOwnedGroups.Add(LGroup);
      FSymbols[AName] := LGroup;
      Exit;
    end

    // Overload: existing is already a group, new is a routine
    else if (LExisting is TMyrOverloadGroupNode) and (ANode is TMyrRoutineDeclNode) then
    begin
      LGroup := TMyrOverloadGroupNode(LExisting);
      LNewRoutine := TMyrRoutineDeclNode(ANode);

      if LNewRoutine.Linkage in [lkDefault, lkCLink] then
      begin
        FErrors.Add(ALocation, esWarning, MYR_ERR_SEM_002,
          'Overloaded routine "%s" defaulting to cpplink (clink does not support overloading)',
          [AName]);
        LNewRoutine.Linkage := lkCppLink;
      end;

      LGroup.Overloads.Add(LNewRoutine);
      if LNewRoutine.IsPublic then
        LGroup.IsPublic := True;
      Exit;
    end

    // Not a routine overload -- genuine duplicate
    else
    begin
      FErrors.Add(ALocation, esError, MYR_ERR_SEM_002,
        'Duplicate declaration: %s', [AName]);
      Exit;
    end;
  end;
  FSymbols.Add(AName, ANode);
end;

function TMyrScope.Lookup(const AName: string): TMyrASTNode;
var
  LScope: TMyrScope;
begin
  Result := nil;
  LScope := Self;
  while LScope <> nil do
  begin
    if LScope.FSymbols.TryGetValue(AName, Result) then
      Exit;
    LScope := LScope.FParent;
  end;
end;

function TMyrScope.LookupLocal(const AName: string): TMyrASTNode;
begin
  if not FSymbols.TryGetValue(AName, Result) then
    Result := nil;
end;

{ TMyrSemantics }
constructor TMyrSemantics.Create();
begin
  inherited;

  FModuleScopes := TObjectDictionary<string, TMyrScope>.Create([doOwnsValues]);
  FPrimitiveTypes := TObjectDictionary<TMyrTokenKind, TMyrTypeDeclNode>.Create([doOwnsValues]);
  FLoopDepth := 0;
  InitPrimitiveTypes();

  // Synthetic pointer-to-char and pointer-to-wchar types for cstr/wstr intrinsics
  FPointerToChar := TMyrPointerTypeNode.Create();
  FPointerToChar.TargetType := GetPrimitiveType(tkChar);
  FPointerToChar.IsConstTarget := True;

  FPointerToWChar := TMyrPointerTypeNode.Create();
  FPointerToWChar.TargetType := GetPrimitiveType(tkWChar);
  FPointerToWChar.IsConstTarget := True;
end;

destructor TMyrSemantics.Destroy();
begin
  // Nil out borrowed references before freeing
  FPointerToChar.TargetType := nil;
  FPointerToChar.Free();
  FPointerToWChar.TargetType := nil;
  FPointerToWChar.Free();

  FPrimitiveTypes.Free();
  FModuleScopes.Free();

  inherited;
end;

procedure TMyrSemantics.InitPrimitiveTypes();

  procedure LRegister(const AKind: TMyrTokenKind; const AName: string;
    const ACppTypeName: string; const AByteSize: Integer);
  var
    LNode: TMyrTypeDeclNode;
  begin
    LNode := TMyrTypeDeclNode.Create();
    LNode.DeclName := AName;
    LNode.PrimitiveKind := AKind;
    LNode.CppTypeName := ACppTypeName;
    LNode.ByteSize := AByteSize;
    FPrimitiveTypes.Add(AKind, LNode);
  end;

begin
  LRegister(tkInt8, 'int8', 'int8_t', 1);
  LRegister(tkInt16, 'int16', 'int16_t', 2);
  LRegister(tkInt32, 'int32', 'int32_t', 4);
  LRegister(tkInt64, 'int64', 'int64_t', 8);
  LRegister(tkUInt8, 'uint8', 'uint8_t', 1);
  LRegister(tkUInt16, 'uint16', 'uint16_t', 2);
  LRegister(tkUInt32, 'uint32', 'uint32_t', 4);
  LRegister(tkUInt64, 'uint64', 'uint64_t', 8);
  LRegister(tkFloat32, 'float32', 'float', 4);
  LRegister(tkFloat64, 'float64', 'double', 8);
  LRegister(tkBoolean, 'boolean', 'bool', 1);
  LRegister(tkChar, 'char', 'char', 1);
  LRegister(tkWChar, 'wchar', 'char16_t', 2);
  LRegister(tkString, 'string', 'std::string', 8);
  LRegister(tkWString, 'wstring', 'std::wstring', 8);
  LRegister(tkPointer, 'pointer', 'void*', 8);
end;

function TMyrSemantics.GetPrimitiveType(const AKind: TMyrTokenKind): TMyrTypeDeclNode;
begin
  if not FPrimitiveTypes.TryGetValue(AKind, Result) then
    Result := nil;
end;

function TMyrSemantics.PushScope(const AKind: TMyrScopeKind): TMyrScope;
begin
  Result := TMyrScope.Create();
  Result.SetErrors(FErrors);
  Result.ScopeKind := AKind;
  Result.Parent := FCurrentScope;
  FCurrentScope := Result;
end;

procedure TMyrSemantics.PopScope();
var
  LOld: TMyrScope;
begin
  LOld := FCurrentScope;
  FCurrentScope := FCurrentScope.Parent;
  // Module scopes are owned by FModuleScopes, don't free them here
  if LOld.ScopeKind <> skModule then
    LOld.Free();
end;

procedure TMyrSemantics.Analyze(const AMasterAST: TMyrMasterAST);
var
  I: Integer;
  LAnalyzed: TDictionary<string, Boolean>;
  LProgress: Boolean;
  LModule: TMyrModuleNode;
  J: Integer;
  LReady: Boolean;
begin
  FMasterAST := AMasterAST;

  // Topological sort: process each module only after all its imports are analyzed.
  // This handles any import ordering, diamond dependencies, and multi-level chains.
  LAnalyzed := TDictionary<string, Boolean>.Create();
  try
    repeat
      LProgress := False;
      for I := 0 to FMasterAST.ModuleCount() - 1 do
      begin
        LModule := FMasterAST.GetModuleAt(I);
        if LAnalyzed.ContainsKey(LModule.ModuleName) then
          Continue;

        // Check if all imports have been analyzed
        LReady := True;
        for J := 0 to LModule.Imports.Count - 1 do
        begin
          if not LAnalyzed.ContainsKey(LModule.Imports[J].ModuleName) then
          begin
            LReady := False;
            Break;
          end;
        end;

        if LReady then
        begin
          DoAnalyzeModule(LModule);
          LAnalyzed.Add(LModule.ModuleName, True);
          LProgress := True;
        end;
      end;
    until (not LProgress) or (LAnalyzed.Count = FMasterAST.ModuleCount());
  finally
    LAnalyzed.Free();
  end;
end;

procedure TMyrSemantics.DoAnalyzeModule(const AModule: TMyrModuleNode);
var
  LScope: TMyrScope;
  LDir: TMyrDirectiveNode;
  LTarget: TMyrTargetKind;
  I: Integer;
  J: Integer;
begin
  FCurrentModule := AModule;

  // Validate module kind
  if not (AModule.ModuleKind in [mkExe, mkDll, mkLib, mkUnit]) then
  begin
    FErrors.Add(AModule.Location, esError, MYR_ERR_SEM_021,
      RSSemInvalidModuleKind, []);
    Exit;
  end;

  // Validate begin...end body rules
  if AModule.ModuleKind = mkExe then
  begin
    // exe must have an entry point
    if not AModule.HasMainBody then
      FErrors.Add(AModule.Location, esError, MYR_ERR_SEM_022,
        RSSemExeMissingMain, []);
  end
  else
  begin
    // dll, lib, unit must NOT have a begin...end block
    if AModule.HasMainBody then
    begin
      if AModule.ModuleKind = mkDll then
        FErrors.Add(AModule.Location, esError, MYR_ERR_SEM_022,
          RSSemMainBodyForbidden, ['dll'])
      else if AModule.ModuleKind = mkLib then
        FErrors.Add(AModule.Location, esError, MYR_ERR_SEM_022,
          RSSemMainBodyForbidden, ['lib'])
      else
        FErrors.Add(AModule.Location, esError, MYR_ERR_SEM_022,
          RSSemMainBodyForbidden, ['unit']);
    end;
  end;

  // Resolve directive values for all modules
  for I := 0 to AModule.Directives.Count - 1 do
  begin
    LDir := AModule.Directives[I];
    LDir.ResolvedValue := LDir.DirectiveValue.DeQuotedString('"');
    LDir.ResolvedValue2 := LDir.DirectiveValue2.DeQuotedString('"');
  end;

  // Target directive validation (main module only)
  if AModule = FMasterAST.Modules[0] then
  begin
    for I := 0 to AModule.Directives.Count - 1 do
    begin
      LDir := AModule.Directives[I];
      if LDir.DirectiveName.ToLower() = 'target' then
      begin
        if MyrTryParseTarget(LDir.ResolvedValue, LTarget) then
        begin
          AModule.ResolvedTarget := LTarget;
          case LTarget of
            tgWin64:   AModule.ResolvedTargetTriple := 'win64';
            tgLinux64: AModule.ResolvedTargetTriple := 'linux64';
          end;
        end
        else
          FErrors.Add(LDir.Location, esError, MYR_ERR_SEM_023,
            RSSemInvalidTarget, [LDir.ResolvedValue]);
      end;
    end;
  end;

  // Create module scope
  LScope := PushScope(skModule);
  FModuleScopes.Add(AModule.ModuleName, LScope);

  // Resolve import nodes to their module nodes in the master AST
  for I := 0 to AModule.Imports.Count - 1 do
  begin
    AModule.Imports[I].ResolvedModule := FMasterAST.GetModule(
      AModule.Imports[I].ModuleName);
    if AModule.Imports[I].ResolvedModule = nil then
      FErrors.Add(AModule.Imports[I].Location, esError, MYR_ERR_SEM_001,
        'Imported module not found: %s', [AModule.Imports[I].ModuleName])
    else
      // Register import name in scope for qualified access (myutils.symbol)
      LScope.Declare(AModule.Imports[I].ModuleName, AModule.Imports[I],
        AModule.Imports[I].Location);
  end;

  if FErrors.HasErrors() then
    Exit;

  // Walk declarations in order (declare-before-use)
  for I := 0 to AModule.Declarations.Count - 1 do
  begin
    DoAnalyzeDeclaration(AModule.Declarations[I]);
    if FErrors.HasErrors() then
      Exit;
  end;

  // Validate all forward declarations resolved
  DoValidateForwards();

  if FErrors.HasErrors() then
    Exit;

  // Analyze bodies
  DoAnalyzeStatementSeq(AModule.InitBody);
  DoAnalyzeStatementSeq(AModule.FinalBody);
  DoAnalyzeStatementSeq(AModule.MainBody);

  // Analyze test blocks
  for I := 0 to AModule.TestBlocks.Count - 1 do
  begin
    // Enrich with sanitized C++ function name
    AModule.TestBlocks[I].CppTestName := MyrSanitizeIdentifier(AModule.TestBlocks[I].TestName);

    PushScope(skTest);
    try
      // Register test block local vars (same path as routine locals)
      for J := 0 to AModule.TestBlocks[I].Locals.Count - 1 do
        DoAnalyzeVarDecl(AModule.TestBlocks[I].Locals[J]);

      DoAnalyzeStatementSeq(AModule.TestBlocks[I].Body);
    finally
      PopScope();
    end;
  end;

  // Pop module scope (stays in FModuleScopes)
  FCurrentScope := FCurrentScope.Parent;
end;

procedure TMyrSemantics.DoAnalyzeDeclaration(const ANode: TMyrASTNode);
begin
  if ANode is TMyrConstDeclNode then
    DoAnalyzeConstDecl(TMyrConstDeclNode(ANode))
  else if ANode is TMyrTypeDeclNode then
    DoAnalyzeTypeDecl(TMyrTypeDeclNode(ANode))
  else if ANode is TMyrVarDeclNode then
    DoAnalyzeVarDecl(TMyrVarDeclNode(ANode))
  else if ANode is TMyrRoutineDeclNode then
    DoAnalyzeRoutineDecl(TMyrRoutineDeclNode(ANode))
  else if ANode is TMyrForwardTypeDeclNode then
    DoAnalyzeForwardTypeDecl(TMyrForwardTypeDeclNode(ANode))
  else if ANode is TMyrForwardRoutineDeclNode then
    DoAnalyzeForwardRoutineDecl(TMyrForwardRoutineDeclNode(ANode))
  else if ANode is TMyrDirectiveNode then
    // Directives don't need semantic analysis
  else if ANode is TMyrCppBlockNode then
    DoAnalyzeCppBlock(TMyrCppBlockNode(ANode))
  else
    FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_013,
      'Unexpected declaration node type');
end;

procedure TMyrSemantics.DoAnalyzeConstDecl(const ANode: TMyrConstDeclNode);
begin
  // Register in current scope
  FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Analyze the value expression
  if ANode.ValueExpr <> nil then
  begin
    DoAnalyzeExpr(TMyrExprNode(ANode.ValueExpr));
    // Type annotation present -- resolve and check compatibility
    if ANode.TypeExpr <> nil then
    begin
      ResolveTypeExpr(ANode.TypeExpr);
      if not IsAssignableFrom(GetResolvedTypeDecl(ANode.TypeExpr), TMyrExprNode(ANode.ValueExpr).ResolvedType) then
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
          'Const value type does not match declared type for: %s', [ANode.DeclName]);
    end;
  end;
end;

procedure TMyrSemantics.DoAnalyzeTypeDecl(const ANode: TMyrTypeDeclNode);
var
  LForward: TMyrASTNode;
begin
  // Check if this resolves a forward declaration
  LForward := FCurrentScope.LookupLocal(ANode.DeclName);
  if LForward <> nil then
  begin
    if LForward is TMyrForwardTypeDeclNode then
    begin
      // Link forward to full declaration
      TMyrForwardTypeDeclNode(LForward).ResolvedDecl := ANode;
      // Update scope entry to point to full declaration
      FCurrentScope.FSymbols[ANode.DeclName] := ANode;
    end
    else
    begin
      FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_002,
        'Duplicate declaration: %s', [ANode.DeclName]);
      Exit;
    end;
  end
  else
    FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Analyze the type definition
  if ANode.TypeDef <> nil then
    DoAnalyzeTypeDef(ANode.TypeDef);
end;

{ TMyrSemantics.DoResolveExternalString }
function TMyrSemantics.DoResolveExternalString(const ARawText: string;
  const ALocation: TSourceRange): string;
var
  LNode: TMyrASTNode;
  LConst: TMyrConstDeclNode;
begin
  // String literal: strip quotes
  if ARawText.StartsWith('"') then
    Result := ARawText.DeQuotedString('"')
  else
  begin
    // Identifier: resolve to const string value
    LNode := FCurrentScope.Lookup(ARawText);
    if LNode = nil then
    begin
      FErrors.Add(ALocation, esError, MYR_ERR_SEM_001,
        'Undeclared identifier in external clause: %s', [ARawText]);
      Result := ARawText;
      Exit;
    end;
    if not (LNode is TMyrConstDeclNode) then
    begin
      FErrors.Add(ALocation, esError, MYR_ERR_SEM_020,
        'External clause identifier must be a const: %s', [ARawText]);
      Result := ARawText;
      Exit;
    end;
    LConst := TMyrConstDeclNode(LNode);
    if not (LConst.ValueExpr is TMyrStringLiteralNode) then
    begin
      FErrors.Add(ALocation, esError, MYR_ERR_SEM_020,
        'External clause const must be a string: %s', [ARawText]);
      Result := ARawText;
      Exit;
    end;
    Result := TMyrStringLiteralNode(LConst.ValueExpr).StringValue;
  end;
end;

procedure TMyrSemantics.DoAnalyzeVarDecl(const ANode: TMyrVarDeclNode);
begin
  FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Resolve the type expression
  if ANode.TypeExpr <> nil then
    ResolveTypeExpr(ANode.TypeExpr);

  // External vars must not have initializers
  if ANode.IsExternal and (ANode.InitExpr <> nil) then
  begin
    FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_020,
      'External variable cannot have an initializer: %s', [ANode.DeclName]);
    Exit;
  end;

  // Enrich external lib name (resolve string literal or const identifier)
  if ANode.IsExternal and (ANode.ExternalLib <> '') then
    ANode.ResolvedExternalLib := DoResolveExternalString(ANode.ExternalLib, ANode.Location);

  // Enrich external symbol name (always a string literal)
  if ANode.IsExternal and (ANode.ExternalName <> '') then
    ANode.ResolvedExternalName := ANode.ExternalName.DeQuotedString('"');

  // Analyze initializer if present
  if ANode.InitExpr <> nil then
  begin
    DoAnalyzeExpr(TMyrExprNode(ANode.InitExpr));

    // Implicit string-to-char coercion for single-character literals
    if (GetResolvedTypeDecl(ANode.TypeExpr) = GetPrimitiveType(tkChar)) and
       (ANode.InitExpr is TMyrStringLiteralNode) and
       (Length(TMyrStringLiteralNode(ANode.InitExpr).StringValue) = 1) then
      TMyrExprNode(ANode.InitExpr).ResolvedType := GetPrimitiveType(tkChar)
    else if (GetResolvedTypeDecl(ANode.TypeExpr) = GetPrimitiveType(tkWChar)) and
            (ANode.InitExpr is TMyrWStringLiteralNode) and
            (Length(TMyrWStringLiteralNode(ANode.InitExpr).StringValue) = 1) then
      TMyrExprNode(ANode.InitExpr).ResolvedType := GetPrimitiveType(tkWChar);

    if (ANode.TypeExpr <> nil) and (TMyrExprNode(ANode.InitExpr).ResolvedType <> nil) then
    begin
      if not IsAssignableFrom(GetResolvedTypeDecl(ANode.TypeExpr), TMyrExprNode(ANode.InitExpr).ResolvedType) then
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
          'Initializer type does not match declared type for: %s', [ANode.DeclName]);
    end;
  end;
end;

procedure TMyrSemantics.DoAnalyzeRoutineDecl(const ANode: TMyrRoutineDeclNode);
var
  LForward: TMyrASTNode;
  LScope: TMyrScope;
  I: Integer;
  LPrevRoutine: TMyrRoutineDeclNode;
begin
  // Check if this resolves a forward declaration
  LForward := FCurrentScope.LookupLocal(ANode.DeclName);
  if LForward <> nil then
  begin
    if LForward is TMyrForwardRoutineDeclNode then
    begin
      // TODO: Verify signatures match
      TMyrForwardRoutineDeclNode(LForward).ResolvedDecl := ANode;
      FCurrentScope.FSymbols[ANode.DeclName] := ANode;
    end
    else if (LForward is TMyrRoutineDeclNode) or (LForward is TMyrOverloadGroupNode) then
    begin
      // Overload -- delegate to Declare which handles group creation
      FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);
    end
    else
    begin
      FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_002,
        'Duplicate declaration: %s', [ANode.DeclName]);
      Exit;
    end;
  end
  else
    FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Resolve return type
  if ANode.ReturnType <> nil then
    ResolveTypeExpr(ANode.ReturnType);

  // Resolve parameter types
  for I := 0 to ANode.Params.Count - 1 do
  begin
    if ANode.Params[I].TypeExpr <> nil then
      ResolveTypeExpr(ANode.Params[I].TypeExpr);
  end;

  // External routines have no body to analyze
  if ANode.IsExternal then
  begin
    // Enrich external lib name (resolve string literal or const identifier)
    if ANode.ExternalLib <> '' then
      ANode.ResolvedExternalLib := DoResolveExternalString(ANode.ExternalLib, ANode.Location);
    // Enrich external symbol name (always a string literal)
    if ANode.ExternalName <> '' then
      ANode.ResolvedExternalName := ANode.ExternalName.DeQuotedString('"');
    Exit;
  end;

  // Push routine scope
  LScope := PushScope(skRoutine);
  LPrevRoutine := FCurrentRoutine;
  FCurrentRoutine := ANode;
  try
    // Register parameters in routine scope
    for I := 0 to ANode.Params.Count - 1 do
      LScope.Declare(ANode.Params[I].ParamName, ANode.Params[I],
        ANode.Params[I].Location);

    // Register local types
    for I := 0 to ANode.LocalTypes.Count - 1 do
      DoAnalyzeTypeDecl(ANode.LocalTypes[I]);

    // Register local consts
    for I := 0 to ANode.LocalConsts.Count - 1 do
      DoAnalyzeConstDecl(ANode.LocalConsts[I]);

    // Register local vars
    for I := 0 to ANode.LocalVars.Count - 1 do
      DoAnalyzeVarDecl(ANode.LocalVars[I]);

    // Analyze body
    DoAnalyzeStatementSeq(ANode.Body);

    // Check return paths for functions
    if ANode.ReturnType <> nil then
    begin
      if not DoCheckReturnPaths(ANode.Body) then
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_007,
          'Not all code paths return a value in function: %s', [ANode.DeclName]);
    end;
  finally
    FCurrentRoutine := LPrevRoutine;
    PopScope();
  end;
end;

procedure TMyrSemantics.DoAnalyzeForwardTypeDecl(const ANode: TMyrForwardTypeDeclNode);
begin
  FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);
end;

procedure TMyrSemantics.DoAnalyzeForwardRoutineDecl(const ANode: TMyrForwardRoutineDeclNode);
var
  I: Integer;
begin
  FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Resolve parameter types
  for I := 0 to ANode.Params.Count - 1 do
  begin
    if ANode.Params[I].TypeExpr <> nil then
      ResolveTypeExpr(ANode.Params[I].TypeExpr);
  end;

  // Resolve return type
  if ANode.ReturnType <> nil then
    ResolveTypeExpr(ANode.ReturnType);
end;

procedure TMyrSemantics.DoValidateForwards();
var
  LPair: TPair<string, TMyrASTNode>;
begin
  for LPair in FCurrentScope.FSymbols do
  begin
    if (LPair.Value is TMyrForwardTypeDeclNode) and
       (TMyrForwardTypeDeclNode(LPair.Value).ResolvedDecl = nil) then
      FErrors.Add(LPair.Value.Location, esError, MYR_ERR_SEM_010,
        'Forward type never defined: %s', [LPair.Key]);

    if (LPair.Value is TMyrForwardRoutineDeclNode) and
       (TMyrForwardRoutineDeclNode(LPair.Value).ResolvedDecl = nil) then
      FErrors.Add(LPair.Value.Location, esError, MYR_ERR_SEM_010,
        'Forward routine never defined: %s', [LPair.Key]);
  end;
end;

// Type definition analysis
procedure TMyrSemantics.DoAnalyzeTypeDef(const ANode: TMyrASTNode);
begin
  if ANode is TMyrRecordTypeNode then
    DoAnalyzeRecordType(TMyrRecordTypeNode(ANode))
  else if ANode is TMyrOverlayTypeNode then
    DoAnalyzeOverlayType(TMyrOverlayTypeNode(ANode))
  else if ANode is TMyrArrayTypeNode then
    DoAnalyzeArrayType(TMyrArrayTypeNode(ANode))
  else if ANode is TMyrPointerTypeNode then
    DoAnalyzePointerType(TMyrPointerTypeNode(ANode))
  else if ANode is TMyrSetTypeNode then
    DoAnalyzeSetType(TMyrSetTypeNode(ANode))
  else if ANode is TMyrChoicesTypeNode then
    DoAnalyzeChoicesType(TMyrChoicesTypeNode(ANode))
  else if ANode is TMyrRoutineTypeNode then
    DoAnalyzeRoutineType(TMyrRoutineTypeNode(ANode))
  else if ANode is TMyrAnonOverlayNode then
    DoAnalyzeAnonOverlay(TMyrAnonOverlayNode(ANode))
  else if ANode is TMyrAnonRecordNode then
    DoAnalyzeAnonRecord(TMyrAnonRecordNode(ANode))
  else if ANode is TMyrTypeRefNode then
    ResolveTypeExpr(ANode);
end;

procedure TMyrSemantics.DoAnalyzeRecordType(const ANode: TMyrRecordTypeNode);
var
  I: Integer;
  LField: TMyrFieldDeclNode;
  LNames: TDictionary<string, Boolean>;
begin
  // Resolve base type if present
  if ANode.BaseType <> nil then
    ResolveTypeExpr(ANode.BaseType);

  // Check for duplicate field names and resolve field types
  LNames := TDictionary<string, Boolean>.Create();
  try
    for I := 0 to ANode.Fields.Count - 1 do
    begin
      if ANode.Fields[I] is TMyrFieldDeclNode then
      begin
        LField := TMyrFieldDeclNode(ANode.Fields[I]);
        if LNames.ContainsKey(LField.FieldName) then
          FErrors.Add(LField.Location, esError, MYR_ERR_SEM_018,
            'Duplicate field name: %s', [LField.FieldName])
        else
          LNames.Add(LField.FieldName, True);

        if LField.TypeExpr <> nil then
          ResolveTypeExpr(LField.TypeExpr);
      end
      else if ANode.Fields[I] is TMyrAnonOverlayNode then
        DoAnalyzeTypeDef(ANode.Fields[I]);
    end;
  finally
    LNames.Free();
  end;
end;

procedure TMyrSemantics.DoAnalyzeOverlayType(const ANode: TMyrOverlayTypeNode);
var
  I: Integer;
  LField: TMyrFieldDeclNode;
  LNames: TDictionary<string, Boolean>;
begin
  LNames := TDictionary<string, Boolean>.Create();
  try
    for I := 0 to ANode.Fields.Count - 1 do
    begin
      if ANode.Fields[I] is TMyrFieldDeclNode then
      begin
        LField := TMyrFieldDeclNode(ANode.Fields[I]);
        if LNames.ContainsKey(LField.FieldName) then
          FErrors.Add(LField.Location, esError, MYR_ERR_SEM_018,
            'Duplicate field name: %s', [LField.FieldName])
        else
          LNames.Add(LField.FieldName, True);

        if LField.TypeExpr <> nil then
          ResolveTypeExpr(LField.TypeExpr);
      end;
    end;
  finally
    LNames.Free();
  end;
end;

{ TMyrSemantics - DoAnalyzeAnonOverlay }
procedure TMyrSemantics.DoAnalyzeAnonOverlay(const ANode: TMyrAnonOverlayNode);
var
  I: Integer;
  LField: TMyrFieldDeclNode;
begin
  for I := 0 to ANode.Fields.Count - 1 do
  begin
    if ANode.Fields[I] is TMyrFieldDeclNode then
    begin
      LField := TMyrFieldDeclNode(ANode.Fields[I]);
      if LField.TypeExpr <> nil then
        ResolveTypeExpr(LField.TypeExpr);
    end
    else
      DoAnalyzeTypeDef(ANode.Fields[I]);
  end;
end;

{ TMyrSemantics - DoAnalyzeAnonRecord }
procedure TMyrSemantics.DoAnalyzeAnonRecord(const ANode: TMyrAnonRecordNode);
var
  I: Integer;
  LField: TMyrFieldDeclNode;
begin
  for I := 0 to ANode.Fields.Count - 1 do
  begin
    if ANode.Fields[I] is TMyrFieldDeclNode then
    begin
      LField := TMyrFieldDeclNode(ANode.Fields[I]);
      if LField.TypeExpr <> nil then
        ResolveTypeExpr(LField.TypeExpr);
    end
    else
      DoAnalyzeTypeDef(ANode.Fields[I]);
  end;
end;

procedure TMyrSemantics.DoAnalyzeArrayType(const ANode: TMyrArrayTypeNode);
begin
  if ANode.ElementType <> nil then
    ResolveTypeExpr(ANode.ElementType);
end;

procedure TMyrSemantics.DoAnalyzePointerType(const ANode: TMyrPointerTypeNode);
begin
  // Pointer target can reference a forward-declared type
  if ANode.TargetType <> nil then
    ResolveTypeExpr(ANode.TargetType);
end;

procedure TMyrSemantics.DoAnalyzeSetType(const ANode: TMyrSetTypeNode);
begin
  if ANode.ElementType <> nil then
    ResolveTypeExpr(ANode.ElementType);
end;

procedure TMyrSemantics.DoAnalyzeChoicesType(const ANode: TMyrChoicesTypeNode);
var
  I: Integer;
  LVal: TMyrChoicesValueNode;
begin
  for I := 0 to ANode.Members.Count - 1 do
  begin
    LVal := TMyrChoicesValueNode(ANode.Members[I]);
    // Analyze explicit value expression if present
    if LVal.ValueExpr <> nil then
      DoAnalyzeExpr(TMyrExprNode(LVal.ValueExpr));
  end;
end;

procedure TMyrSemantics.DoAnalyzeRoutineType(const ANode: TMyrRoutineTypeNode);
var
  I: Integer;
begin
  for I := 0 to ANode.Params.Count - 1 do
  begin
    if ANode.Params[I].TypeExpr <> nil then
      ResolveTypeExpr(ANode.Params[I].TypeExpr);
  end;

  if ANode.ReturnType <> nil then
    ResolveTypeExpr(ANode.ReturnType);
end;

// Statement analysis
procedure TMyrSemantics.DoAnalyzeStatementSeq(const AList: TObjectList<TMyrASTNode>);
var
  I: Integer;
begin
  if AList = nil then
    Exit;
  for I := 0 to AList.Count - 1 do
  begin
    DoAnalyzeStatement(AList[I]);
    if FErrors.HasErrors() then
      Exit;
  end;
end;

procedure TMyrSemantics.DoAnalyzeStatement(const ANode: TMyrASTNode);
begin
  if ANode is TMyrAssignNode then
    DoAnalyzeAssign(TMyrAssignNode(ANode))
  else if ANode is TMyrCallStmtNode then
    DoAnalyzeCallStmt(TMyrCallStmtNode(ANode))
  else if ANode is TMyrIfNode then
    DoAnalyzeIf(TMyrIfNode(ANode))
  else if ANode is TMyrWhileNode then
    DoAnalyzeWhile(TMyrWhileNode(ANode))
  else if ANode is TMyrForNode then
    DoAnalyzeFor(TMyrForNode(ANode))
  else if ANode is TMyrRepeatNode then
    DoAnalyzeRepeat(TMyrRepeatNode(ANode))
  else if ANode is TMyrMatchNode then
    DoAnalyzeMatch(TMyrMatchNode(ANode))
  else if ANode is TMyrReturnNode then
    DoAnalyzeReturn(TMyrReturnNode(ANode))
  else if ANode is TMyrGuardNode then
    DoAnalyzeGuard(TMyrGuardNode(ANode))
  else if ANode is TMyrThrowNode then
    DoAnalyzeThrow(TMyrThrowNode(ANode))
  else if ANode is TMyrPrintNode then
    DoAnalyzePrint(TMyrPrintNode(ANode))
  else if ANode is TMyrAssertStmtNode then
    DoAnalyzeAssert(TMyrAssertStmtNode(ANode))
  else if ANode is TMyrBreakNode then
    DoAnalyzeBreak(TMyrBreakNode(ANode))
  else if ANode is TMyrContinueNode then
    DoAnalyzeContinue(TMyrContinueNode(ANode))
  else if ANode is TMyrNewNode then
    DoAnalyzeNew(TMyrNewNode(ANode))
  else if ANode is TMyrDisposeNode then
    DoAnalyzeDispose(TMyrDisposeNode(ANode))
  else if ANode is TMyrGetMemNode then
    DoAnalyzeGetMem(TMyrGetMemNode(ANode))
  else if ANode is TMyrFreeMemNode then
    DoAnalyzeFreeMem(TMyrFreeMemNode(ANode))
  else if ANode is TMyrResizeMemNode then
    DoAnalyzeResizeMem(TMyrResizeMemNode(ANode))
  else if ANode is TMyrSetLengthNode then
    DoAnalyzeSetLength(TMyrSetLengthNode(ANode))
  else if ANode is TMyrThrowCodeNode then
    // ThrowCode has code + message expressions
    DoAnalyzeThrow(nil)  // handled inline
  else if ANode is TMyrVarDeclNode then
    DoAnalyzeVarDecl(TMyrVarDeclNode(ANode))
  else if ANode is TMyrDirectiveNode then
    // Directives in statement position -- no analysis needed
  else if ANode is TMyrCppBlockNode then
    DoAnalyzeCppBlock(TMyrCppBlockNode(ANode))
  ;
end;

procedure TMyrSemantics.DoAnalyzeAssign(const ANode: TMyrAssignNode);
begin
  DoAnalyzeExpr(TMyrExprNode(ANode.Target));
  DoAnalyzeExpr(TMyrExprNode(ANode.ValueExpr));

  // Type check: value must be assignable to target
  if (TMyrExprNode(ANode.Target).ResolvedType <> nil) and
     (TMyrExprNode(ANode.ValueExpr).ResolvedType <> nil) then
  begin
    if not IsAssignableFrom(TMyrExprNode(ANode.Target).ResolvedType,
                            TMyrExprNode(ANode.ValueExpr).ResolvedType) then
      FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
        'Cannot assign: type mismatch');
  end;
end;

procedure TMyrSemantics.DoAnalyzeCallStmt(const ANode: TMyrCallStmtNode);
begin
  // The call expression handles all resolution
  if ANode.CallExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.CallExpr));
end;

procedure TMyrSemantics.DoAnalyzeIf(const ANode: TMyrIfNode);
begin
  // Condition must be boolean
  DoAnalyzeExpr(TMyrExprNode(ANode.Condition));
  if (TMyrExprNode(ANode.Condition).ResolvedType <> nil) and
     (not IsBooleanType(TMyrExprNode(ANode.Condition).ResolvedType)) then
    FErrors.Add(ANode.Condition.Location, esError, MYR_ERR_SEM_003,
      'If condition must be boolean');

  DoAnalyzeStatementSeq(ANode.ThenBody);

  // ElseBody contains either the else statements or a nested TMyrIfNode
  // for elsif chains (parser flattens elsif into nested if/else)
  DoAnalyzeStatementSeq(ANode.ElseBody);
end;

procedure TMyrSemantics.DoAnalyzeWhile(const ANode: TMyrWhileNode);
begin
  DoAnalyzeExpr(TMyrExprNode(ANode.Condition));
  if (TMyrExprNode(ANode.Condition).ResolvedType <> nil) and
     (not IsBooleanType(TMyrExprNode(ANode.Condition).ResolvedType)) then
    FErrors.Add(ANode.Condition.Location, esError, MYR_ERR_SEM_003,
      'While condition must be boolean');

  Inc(FLoopDepth);
  DoAnalyzeStatementSeq(ANode.Body);
  Dec(FLoopDepth);
end;

procedure TMyrSemantics.DoAnalyzeFor(const ANode: TMyrForNode);
begin
  // Analyze start and end expressions
  DoAnalyzeExpr(TMyrExprNode(ANode.StartExpr));
  DoAnalyzeExpr(TMyrExprNode(ANode.EndExpr));

  // Push block scope for iterator variable
  PushScope(skBlock);
  try
    Inc(FLoopDepth);
    DoAnalyzeStatementSeq(ANode.Body);
    Dec(FLoopDepth);
  finally
    PopScope();
  end;
end;

procedure TMyrSemantics.DoAnalyzeRepeat(const ANode: TMyrRepeatNode);
begin
  Inc(FLoopDepth);
  DoAnalyzeStatementSeq(ANode.Body);
  Dec(FLoopDepth);

  DoAnalyzeExpr(TMyrExprNode(ANode.Condition));
  if (TMyrExprNode(ANode.Condition).ResolvedType <> nil) and
     (not IsBooleanType(TMyrExprNode(ANode.Condition).ResolvedType)) then
    FErrors.Add(ANode.Condition.Location, esError, MYR_ERR_SEM_003,
      'Repeat condition must be boolean');
end;

procedure TMyrSemantics.DoAnalyzeMatch(const ANode: TMyrMatchNode);
var
  I: Integer;
  LArm: TMyrMatchArmNode;
begin
  DoAnalyzeExpr(TMyrExprNode(ANode.Expr));

  for I := 0 to ANode.Arms.Count - 1 do
  begin
    LArm := TMyrMatchArmNode(ANode.Arms[I]);
    DoAnalyzeStatementSeq(LArm.Body);
  end;

  // Analyze else body if present
  DoAnalyzeStatementSeq(ANode.ElseBody);
end;

procedure TMyrSemantics.DoAnalyzeReturn(const ANode: TMyrReturnNode);
begin
  if ANode.ValueExpr <> nil then
  begin
    DoAnalyzeExpr(TMyrExprNode(ANode.ValueExpr));
    // Check return type matches (only inside a routine with a declared return type)
    if (FCurrentRoutine <> nil) and
       (FCurrentRoutine.ReturnType <> nil) and
       (TMyrExprNode(ANode.ValueExpr).ResolvedType <> nil) then
    begin
      if not IsAssignableFrom(GetResolvedTypeDecl(FCurrentRoutine.ReturnType),
                              TMyrExprNode(ANode.ValueExpr).ResolvedType) then
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
          'Return value type does not match function return type');
    end;
  end
  else if (FCurrentRoutine <> nil) and (FCurrentRoutine.ReturnType <> nil) then
    FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
      'Function requires a return value');
end;

procedure TMyrSemantics.DoAnalyzeGuard(const ANode: TMyrGuardNode);
begin
  DoAnalyzeStatementSeq(ANode.GuardBody);
  DoAnalyzeStatementSeq(ANode.ExceptBody);
  DoAnalyzeStatementSeq(ANode.FinallyBody);
end;

procedure TMyrSemantics.DoAnalyzeThrow(const ANode: TMyrThrowNode);
begin
  if ANode = nil then
    Exit;
  if ANode.MessageExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.MessageExpr));
end;

procedure TMyrSemantics.DoAnalyzePrint(const ANode: TMyrPrintNode);
var
  I: Integer;
begin
  // All print arguments (first is format string, rest are values)
  for I := 0 to ANode.Args.Count - 1 do
    DoAnalyzeExpr(TMyrExprNode(ANode.Args[I]));
end;

procedure TMyrSemantics.DoAnalyzeAssert(const ANode: TMyrAssertStmtNode);
var
  I: Integer;
begin
  // Analyze all assert arguments
  for I := 0 to ANode.Args.Count - 1 do
    DoAnalyzeExpr(TMyrExprNode(ANode.Args[I]));
end;

procedure TMyrSemantics.DoAnalyzeBreak(const ANode: TMyrBreakNode);
begin
  if FLoopDepth = 0 then
    FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_005,
      'Break statement outside of a loop');
end;

procedure TMyrSemantics.DoAnalyzeContinue(const ANode: TMyrContinueNode);
begin
  if FLoopDepth = 0 then
    FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_005,
      'Continue statement outside of a loop');
end;

{ TMyrSemantics.DoAnalyzeCppBlock }
procedure TMyrSemantics.DoAnalyzeCppBlock(const ANode: TMyrCppBlockNode);
begin
  // Validate target is 'header' or 'source'
  if (ANode.Target <> 'header') and (ANode.Target <> 'source') then
    FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_013,
      'cppstart target must be ''header'' or ''source'', got ''%s''',
      [ANode.Target]);
end;

{ TMyrSemantics.DoAnalyzeNew }
procedure TMyrSemantics.DoAnalyzeNew(const ANode: TMyrNewNode);
begin
  if ANode.ArgExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.ArgExpr));
end;

procedure TMyrSemantics.DoAnalyzeDispose(const ANode: TMyrDisposeNode);
begin
  if ANode.ArgExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.ArgExpr));
end;

procedure TMyrSemantics.DoAnalyzeGetMem(const ANode: TMyrGetMemNode);
begin
  if ANode.ArgExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.ArgExpr));
end;

procedure TMyrSemantics.DoAnalyzeFreeMem(const ANode: TMyrFreeMemNode);
begin
  if ANode.ArgExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.ArgExpr));
end;

procedure TMyrSemantics.DoAnalyzeResizeMem(const ANode: TMyrResizeMemNode);
begin
  if ANode.PtrExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.PtrExpr));
  if ANode.SizeExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.SizeExpr));
end;

procedure TMyrSemantics.DoAnalyzeSetLength(const ANode: TMyrSetLengthNode);
begin
  if ANode.TargetExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.TargetExpr));
  if ANode.LengthExpr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.LengthExpr));
end;

procedure TMyrSemantics.DoAnalyzeExpr(const ANode: TMyrExprNode);
begin
  if ANode = nil then
    Exit;

  if ANode is TMyrBinaryExprNode then
    DoAnalyzeBinaryExpr(TMyrBinaryExprNode(ANode))
  else if ANode is TMyrUnaryExprNode then
    DoAnalyzeUnaryExpr(TMyrUnaryExprNode(ANode))
  else if ANode is TMyrIdentifierNode then
    DoAnalyzeIdentifier(TMyrIdentifierNode(ANode))
  else if ANode is TMyrDotAccessNode then
    DoAnalyzeDotAccess(TMyrDotAccessNode(ANode))
  else if ANode is TMyrIndexAccessNode then
    DoAnalyzeIndexAccess(TMyrIndexAccessNode(ANode))
  else if ANode is TMyrDerefNode then
    DoAnalyzeDeref(TMyrDerefNode(ANode))
  else if ANode is TMyrCallExprNode then
    DoAnalyzeCallExpr(TMyrCallExprNode(ANode))
  else if ANode is TMyrTypeCastExprNode then
    DoAnalyzeTypeCast(TMyrTypeCastExprNode(ANode))
  else if ANode is TMyrIntrinsicExprNode then
    DoAnalyzeIntrinsic(TMyrIntrinsicExprNode(ANode))
  else if ANode is TMyrSetLiteralExprNode then
    DoAnalyzeSetLiteral(TMyrSetLiteralExprNode(ANode))
  else if ANode is TMyrRecordLiteralNode then
    DoAnalyzeRecordLiteral(TMyrRecordLiteralNode(ANode))
  else if ANode is TMyrCppExprNode then
    // cpp() expressions pass through -- raw C++ with no semantic analysis
  else if ANode is TMyrTypeRefNode then
    DoAnalyzeTypeRef(TMyrTypeRefNode(ANode))
  else if (ANode is TMyrIntLiteralNode) or (ANode is TMyrFloatLiteralNode) or
          (ANode is TMyrStringLiteralNode) or (ANode is TMyrWStringLiteralNode) or
          (ANode is TMyrBoolLiteralNode) or (ANode is TMyrNilLiteralNode) then
    DoResolveLiteralType(ANode);
end;

procedure TMyrSemantics.DoResolveLiteralType(const ANode: TMyrExprNode);
begin
  if ANode is TMyrIntLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkInt32)
  else if ANode is TMyrFloatLiteralNode then
  begin
    if TMyrFloatLiteralNode(ANode).HasSuffix then
      ANode.ResolvedType := GetPrimitiveType(tkFloat32)
    else
      ANode.ResolvedType := GetPrimitiveType(tkFloat64);
  end
  else if ANode is TMyrStringLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkString)
  else if ANode is TMyrWStringLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkWString)
  else if ANode is TMyrBoolLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkBoolean)
  else if ANode is TMyrNilLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkPointer);
end;

procedure TMyrSemantics.DoAnalyzeBinaryExpr(const ANode: TMyrBinaryExprNode);
var
  LLeft: TMyrASTNode;
  LRight: TMyrASTNode;
begin
  DoAnalyzeExpr(TMyrExprNode(ANode.Left));
  DoAnalyzeExpr(TMyrExprNode(ANode.Right));

  LLeft := TMyrExprNode(ANode.Left).ResolvedType;
  LRight := TMyrExprNode(ANode.Right).ResolvedType;

  if (LLeft = nil) or (LRight = nil) then
    Exit;

  // Comparison operators always produce boolean
  case ANode.Op of
    boEq, boNotEq, boLess, boGreater, boLessEq, boGreaterEq:
      ANode.ResolvedType := GetPrimitiveType(tkBoolean);
    boAnd, boOr, boXor:
    begin
      if IsBooleanType(LLeft) and IsBooleanType(LRight) then
      begin
        // Boolean context: logical operators
        ANode.ResolvedType := GetPrimitiveType(tkBoolean);
        if ANode.Op = boAnd then
          ANode.Op := boLogicalAnd
        else if ANode.Op = boOr then
          ANode.Op := boLogicalOr;
        // boXor stays as boXor -- C++ ^ is correct for boolean xor
      end
      else if IsIntegerType(LLeft) and IsIntegerType(LRight) then
      begin
        // Integer context: bitwise operators
        ANode.ResolvedType := PromoteTypes(LLeft, LRight);
      end
      else
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
          'and/or/xor requires both operands to be boolean or both integer');
    end;
    boIn:
      ANode.ResolvedType := GetPrimitiveType(tkBoolean);
  else
    // Set arithmetic: +, -, * on set types
    if (LLeft is TMyrSetTypeNode) and (LRight is TMyrSetTypeNode) then
    begin
      if ANode.Op in [boAdd, boSub, boMul] then
        ANode.ResolvedType := LLeft
      else
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
          'Invalid operator for set types');
    end
    else
    begin
      // Arithmetic: promote types
      ANode.ResolvedType := PromoteTypes(LLeft, LRight);
      if ANode.ResolvedType = nil then
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
          'Incompatible types for binary operator');
    end;
  end;
end;

procedure TMyrSemantics.DoAnalyzeUnaryExpr(const ANode: TMyrUnaryExprNode);
begin
  DoAnalyzeExpr(TMyrExprNode(ANode.Operand));

  if TMyrExprNode(ANode.Operand).ResolvedType = nil then
    Exit;

  if ANode.Op = uoNot then
  begin
    if not IsBooleanType(TMyrExprNode(ANode.Operand).ResolvedType) then
      FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
        'Not operator requires boolean operand');
    ANode.ResolvedType := GetPrimitiveType(tkBoolean);
  end
  else if ANode.Op = uoAddressOf then
    ANode.ResolvedType := GetPrimitiveType(tkPointer)
  else
    // Unary minus/plus: same type as operand
    ANode.ResolvedType := TMyrExprNode(ANode.Operand).ResolvedType;
end;

procedure TMyrSemantics.DoAnalyzeIdentifier(const ANode: TMyrIdentifierNode);
var
  LDecl: TMyrASTNode;
begin
  LDecl := FCurrentScope.Lookup(ANode.IdentName);

  // Check if it's an imported module name (would need dot access)
  if LDecl = nil then
  begin
    // Check if it matches any import name -- that's an unqualified access error
    if FCurrentModule <> nil then
    begin
      // Check imports for name match
    end;
    FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
      'Undeclared identifier: %s', [ANode.IdentName]);
    Exit;
  end;

  ANode.ResolvedDecl := LDecl;

  // Resolve type based on what the identifier refers to
  ANode.ResolvedType := DoResolvedTypeOfDecl(LDecl);
end;

procedure TMyrSemantics.DoAnalyzeDotAccess(const ANode: TMyrDotAccessNode);

  function FindFieldInFields(const AFields: TObjectList<TMyrASTNode>;
    const AName: string): TMyrFieldDeclNode;
  var
    LI: Integer;
    LF: TMyrFieldDeclNode;
    LResult: TMyrFieldDeclNode;
  begin
    Result := nil;
    for LI := 0 to AFields.Count - 1 do
    begin
      if AFields[LI] is TMyrFieldDeclNode then
      begin
        LF := TMyrFieldDeclNode(AFields[LI]);
        if LF.FieldName = AName then
          Exit(LF);
      end
      else if AFields[LI] is TMyrAnonOverlayNode then
      begin
        LResult := FindFieldInFields(TMyrAnonOverlayNode(AFields[LI]).Fields, AName);
        if LResult <> nil then
          Exit(LResult);
      end
      else if AFields[LI] is TMyrAnonRecordNode then
      begin
        LResult := FindFieldInFields(TMyrAnonRecordNode(AFields[LI]).Fields, AName);
        if LResult <> nil then
          Exit(LResult);
      end;
    end;
  end;

var
  LLeft: TMyrExprNode;
  LModuleScope: TMyrScope;
  LDecl: TMyrASTNode;
  LRecordType: TMyrRecordTypeNode;
  LField: TMyrFieldDeclNode;
  LBaseDecl: TMyrASTNode;
begin
  LLeft := TMyrExprNode(ANode.BaseExpr);
  DoAnalyzeExpr(LLeft);

  // Check if left side is a module name (cross-module qualified access)
  if (LLeft is TMyrIdentifierNode) and
     (TMyrIdentifierNode(LLeft).ResolvedDecl is TMyrImportNode) then
  begin
    // It might be a module name -- check imports
    if FModuleScopes.TryGetValue(TMyrIdentifierNode(LLeft).IdentName, LModuleScope) then
    begin
      // Verify it's actually imported
      LDecl := LModuleScope.LookupLocal(ANode.MemberName);
      if LDecl = nil then
      begin
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
          'Symbol not found in module %s: %s',
          [TMyrIdentifierNode(LLeft).IdentName, ANode.MemberName]);
        Exit;
      end;

      // Check visibility
      if (LDecl is TMyrDeclNode) and (not TMyrDeclNode(LDecl).IsPublic) then
      begin
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_008,
          'Symbol %s.%s is not public',
          [TMyrIdentifierNode(LLeft).IdentName, ANode.MemberName]);
        Exit;
      end;

      ANode.ResolvedDecl := LDecl;
      ANode.AccessKind := dakModule;
      // Resolve type of the accessed symbol -- same authority as identifiers
      ANode.ResolvedType := DoResolvedTypeOfDecl(LDecl);
      Exit;
    end;
  end;

  // Left side is a record -- resolve field access
  if LLeft.ResolvedType is TMyrTypeDeclNode then
  begin
    if TMyrTypeDeclNode(LLeft.ResolvedType).TypeDef is TMyrRecordTypeNode then
    begin
      LRecordType := TMyrRecordTypeNode(TMyrTypeDeclNode(LLeft.ResolvedType).TypeDef);
      // Search own fields, anonymous overlays/records, and inherited fields
      while LRecordType <> nil do
      begin
        LField := FindFieldInFields(LRecordType.Fields, ANode.MemberName);
        if LField <> nil then
        begin
          ANode.ResolvedDecl := LField;
          ANode.ResolvedType := GetResolvedTypeDecl(LField.TypeExpr);
          ANode.AccessKind := dakField;
          Exit;
        end;
        // Walk up to base type
        LBaseDecl := GetResolvedTypeDecl(LRecordType.BaseType);
        if (LBaseDecl is TMyrTypeDeclNode) and
           (TMyrTypeDeclNode(LBaseDecl).TypeDef is TMyrRecordTypeNode) then
          LRecordType := TMyrRecordTypeNode(TMyrTypeDeclNode(LBaseDecl).TypeDef)
        else
          LRecordType := nil;
      end;
      FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
        'Field not found: %s', [ANode.MemberName]);
    end
    else if TMyrTypeDeclNode(LLeft.ResolvedType).TypeDef is TMyrChoicesTypeNode then
    begin
      // Choices member access: MyEnum.Value
      ANode.AccessKind := dakChoices;
      ANode.ResolvedType := LLeft.ResolvedType;
    end;
  end;
end;

procedure TMyrSemantics.DoAnalyzeIndexAccess(const ANode: TMyrIndexAccessNode);
begin
  DoAnalyzeExpr(TMyrExprNode(ANode.BaseExpr));
  DoAnalyzeExpr(TMyrExprNode(ANode.IndexExpr));

  // Index must be integer
  if (TMyrExprNode(ANode.IndexExpr).ResolvedType <> nil) and
     (not IsIntegerType(TMyrExprNode(ANode.IndexExpr).ResolvedType)) then
    FErrors.Add(ANode.IndexExpr.Location, esError, MYR_ERR_SEM_003,
      'Array index must be an integer type');

  // Result type is the array element type
  if TMyrExprNode(ANode.BaseExpr).ResolvedType is TMyrTypeDeclNode then
  begin
    if TMyrTypeDeclNode(TMyrExprNode(ANode.BaseExpr).ResolvedType).TypeDef is TMyrArrayTypeNode then
      ANode.ResolvedType := GetResolvedTypeDecl(TMyrArrayTypeNode(
        TMyrTypeDeclNode(TMyrExprNode(ANode.BaseExpr).ResolvedType).TypeDef).ElementType);
  end;
end;

procedure TMyrSemantics.DoAnalyzeDeref(const ANode: TMyrDerefNode);
begin
  DoAnalyzeExpr(TMyrExprNode(ANode.BaseExpr));

  if TMyrExprNode(ANode.BaseExpr).ResolvedType = nil then
    Exit;

  if not IsPointerType(TMyrExprNode(ANode.BaseExpr).ResolvedType) then
    FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_013,
      'Dereference requires a pointer type');

  // Result type is the pointer's target type. The base may carry either a
  // named pointer type (TMyrTypeDeclNode wrapping TMyrPointerTypeNode) or an
  // anonymous one (TMyrPointerTypeNode directly, from "pointer to T" on a var).
  if TMyrExprNode(ANode.BaseExpr).ResolvedType is TMyrTypeDeclNode then
  begin
    if TMyrTypeDeclNode(TMyrExprNode(ANode.BaseExpr).ResolvedType).TypeDef is TMyrPointerTypeNode then
      ANode.ResolvedType := GetResolvedTypeDecl(TMyrPointerTypeNode(
        TMyrTypeDeclNode(TMyrExprNode(ANode.BaseExpr).ResolvedType).TypeDef).TargetType);
  end
  else if TMyrExprNode(ANode.BaseExpr).ResolvedType is TMyrPointerTypeNode then
    ANode.ResolvedType := GetResolvedTypeDecl(
      TMyrPointerTypeNode(TMyrExprNode(ANode.BaseExpr).ResolvedType).TargetType);
end;

{ TMyrSemantics.DoOverloadTypesMatch }
function TMyrSemantics.DoOverloadTypesMatch(const ARoutine: TMyrRoutineDeclNode;
  const ACall: TMyrCallExprNode): Boolean;
var
  I: Integer;
  LParamType: TMyrASTNode;
  LArgType: TMyrASTNode;
begin
  Result := True;
  for I := 0 to ARoutine.Params.Count - 1 do
  begin
    if I >= ACall.Args.Count then
      Exit(False);
    LParamType := GetResolvedTypeDecl(TMyrVarDeclNode(ARoutine.Params[I]).TypeExpr);
    LArgType := TMyrExprNode(ACall.Args[I]).ResolvedType;
    if (LParamType = nil) or (LArgType = nil) then
      Continue;
    // Float param requires float arg (and vice versa)
    if IsFloatType(LParamType) <> IsFloatType(LArgType) then
      Exit(False);
  end;
end;

function TMyrSemantics.DoResolvedTypeOfDecl(const ADecl: TMyrASTNode): TMyrASTNode;
begin
  Result := nil;
  if ADecl is TMyrVarDeclNode then
    Result := GetResolvedTypeDecl(TMyrVarDeclNode(ADecl).TypeExpr)
  else if ADecl is TMyrConstDeclNode then
  begin
    if TMyrConstDeclNode(ADecl).TypeExpr <> nil then
      Result := GetResolvedTypeDecl(TMyrConstDeclNode(ADecl).TypeExpr)
    else if TMyrConstDeclNode(ADecl).ValueExpr <> nil then
      Result := TMyrExprNode(TMyrConstDeclNode(ADecl).ValueExpr).ResolvedType;
  end
  else if ADecl is TMyrParamDeclNode then
    Result := GetResolvedTypeDecl(TMyrParamDeclNode(ADecl).TypeExpr)
  else if ADecl is TMyrRoutineDeclNode then
    // Routine -- type is the routine itself
    Result := ADecl
  else if ADecl is TMyrOverloadGroupNode then
    // Overload group -- resolved to a concrete routine at the call site
    Result := ADecl
  else if ADecl is TMyrForwardRoutineDeclNode then
    Result := ADecl
  else if ADecl is TMyrImportNode then
    // Import module name -- the import itself (for dot access)
    Result := ADecl
  else if ADecl is TMyrTypeDeclNode then
    Result := ADecl;
end;

procedure TMyrSemantics.DoAnalyzeCallExpr(const ANode: TMyrCallExprNode);
var
  LRoutine: TMyrRoutineDeclNode;
  LForwardRoutine: TMyrForwardRoutineDeclNode;
  LGroup: TMyrOverloadGroupNode;
  LMatched: TMyrRoutineDeclNode;
  I: Integer;
begin
  DoAnalyzeExpr(TMyrExprNode(ANode.Callee));

  // Analyze arguments
  for I := 0 to ANode.Args.Count - 1 do
    DoAnalyzeExpr(TMyrExprNode(ANode.Args[I]));

  // Resolve the call target
  if TMyrExprNode(ANode.Callee).ResolvedType is TMyrOverloadGroupNode then
  begin
    // Overload resolution: match by argument count, prefer type-compatible
    LGroup := TMyrOverloadGroupNode(TMyrExprNode(ANode.Callee).ResolvedType);
    LMatched := nil;
    for I := 0 to LGroup.Overloads.Count - 1 do
    begin
      LRoutine := LGroup.Overloads[I];
      if LRoutine.IsVariadic then
      begin
        if ANode.Args.Count >= LRoutine.Params.Count then
        begin
          LMatched := LRoutine;
          Break;
        end;
      end
      else if ANode.Args.Count = LRoutine.Params.Count then
      begin
        // Check if argument types match parameter types
        if DoOverloadTypesMatch(LRoutine, ANode) then
        begin
          LMatched := LRoutine;
          Break;
        end;
        // Keep first count-match as fallback
        if LMatched = nil then
          LMatched := LRoutine;
      end;
    end;

    if LMatched <> nil then
    begin
      ANode.ResolvedRoutine := LMatched;
      ANode.ResolvedType := GetResolvedTypeDecl(LMatched.ReturnType);
    end
    else
      FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_004,
        'No overload of "%s" matches %d argument(s)', [LGroup.DeclName, ANode.Args.Count]);
  end
  else if TMyrExprNode(ANode.Callee).ResolvedType is TMyrRoutineDeclNode then
  begin
    LRoutine := TMyrRoutineDeclNode(TMyrExprNode(ANode.Callee).ResolvedType);
    ANode.ResolvedRoutine := LRoutine;
    ANode.ResolvedType := GetResolvedTypeDecl(LRoutine.ReturnType);

    // Check argument count (account for variadic)
    if not LRoutine.IsVariadic then
    begin
      if ANode.Args.Count <> LRoutine.Params.Count then
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_004,
          'Expected %d arguments, got %d', [LRoutine.Params.Count, ANode.Args.Count]);
    end
    else
    begin
      if ANode.Args.Count < LRoutine.Params.Count then
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_004,
          'Expected at least %d arguments, got %d', [LRoutine.Params.Count, ANode.Args.Count]);
    end;
  end
  else if TMyrExprNode(ANode.Callee).ResolvedType is TMyrForwardRoutineDeclNode then
  begin
    LForwardRoutine := TMyrForwardRoutineDeclNode(TMyrExprNode(ANode.Callee).ResolvedType);
    ANode.ResolvedRoutine := LForwardRoutine;
    ANode.ResolvedType := GetResolvedTypeDecl(LForwardRoutine.ReturnType);
  end
  else if (TMyrExprNode(ANode.Callee).ResolvedType is TMyrTypeDeclNode) and
          (TMyrTypeDeclNode(TMyrExprNode(ANode.Callee).ResolvedType).TypeDef is TMyrRoutineTypeNode) then
  begin
    // Calling through a routine type variable
    ANode.ResolvedType := GetResolvedTypeDecl(TMyrRoutineTypeNode(TMyrTypeDeclNode(
      TMyrExprNode(ANode.Callee).ResolvedType).TypeDef).ReturnType);
  end;

  // Auto-coerce string/wstring args to pointer to char/wchar
  DoCoerceCallArgs(ANode);
end;

procedure TMyrSemantics.DoCoerceCallArgs(const ANode: TMyrCallExprNode);
var
  LRoutine: TMyrRoutineDeclNode;
  LI: Integer;
  LParamType: TMyrASTNode;
  LArgType: TMyrASTNode;
  LOldArg: TMyrASTNode;
  LWrapper: TMyrIntrinsicExprNode;
  LPtr: TMyrPointerTypeNode;
  LTargetKind: TMyrTokenKind;
  LIntrinsicKind: TMyrIntrinsicKind;
begin
  if not (ANode.ResolvedRoutine is TMyrRoutineDeclNode) then
    Exit;
  LRoutine := TMyrRoutineDeclNode(ANode.ResolvedRoutine);

  for LI := 0 to ANode.Args.Count - 1 do
  begin
    if LI >= LRoutine.Params.Count then
      Break;

    LParamType := LRoutine.Params[LI].TypeExpr;
    LArgType := TMyrExprNode(ANode.Args[LI]).ResolvedType;

    // Skip if param is not pointer to char/wchar
    if not (LParamType is TMyrPointerTypeNode) then
      Continue;
    LPtr := TMyrPointerTypeNode(LParamType);
    if not (LPtr.TargetType is TMyrTypeRefNode) then
      Continue;
    LTargetKind := TMyrTypeRefNode(LPtr.TargetType).TokenKind;

    // String literals are already raw char*/wchar* -- no managed header,
    // so cstr()/cwstr() (which call RT_StrData) would AV reading a
    // nonexistent header at a negative offset. Skip the wrap entirely.
    if ANode.Args[LI] is TMyrStringLiteralNode then
      Continue;

    // string -> pointer to char: auto-insert cstr()
    if (LTargetKind = tkChar) and (LArgType = GetPrimitiveType(tkString)) then
      LIntrinsicKind := ikCStr
    // wstring -> pointer to wchar: auto-insert cwstr()
    else if (LTargetKind = tkWChar) and (LArgType = GetPrimitiveType(tkWString)) then
      LIntrinsicKind := ikWStr
    else
      Continue;

    // Extract old arg without freeing, wrap in intrinsic, insert back
    LOldArg := ANode.Args[LI];
    ANode.Args.Extract(LOldArg);
    LWrapper := TMyrIntrinsicExprNode.Create();
    LWrapper.IntrinsicKind := LIntrinsicKind;
    LWrapper.Args.Add(LOldArg);
    LWrapper.ResolvedType := TMyrExprNode(LOldArg).ResolvedType;
    ANode.Args.Insert(LI, LWrapper);
  end;
end;

procedure TMyrSemantics.DoAnalyzeTypeCast(const ANode: TMyrTypeCastExprNode);
begin
  if ANode.TargetType <> nil then
    ResolveTypeExpr(ANode.TargetType);
  if ANode.Expr <> nil then
    DoAnalyzeExpr(TMyrExprNode(ANode.Expr));
  ANode.ResolvedType := GetResolvedTypeDecl(ANode.TargetType);
end;

procedure TMyrSemantics.DoAnalyzeIntrinsic(const ANode: TMyrIntrinsicExprNode);
var
  I: Integer;
begin
  // Analyze all arguments
  for I := 0 to ANode.Args.Count - 1 do
    DoAnalyzeExpr(TMyrExprNode(ANode.Args[I]));

  // Resolve result type based on intrinsic kind
  case ANode.IntrinsicKind of
    ikLen:
      ANode.ResolvedType := GetPrimitiveType(tkInt32);
    ikSize:
      ANode.ResolvedType := GetPrimitiveType(tkInt64);
    ikParamCount:
      ANode.ResolvedType := GetPrimitiveType(tkInt32);
    ikParamStr:
      ANode.ResolvedType := GetPrimitiveType(tkString);
    ikExcCode:
      ANode.ResolvedType := GetPrimitiveType(tkInt32);
    ikExcMsg:
      ANode.ResolvedType := GetPrimitiveType(tkString);
    ikUtf8:
      ANode.ResolvedType := GetPrimitiveType(tkString);
    ikWStr:
      ANode.ResolvedType := FPointerToWChar;
    ikCStr:
      ANode.ResolvedType := FPointerToChar;
  end;
end;

procedure TMyrSemantics.DoAnalyzeSetLiteral(const ANode: TMyrSetLiteralExprNode);
var
  I: Integer;
begin
  for I := 0 to ANode.Elements.Count - 1 do
  begin
    if TMyrSetElementNode(ANode.Elements[I]).LowExpr <> nil then
      DoAnalyzeExpr(TMyrExprNode(TMyrSetElementNode(ANode.Elements[I]).LowExpr));
    if TMyrSetElementNode(ANode.Elements[I]).HighExpr <> nil then
      DoAnalyzeExpr(TMyrExprNode(TMyrSetElementNode(ANode.Elements[I]).HighExpr));
  end;
end;

procedure TMyrSemantics.DoAnalyzeRecordLiteral(const ANode: TMyrRecordLiteralNode);
var
  I: Integer;
  LDecl: TMyrASTNode;
begin
  // Resolve the type by name -- module-qualified or local
  if ANode.TypeName <> '' then
  begin
    if ANode.ModuleName <> '' then
    begin
      // Module-qualified: look up in the module's scope
      if FModuleScopes.ContainsKey(ANode.ModuleName) then
      begin
        LDecl := FModuleScopes[ANode.ModuleName].LookupLocal(ANode.TypeName);
        if LDecl <> nil then
        begin
          if (LDecl is TMyrTypeDeclNode) and TMyrTypeDeclNode(LDecl).IsPublic then
            ANode.ResolvedType := LDecl
          else if (LDecl is TMyrTypeDeclNode) and not TMyrTypeDeclNode(LDecl).IsPublic then
            FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
              'Type ''%s'' in module ''%s'' is not public', [ANode.TypeName, ANode.ModuleName])
          else
            ANode.ResolvedType := LDecl;
        end
        else
          FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
            'Undeclared type: %s.%s', [ANode.ModuleName, ANode.TypeName]);
      end
      else
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
          'Unknown module: %s', [ANode.ModuleName]);
    end
    else
    begin
      LDecl := FCurrentScope.Lookup(ANode.TypeName);
      if LDecl <> nil then
        ANode.ResolvedType := LDecl
      else
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
          'Undeclared type: %s', [ANode.TypeName]);
    end;
  end;

  for I := 0 to ANode.FieldInits.Count - 1 do
  begin
    if ANode.FieldInits[I].ValueExpr <> nil then
      DoAnalyzeExpr(TMyrExprNode(ANode.FieldInits[I].ValueExpr));
  end;
end;

procedure TMyrSemantics.DoAnalyzeTypeRef(const ANode: TMyrTypeRefNode);
begin
  ResolveTypeExpr(ANode);
  ANode.ResolvedType := ANode.ResolvedDecl;

  // Set CppTypeText for user-defined types (primitives already set by parser)
  if (ANode.CppTypeText = '') and (ANode.ResolvedDecl is TMyrTypeDeclNode) then
    ANode.CppTypeText := TMyrTypeDeclNode(ANode.ResolvedDecl).DeclName;
end;

// Type resolution and helpers
procedure TMyrSemantics.ResolveTypeExpr(const ANode: TMyrASTNode);
var
  LDecl: TMyrASTNode;
  LRef: TMyrTypeRefNode;
  LPrimitive: TMyrTypeDeclNode;
  LName: string;
  LModuleScope: TMyrScope;
begin
  if not (ANode is TMyrTypeRefNode) then
  begin
    DoAnalyzeTypeDef(ANode);
    Exit;
  end;

  LRef := TMyrTypeRefNode(ANode);

  // Check if it's a primitive type by token kind
  if LRef.TokenKind <> tkIdentifier then
  begin
    if FPrimitiveTypes.TryGetValue(LRef.TokenKind, LPrimitive) then
      LRef.ResolvedDecl := LPrimitive;
  end
  // Qualified access: ModuleName.TypeName
  else if Length(LRef.QualParts) = 2 then
  begin
    if FModuleScopes.TryGetValue(LRef.QualParts[0], LModuleScope) then
    begin
      LDecl := LModuleScope.LookupLocal(LRef.QualParts[1]);
      if LDecl = nil then
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
          'Type not found in module %s: %s', [LRef.QualParts[0], LRef.QualParts[1]])
      else if (LDecl is TMyrDeclNode) and (not TMyrDeclNode(LDecl).IsPublic) then
        FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_008,
          'Type %s.%s is not public', [LRef.QualParts[0], LRef.QualParts[1]])
      else
        LRef.ResolvedDecl := LDecl;
    end
    else
      FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
        'Module scope not found: %s', [LRef.QualParts[0]]);
  end
  // Unqualified: single name lookup
  else if (Length(LRef.QualParts) = 1) and (LRef.QualParts[0] <> '') then
  begin
    LName := LRef.QualParts[0];
    LDecl := FCurrentScope.Lookup(LName);
    if LDecl = nil then
      FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_001,
        'Undeclared type: %s', [LName])
    else if (LDecl is TMyrTypeDeclNode) or (LDecl is TMyrForwardTypeDeclNode) then
      LRef.ResolvedDecl := LDecl
    else
      FErrors.Add(ANode.Location, esError, MYR_ERR_SEM_003,
        '%s is not a type', [LName]);
  end;
end;

function TMyrSemantics.GetResolvedTypeDecl(const ANode: TMyrASTNode): TMyrASTNode;
begin
  if ANode is TMyrTypeRefNode then
    Result := TMyrTypeRefNode(ANode).ResolvedDecl
  else
    Result := ANode;
end;

function TMyrSemantics.IsAssignableFrom(const ATarget: TMyrASTNode;
  const ASource: TMyrASTNode): Boolean;
var
  LTargetPtr: TMyrPointerTypeNode;
  LSourcePtr: TMyrPointerTypeNode;
  LTargetBase: TMyrASTNode;
  LSourceBase: TMyrASTNode;
begin
  Result := False;
  if (ATarget = nil) or (ASource = nil) then
    Exit;

  // Same type
  if ATarget = ASource then
  begin
    Result := True;
    Exit;
  end;

  // Structural pointer comparison: pointer to X = pointer to X
  // Different TMyrPointerTypeNode instances may refer to the same target type
  LTargetPtr := nil;
  LSourcePtr := nil;
  if ATarget is TMyrPointerTypeNode then
    LTargetPtr := TMyrPointerTypeNode(ATarget)
  else if (ATarget is TMyrTypeDeclNode) and
          (TMyrTypeDeclNode(ATarget).TypeDef is TMyrPointerTypeNode) then
    LTargetPtr := TMyrPointerTypeNode(TMyrTypeDeclNode(ATarget).TypeDef);
  if ASource is TMyrPointerTypeNode then
    LSourcePtr := TMyrPointerTypeNode(ASource)
  else if (ASource is TMyrTypeDeclNode) and
          (TMyrTypeDeclNode(ASource).TypeDef is TMyrPointerTypeNode) then
    LSourcePtr := TMyrPointerTypeNode(TMyrTypeDeclNode(ASource).TypeDef);
  if (LTargetPtr <> nil) and (LSourcePtr <> nil) then
  begin
    LTargetBase := GetResolvedTypeDecl(LTargetPtr.TargetType);
    LSourceBase := GetResolvedTypeDecl(LSourcePtr.TargetType);
    // Both untyped pointers
    if (LTargetBase = nil) and (LSourceBase = nil) then
    begin
      Result := True;
      Exit;
    end;
    // Both point to the same resolved type
    if (LTargetBase <> nil) and (LSourceBase <> nil) and (LTargetBase = LSourceBase) then
    begin
      Result := True;
      Exit;
    end;
  end;

  // Nil assignable to any pointer
  if IsPointerType(ATarget) and (ASource = GetPrimitiveType(tkPointer)) then
  begin
    Result := True;
    Exit;
  end;

  // Numeric promotion: int -> float
  if IsFloatType(ATarget) and IsIntegerType(ASource) then
  begin
    Result := True;
    Exit;
  end;

  // Smaller int -> larger int
  if IsIntegerType(ATarget) and IsIntegerType(ASource) then
  begin
    Result := True;
    Exit;
  end;

  // float32 -> float64
  if IsFloatType(ATarget) and IsFloatType(ASource) then
  begin
    Result := True;
    Exit;
  end;

  // Routine type: source is a routine decl, target is a routine type
  if (ATarget is TMyrTypeDeclNode) and
     (TMyrTypeDeclNode(ATarget).TypeDef is TMyrRoutineTypeNode) and
     (ASource is TMyrRoutineDeclNode) then
  begin
    Result := True;
    Exit;
  end;

  // Routine type: both are the same routine type (var-to-var assignment)
  if (ATarget is TMyrTypeDeclNode) and
     (TMyrTypeDeclNode(ATarget).TypeDef is TMyrRoutineTypeNode) and
     (ASource is TMyrTypeDeclNode) and
     (TMyrTypeDeclNode(ASource).TypeDef is TMyrRoutineTypeNode) then
  begin
    Result := True;
    Exit;
  end;

  // Set types are structurally compatible
  if (ATarget is TMyrSetTypeNode) and (ASource is TMyrSetTypeNode) then
  begin
    Result := True;
    Exit;
  end;
end;

function TMyrSemantics.PromoteTypes(const ALeft: TMyrASTNode;
  const ARight: TMyrASTNode): TMyrASTNode;
begin
  Result := nil;
  if (ALeft = nil) or (ARight = nil) then
    Exit;

  // Same type
  if ALeft = ARight then
  begin
    Result := ALeft;
    Exit;
  end;

  // Float + int -> float
  if IsFloatType(ALeft) and IsIntegerType(ARight) then
  begin
    Result := ALeft;
    Exit;
  end;
  if IsIntegerType(ALeft) and IsFloatType(ARight) then
  begin
    Result := ARight;
    Exit;
  end;

  // float32 + float64 -> float64
  if IsFloatType(ALeft) and IsFloatType(ARight) then
  begin
    Result := GetPrimitiveType(tkFloat64);
    Exit;
  end;

  // int + int -> larger int (simplified: promote to int64)
  if IsIntegerType(ALeft) and IsIntegerType(ARight) then
  begin
    Result := GetPrimitiveType(tkInt64);
    Exit;
  end;

  // String + string
  if IsStringType(ALeft) and IsStringType(ARight) then
  begin
    if ALeft = ARight then
      Result := ALeft
    else
      Result := GetPrimitiveType(tkString);
    Exit;
  end;
end;

function TMyrSemantics.IsIntegerType(const AType: TMyrASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkInt8)) or
            (AType = GetPrimitiveType(tkInt16)) or
            (AType = GetPrimitiveType(tkInt32)) or
            (AType = GetPrimitiveType(tkInt64)) or
            (AType = GetPrimitiveType(tkUInt8)) or
            (AType = GetPrimitiveType(tkUInt16)) or
            (AType = GetPrimitiveType(tkUInt32)) or
            (AType = GetPrimitiveType(tkUInt64));
end;

function TMyrSemantics.IsFloatType(const AType: TMyrASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkFloat32)) or
            (AType = GetPrimitiveType(tkFloat64));
end;

function TMyrSemantics.IsNumericType(const AType: TMyrASTNode): Boolean;
begin
  Result := IsIntegerType(AType) or IsFloatType(AType);
end;

function TMyrSemantics.IsBooleanType(const AType: TMyrASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkBoolean));
end;

function TMyrSemantics.IsStringType(const AType: TMyrASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkString)) or
            (AType = GetPrimitiveType(tkWString));
end;

function TMyrSemantics.IsPointerType(const AType: TMyrASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkPointer));
  // Also check for typed pointers (pointer to T)
  if not Result then
    Result := AType is TMyrPointerTypeNode;
  if (not Result) and (AType is TMyrTypeDeclNode) then
    Result := TMyrTypeDeclNode(AType).TypeDef is TMyrPointerTypeNode;
end;

function TMyrSemantics.DoCheckReturnPaths(const AList: TObjectList<TMyrASTNode>): Boolean;
var
  I: Integer;
  LNode: TMyrASTNode;
  LIf: TMyrIfNode;
begin
  Result := False;
  if (AList = nil) or (AList.Count = 0) then
    Exit;

  // Check last statement
  LNode := AList[AList.Count - 1];

  if LNode is TMyrReturnNode then
  begin
    Result := True;
    Exit;
  end;

  // If/else: all branches must return
  // (elsif is flattened into nested if/else by parser)
  if LNode is TMyrIfNode then
  begin
    LIf := TMyrIfNode(LNode);
    // Must have an else branch
    if (LIf.ElseBody = nil) or (LIf.ElseBody.Count = 0) then
      Exit;

    // Then branch must return
    if not DoCheckReturnPaths(LIf.ThenBody) then
      Exit;

    // Else branch must return (may contain nested if for elsif chains)
    Result := DoCheckReturnPaths(LIf.ElseBody);
    Exit;
  end;

  // Match with else arm: all arms must return
  if LNode is TMyrMatchNode then
  begin
    // Simplified: check if all arms return
    Result := True;
    for I := 0 to TMyrMatchNode(LNode).Arms.Count - 1 do
    begin
      if not DoCheckReturnPaths(TMyrMatchArmNode(TMyrMatchNode(LNode).Arms[I]).Body) then
      begin
        Result := False;
        Exit;
      end;
    end;
  end;
end;

end.
