{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  Myrissa.LSP - Language Server Protocol Implementation

  Implements the full LSP server over JSON-RPC 2.0 (stdin/stdout).
  Three layers:
    TMyrLSPDocument  - Holds source, runs compiler pipeline, queries enriched AST
    TMyrLSPService   - Pure logic, no JSON. Answers every LSP query
    TMyrLSPServer    - JSON-RPC framing and dispatch loop

  All LSP queries read directly from the semantically enriched AST.
  No parallel symbol table is maintained.

  Dependencies: StdApp.Base, Myrissa.Common, Myrissa.Lexer, Myrissa.Parser,
                Myrissa.AST, Myrissa.Semantics
===============================================================================}

unit Myrissa.LSP;

interface

uses
  WinApi.Windows,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.Rtti,
  StdApp.Base,
  Myrissa.Frontend;

type

  // Forward declarations
  TMyrLSPDocument = class;
  TMyrLSPService  = class;
  TMyrLSPServer   = class;

  { TMyrLSPPosition }
  TMyrLSPPosition = record
    Line: Integer;
    Character: Integer;
    procedure Clear();
    function ToJSON(): TJSONObject;
    class function FromJSON(const AObj: TJSONObject): TMyrLSPPosition; static;
  end;

  { TMyrLSPRange }
  TMyrLSPRange = record
    StartPos: TMyrLSPPosition;
    EndPos: TMyrLSPPosition;
    procedure Clear();
    function ToJSON(): TJSONObject;
    class function FromJSON(const AObj: TJSONObject): TMyrLSPRange; static;
    class function FromSourceRange(const ARange: TSourceRange): TMyrLSPRange; static;
  end;

  { TMyrLSPLocation }
  TMyrLSPLocation = record
    Uri: string;
    Range: TMyrLSPRange;
    function IsEmpty(): Boolean;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPDiagnosticRelated }
  TMyrLSPDiagnosticRelated = record
    Location: TMyrLSPLocation;
    Message: string;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPDiagnostic }
  TMyrLSPDiagnostic = record
    Range: TMyrLSPRange;
    Severity: Integer;
    Code: string;
    Source: string;
    Message: string;
    Related: TArray<TMyrLSPDiagnosticRelated>;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPCompletionItem }
  TMyrLSPCompletionItem = record
    LabelText: string;
    Kind: Integer;
    Detail: string;
    Documentation: string;
    InsertText: string;
    InsertTextFormat: Integer;
    SortText: string;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPParameterInfo }
  TMyrLSPParameterInfo = record
    LabelText: string;
    Documentation: string;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPSignatureInfo }
  TMyrLSPSignatureInfo = record
    LabelText: string;
    Documentation: string;
    Parameters: TArray<TMyrLSPParameterInfo>;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPSignatureHelp }
  TMyrLSPSignatureHelp = record
    Signatures: TArray<TMyrLSPSignatureInfo>;
    ActiveSignature: Integer;
    ActiveParameter: Integer;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPHover }
  TMyrLSPHover = record
    Contents: string;
    Range: TMyrLSPRange;
    HasRange: Boolean;
    function IsEmpty(): Boolean;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPDocumentSymbol }
  TMyrLSPDocumentSymbol = record
    SymbolName: string;
    Detail: string;
    Kind: Integer;
    Range: TMyrLSPRange;
    SelectionRange: TMyrLSPRange;
    Children: TArray<TMyrLSPDocumentSymbol>;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPFoldingRange }
  TMyrLSPFoldingRange = record
    StartLine: Integer;
    EndLine: Integer;
    Kind: string;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPInlayHint }
  TMyrLSPInlayHint = record
    Position: TMyrLSPPosition;
    LabelText: string;
    Kind: Integer;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPTextEdit }
  TMyrLSPTextEdit = record
    Range: TMyrLSPRange;
    NewText: string;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPWorkspaceEdit }
  TMyrLSPWorkspaceEdit = record
    Uri: string;
    Edits: TArray<TMyrLSPTextEdit>;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPSymbolInformation }
  TMyrLSPSymbolInformation = record
    SymbolName: string;
    Kind: Integer;
    Uri: string;
    Range: TMyrLSPRange;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPCallHierarchyItem }
  TMyrLSPCallHierarchyItem = record
    ItemName: string;
    Kind: Integer;
    Uri: string;
    Range: TMyrLSPRange;
    SelectionRange: TMyrLSPRange;
    function ToJSON(): TJSONObject;
  end;

  { TMyrLSPCallHierarchyCall }
  TMyrLSPCallHierarchyCall = record
    Item: TMyrLSPCallHierarchyItem;
    FromRanges: TArray<TMyrLSPRange>;
    function ToJSON(const ADirection: string): TJSONObject;
  end;

  { TMyrLSPDocument }
  TMyrLSPDocument = class(TBaseObject)
  private
    FUri: string;
    FContent: string;
    FVersion: Integer;
    FLines: TStringList;
    FMasterAST: TMyrMasterAST;
    FParser: TMyrParser;
    FSemantics: TMyrSemantics;

    procedure UpdateLines();

  public
    constructor Create(); override;
    destructor Destroy(); override;

    function GetUri(): string;
    procedure SetUri(const AValue: string);
    function GetContent(): string;
    procedure SetContent(const AValue: string);
    function GetVersion(): Integer;
    procedure SetVersion(const AValue: Integer);

    procedure Parse();

    function GetMasterAST(): TMyrMasterAST;
    function GetModule(): TMyrModuleNode;
    function GetTokens(): TList<TMyrToken>;

    function OffsetToPosition(const AOffset: Integer): TMyrLSPPosition;
    function PositionToOffset(const APosition: TMyrLSPPosition): Integer;
    function GetLineCount(): Integer;
    function GetLine(const AIndex: Integer): string;

    function FindNodeAtPosition(const APosition: TMyrLSPPosition): TMyrASTNode;
    function FindCallAtPosition(const APosition: TMyrLSPPosition): TMyrCallExprNode;
  end;

  { TMyrLSPService }
  TMyrLSPService = class(TBaseObject)
  private
    FDocuments: TObjectDictionary<string, TMyrLSPDocument>;
    FLexer: TMyrLexer;  // keyword registry for completions

    function GetDocument(const AUri: string): TMyrLSPDocument;

    function TypeRefToString(const ANode: TMyrASTNode): string;
    function BuildSignatureString(const ARoutine: TMyrRoutineDeclNode): string;
    function BuildSnippetInsertText(const AName: string;
      const ARoutine: TMyrRoutineDeclNode): string;
    function DeclToCompletionKind(const ANode: TMyrASTNode): Integer;
    function DeclToSymbolKind(const ANode: TMyrASTNode): Integer;

    function GetKeywordCompletions(): TArray<TMyrLSPCompletionItem>;
    function GetBuiltinTypeCompletions(): TArray<TMyrLSPCompletionItem>;

    procedure WalkASTForReferences(const ANode: TMyrASTNode;
      const ATarget: TMyrASTNode; const AUri: string;
      var ALocations: TArray<TMyrLSPLocation>);
    procedure WalkChildren(const ANode: TMyrASTNode;
      const ATarget: TMyrASTNode; const AUri: string;
      var ALocations: TArray<TMyrLSPLocation>);
    procedure WalkListForReferences(const AList: TObjectList<TMyrASTNode>;
      const ATarget: TMyrASTNode; const AUri: string;
      var ALocations: TArray<TMyrLSPLocation>);

  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure OpenDocument(const AUri: string; const AContent: string);
    procedure UpdateDocument(const AUri: string; const AContent: string;
      const AVersion: Integer);
    procedure CloseDocument(const AUri: string);
    function HasDocument(const AUri: string): Boolean;

    function GetDiagnostics(const AUri: string): TArray<TMyrLSPDiagnostic>;
    function GetCompletions(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TArray<TMyrLSPCompletionItem>;
    function GetHover(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TMyrLSPHover;
    function GetDefinition(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TMyrLSPLocation;
    function GetTypeDefinition(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TMyrLSPLocation;
    function GetReferences(const AUri: string; const ALine: Integer;
      const ACharacter: Integer;
      const AIncludeDeclaration: Boolean): TArray<TMyrLSPLocation>;
    function GetDocumentSymbols(
      const AUri: string): TArray<TMyrLSPDocumentSymbol>;
    function GetSignatureHelp(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TMyrLSPSignatureHelp;
    function GetFoldingRanges(
      const AUri: string): TArray<TMyrLSPFoldingRange>;
    function GetSemanticTokens(const AUri: string): TArray<Integer>;
    function GetInlayHints(const AUri: string; const AStartLine: Integer;
      const AStartChar: Integer; const AEndLine: Integer;
      const AEndChar: Integer): TArray<TMyrLSPInlayHint>;
    function GetRenameEdits(const AUri: string; const ALine: Integer;
      const ACharacter: Integer;
      const ANewName: string): TMyrLSPWorkspaceEdit;
    function GetWorkspaceSymbols(const AQuery: string;
      const AUri: string): TArray<TMyrLSPSymbolInformation>;
    function PrepareCallHierarchy(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TArray<TMyrLSPCallHierarchyItem>;
    function GetIncomingCalls(const AUri: string;
      const AName: string): TArray<TMyrLSPCallHierarchyCall>;
    function GetOutgoingCalls(const AUri: string;
      const AName: string): TArray<TMyrLSPCallHierarchyCall>;
    function GetDocumentFormatting(const AUri: string; const ATabSize: Integer;
      const AInsertSpaces: Boolean): TArray<TMyrLSPTextEdit>;

    class function FilePathToUri(const APath: string): string; static;
    class function UriToFilePath(const AUri: string): string; static;
    class function ErrorSeverityToLSPSeverity(
      const ASeverity: TErrorSeverity): Integer; static;
  end;

  { TMyrLSPServer }
  TMyrLSPServer = class(TBaseObject)
  private
    FService: TMyrLSPService;
    FInitialized: Boolean;
    FShutdownRequested: Boolean;
    FRunning: Boolean;
    FExitCode: DWORD;
    FLogEnabled: Boolean;
    FInputStream: TStream;
    FOutputStream: TStream;
    FOwnsStreams: Boolean;

    procedure Log(const AMsg: string);

    function ReadMessage(): TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
    procedure SendResponse(const AId: TJSONValue; const AResult: TJSONValue);
    procedure SendError(const AId: TJSONValue; const ACode: Integer;
      const AMessage: string);
    procedure SendNotification(const AMethod: string;
      const AParams: TJSONValue);

    procedure DispatchMessage(const AMessage: TJSONObject);
    procedure PublishDiagnostics(const AUri: string);

    procedure HandleInitialize(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleShutdown(const AId: TJSONValue);
    procedure HandleTextDocumentCompletion(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentHover(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentDefinition(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentTypeDefinition(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentReferences(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentDocumentSymbol(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentSignatureHelp(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentFoldingRange(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentSemanticTokensFull(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentFormatting(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentCodeAction(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentInlayHint(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentRename(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleWorkspaceSymbol(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentPrepareCallHierarchy(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleCallHierarchyIncomingCalls(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleCallHierarchyOutgoingCalls(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleInitialized(const AParams: TJSONObject);
    procedure HandleExit();
    procedure HandleTextDocumentDidOpen(const AParams: TJSONObject);
    procedure HandleTextDocumentDidChange(const AParams: TJSONObject);
    procedure HandleTextDocumentDidClose(const AParams: TJSONObject);

  public
    constructor Create(); override;
    destructor Destroy(); override;

    function Run(): DWORD;
    procedure SetStreams(const AInput: TStream; const AOutput: TStream);
    function GetService(): TMyrLSPService;
    property LogEnabled: Boolean read FLogEnabled write FLogEnabled;
  end;

implementation

uses
  Myrissa.Common;

{ TMyrLSPPosition }
procedure TMyrLSPPosition.Clear();
begin
  Line := 0;
  Character := 0;
end;

function TMyrLSPPosition.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('line', TJSONNumber.Create(Line));
  Result.AddPair('character', TJSONNumber.Create(Character));
end;

class function TMyrLSPPosition.FromJSON(
  const AObj: TJSONObject): TMyrLSPPosition;
begin
  Result.Line := AObj.GetValue<Integer>('line', 0);
  Result.Character := AObj.GetValue<Integer>('character', 0);
end;

{ TMyrLSPRange }
procedure TMyrLSPRange.Clear();
begin
  StartPos.Clear();
  EndPos.Clear();
end;

function TMyrLSPRange.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('start', StartPos.ToJSON());
  Result.AddPair('end', EndPos.ToJSON());
end;

class function TMyrLSPRange.FromJSON(
  const AObj: TJSONObject): TMyrLSPRange;
var
  LStart: TJSONObject;
  LEnd: TJSONObject;
begin
  Result.Clear();
  LStart := AObj.GetValue<TJSONObject>('start', nil);
  if LStart <> nil then
    Result.StartPos := TMyrLSPPosition.FromJSON(LStart);
  LEnd := AObj.GetValue<TJSONObject>('end', nil);
  if LEnd <> nil then
    Result.EndPos := TMyrLSPPosition.FromJSON(LEnd);
end;

class function TMyrLSPRange.FromSourceRange(
  const ARange: TSourceRange): TMyrLSPRange;
begin
  // LSP is 0-based; Myrissa source ranges are 1-based
  Result.StartPos.Line := Max(0, Integer(ARange.StartLine) - 1);
  Result.StartPos.Character := Max(0, Integer(ARange.StartColumn) - 1);
  Result.EndPos.Line := Max(0, Integer(ARange.EndLine) - 1);
  Result.EndPos.Character := Max(0, Integer(ARange.EndColumn) - 1);
end;

{ TMyrLSPLocation }
function TMyrLSPLocation.IsEmpty(): Boolean;
begin
  Result := Uri = '';
end;

function TMyrLSPLocation.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('uri', Uri);
  Result.AddPair('range', Range.ToJSON());
end;

{ TMyrLSPDiagnosticRelated }
function TMyrLSPDiagnosticRelated.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('location', Location.ToJSON());
  Result.AddPair('message', Message);
end;

{ TMyrLSPDiagnostic }
function TMyrLSPDiagnostic.ToJSON(): TJSONObject;
var
  LRelatedArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair('range', Range.ToJSON());
  Result.AddPair('severity', TJSONNumber.Create(Severity));
  if Code <> '' then
    Result.AddPair('code', Code);
  if Source <> '' then
    Result.AddPair('source', Source);
  Result.AddPair('message', Message);
  if Length(Related) > 0 then
  begin
    LRelatedArray := TJSONArray.Create();
    for LI := 0 to High(Related) do
      LRelatedArray.AddElement(Related[LI].ToJSON());
    Result.AddPair('relatedInformation', LRelatedArray);
  end;
end;

{ TMyrLSPCompletionItem }
function TMyrLSPCompletionItem.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('label', LabelText);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
  if Detail <> '' then
    Result.AddPair('detail', Detail);
  if Documentation <> '' then
    Result.AddPair('documentation', Documentation);
  if InsertText <> '' then
    Result.AddPair('insertText', InsertText);
  if InsertTextFormat <> 0 then
    Result.AddPair('insertTextFormat', TJSONNumber.Create(InsertTextFormat));
  if SortText <> '' then
    Result.AddPair('sortText', SortText);
end;

{ TMyrLSPParameterInfo }
function TMyrLSPParameterInfo.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('label', LabelText);
  if Documentation <> '' then
    Result.AddPair('documentation', Documentation);
end;

{ TMyrLSPSignatureInfo }
function TMyrLSPSignatureInfo.ToJSON(): TJSONObject;
var
  LParamsArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair('label', LabelText);
  if Documentation <> '' then
    Result.AddPair('documentation', Documentation);
  if Length(Parameters) > 0 then
  begin
    LParamsArray := TJSONArray.Create();
    for LI := 0 to High(Parameters) do
      LParamsArray.AddElement(Parameters[LI].ToJSON());
    Result.AddPair('parameters', LParamsArray);
  end;
end;

{ TMyrLSPSignatureHelp }
function TMyrLSPSignatureHelp.ToJSON(): TJSONObject;
var
  LSigsArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  LSigsArray := TJSONArray.Create();
  for LI := 0 to High(Signatures) do
    LSigsArray.AddElement(Signatures[LI].ToJSON());
  Result.AddPair('signatures', LSigsArray);
  Result.AddPair('activeSignature', TJSONNumber.Create(ActiveSignature));
  Result.AddPair('activeParameter', TJSONNumber.Create(ActiveParameter));
end;

{ TMyrLSPHover }
function TMyrLSPHover.IsEmpty(): Boolean;
begin
  Result := Contents = '';
end;

function TMyrLSPHover.ToJSON(): TJSONObject;
var
  LContents: TJSONObject;
begin
  Result := TJSONObject.Create();
  LContents := TJSONObject.Create();
  LContents.AddPair('kind', 'markdown');
  LContents.AddPair('value', Contents);
  Result.AddPair('contents', LContents);
  if HasRange then
    Result.AddPair('range', Range.ToJSON());
end;

{ TMyrLSPDocumentSymbol }
function TMyrLSPDocumentSymbol.ToJSON(): TJSONObject;
var
  LChildArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair('name', SymbolName);
  if Detail <> '' then
    Result.AddPair('detail', Detail);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
  Result.AddPair('range', Range.ToJSON());
  Result.AddPair('selectionRange', SelectionRange.ToJSON());
  if Length(Children) > 0 then
  begin
    LChildArray := TJSONArray.Create();
    for LI := 0 to High(Children) do
      LChildArray.AddElement(Children[LI].ToJSON());
    Result.AddPair('children', LChildArray);
  end;
end;

{ TMyrLSPFoldingRange }
function TMyrLSPFoldingRange.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('startLine', TJSONNumber.Create(StartLine));
  Result.AddPair('endLine', TJSONNumber.Create(EndLine));
  if Kind <> '' then
    Result.AddPair('kind', Kind);
end;

{ TMyrLSPInlayHint }
function TMyrLSPInlayHint.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('position', Position.ToJSON());
  Result.AddPair('label', LabelText);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
end;

{ TMyrLSPTextEdit }
function TMyrLSPTextEdit.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('range', Range.ToJSON());
  Result.AddPair('newText', NewText);
end;

{ TMyrLSPWorkspaceEdit }
function TMyrLSPWorkspaceEdit.ToJSON(): TJSONObject;
var
  LEditsArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair('uri', Uri);
  LEditsArray := TJSONArray.Create();
  for LI := 0 to High(Edits) do
    LEditsArray.AddElement(Edits[LI].ToJSON());
  Result.AddPair('edits', LEditsArray);
end;

{ TMyrLSPSymbolInformation }
function TMyrLSPSymbolInformation.ToJSON(): TJSONObject;
var
  LLocation: TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('name', SymbolName);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
  LLocation := TJSONObject.Create();
  LLocation.AddPair('uri', Uri);
  LLocation.AddPair('range', Range.ToJSON());
  Result.AddPair('location', LLocation);
end;

{ TMyrLSPCallHierarchyItem }
function TMyrLSPCallHierarchyItem.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('name', ItemName);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
  Result.AddPair('uri', Uri);
  Result.AddPair('range', Range.ToJSON());
  Result.AddPair('selectionRange', SelectionRange.ToJSON());
end;

{ TMyrLSPCallHierarchyCall }
function TMyrLSPCallHierarchyCall.ToJSON(
  const ADirection: string): TJSONObject;
var
  LRangesArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair(ADirection, Item.ToJSON());
  LRangesArray := TJSONArray.Create();
  for LI := 0 to High(FromRanges) do
    LRangesArray.AddElement(FromRanges[LI].ToJSON());
  Result.AddPair('fromRanges', LRangesArray);
end;

{ TMyrLSPDocument }
constructor TMyrLSPDocument.Create();
begin
  inherited Create();

  FUri := '';
  FContent := '';
  FVersion := 0;
  FLines := TStringList.Create();
  FMasterAST := nil;
  FParser := nil;
  FSemantics := nil;
end;

destructor TMyrLSPDocument.Destroy();
begin
  FreeAndNil(FSemantics);
  FreeAndNil(FMasterAST);
  FreeAndNil(FParser);
  FreeAndNil(FLines);

  inherited Destroy();
end;

procedure TMyrLSPDocument.UpdateLines();
begin
  FLines.Clear();
  FLines.Text := FContent;
end;

function TMyrLSPDocument.GetUri(): string;
begin
  Result := FUri;
end;

procedure TMyrLSPDocument.SetUri(const AValue: string);
begin
  FUri := AValue;
end;

function TMyrLSPDocument.GetContent(): string;
begin
  Result := FContent;
end;

procedure TMyrLSPDocument.SetContent(const AValue: string);
begin
  FContent := AValue;
end;

function TMyrLSPDocument.GetVersion(): Integer;
begin
  Result := FVersion;
end;

procedure TMyrLSPDocument.SetVersion(const AValue: Integer);
begin
  FVersion := AValue;
end;

procedure TMyrLSPDocument.Parse();
var
  LModule: TMyrModuleNode;
begin
  // Free previous results
  FreeAndNil(FSemantics);
  FreeAndNil(FMasterAST);
  FreeAndNil(FParser);

  FErrors.Clear();
  FErrors.SetMaxErrors(100);

  FMasterAST := TMyrMasterAST.Create();

  // Parse phase
  FParser := TMyrParser.Create();
  FParser.SetErrors(FErrors);

  LModule := FParser.ParseModuleFromString(FContent, FUri, FMasterAST);
  if LModule <> nil then
  begin
    FMasterAST.AddModule(LModule);

    // Semantic phase (only when parse succeeded without errors)
    if not FErrors.HasErrors() then
    begin
      FSemantics := TMyrSemantics.Create();
      FSemantics.SetErrors(FErrors);
      FErrors.RaiseOnError := True;
      try
        FSemantics.Analyze(FMasterAST);
      except
        on EStdAppException do; // errors collected, continue
      end;
      FErrors.RaiseOnError := False;
    end;
  end;

  UpdateLines();
end;

function TMyrLSPDocument.GetMasterAST(): TMyrMasterAST;
begin
  Result := FMasterAST;
end;

function TMyrLSPDocument.GetModule(): TMyrModuleNode;
begin
  if (FMasterAST <> nil) and (FMasterAST.ModuleCount() > 0) then
    Result := FMasterAST.GetModuleAt(0)
  else
    Result := nil;
end;

function TMyrLSPDocument.GetTokens(): TList<TMyrToken>;
begin
  if (FParser <> nil) and (FParser.Lexer <> nil) then
    Result := FParser.Lexer.GetTokens()
  else
    Result := nil;
end;

function TMyrLSPDocument.OffsetToPosition(
  const AOffset: Integer): TMyrLSPPosition;
var
  LLine: Integer;
  LPos: Integer;
  LLineLen: Integer;
begin
  Result.Clear();
  LPos := 0;
  LLine := 0;

  while LLine < FLines.Count do
  begin
    LLineLen := Length(FLines[LLine]) + 1;
    if LPos + LLineLen > AOffset then
    begin
      Result.Line := LLine;
      Result.Character := AOffset - LPos;
      Exit;
    end;
    LPos := LPos + LLineLen;
    Inc(LLine);
  end;

  if FLines.Count > 0 then
  begin
    Result.Line := FLines.Count - 1;
    Result.Character := Length(FLines[FLines.Count - 1]);
  end;
end;

function TMyrLSPDocument.PositionToOffset(
  const APosition: TMyrLSPPosition): Integer;
var
  LLine: Integer;
  LI: Integer;
begin
  LLine := 0;
  LI := 1;

  while LI <= Length(FContent) do
  begin
    if LLine = APosition.Line then
    begin
      Result := LI - 1 + APosition.Character;
      Exit;
    end;
    if FContent[LI] = #13 then
    begin
      Inc(LLine);
      Inc(LI);
      if (LI <= Length(FContent)) and (FContent[LI] = #10) then
        Inc(LI);
    end
    else if FContent[LI] = #10 then
    begin
      Inc(LLine);
      Inc(LI);
    end
    else
      Inc(LI);
  end;

  if LLine = APosition.Line then
    Result := Length(FContent) + APosition.Character
  else
    Result := Length(FContent);
end;

function TMyrLSPDocument.GetLineCount(): Integer;
begin
  Result := FLines.Count;
end;

function TMyrLSPDocument.GetLine(const AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FLines.Count) then
    Result := FLines[AIndex]
  else
    Result := '';
end;

function TMyrLSPDocument.FindNodeAtPosition(
  const APosition: TMyrLSPPosition): TMyrASTNode;

  function ContainsPos(const ARange: TSourceRange): Boolean;
  var
    LLine: UInt64;
    LChar: UInt64;
  begin
    LLine := UInt64(APosition.Line + 1);
    LChar := UInt64(APosition.Character + 1);
    if (LLine < ARange.StartLine) or (LLine > ARange.EndLine) then
      Exit(False);
    if ARange.StartLine = ARange.EndLine then
      Exit((LChar >= ARange.StartColumn) and (LChar <= ARange.EndColumn));
    if LLine = ARange.StartLine then
      Result := LChar >= ARange.StartColumn
    else if LLine = ARange.EndLine then
      Result := LChar <= ARange.EndColumn
    else
      Result := True;
  end;

  function SearchInList(const AList: TObjectList<TMyrASTNode>): TMyrASTNode; forward;

  function SearchNode(const ANode: TMyrASTNode): TMyrASTNode;
  var
    LFound: TMyrASTNode;
    LI: Integer;
  begin
    Result := nil;
    if ANode = nil then Exit;
    if ANode.Location.IsEmpty() then Exit;
    if not ContainsPos(ANode.Location) then Exit;

    // Try children first -- deepest match wins
    if ANode is TMyrModuleNode then
    begin
      LFound := SearchInList(TMyrModuleNode(ANode).Declarations);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrModuleNode(ANode).InitBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrModuleNode(ANode).FinalBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrModuleNode(ANode).MainBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrRoutineDeclNode then
    begin
      for LI := 0 to TMyrRoutineDeclNode(ANode).Params.Count - 1 do
      begin
        LFound := SearchNode(TMyrRoutineDeclNode(ANode).Params[LI]);
        if LFound <> nil then Exit(LFound);
      end;
      LFound := SearchNode(TMyrRoutineDeclNode(ANode).ReturnType);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrRoutineDeclNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrVarDeclNode then
    begin
      LFound := SearchNode(TMyrVarDeclNode(ANode).TypeExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrVarDeclNode(ANode).InitExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrConstDeclNode then
    begin
      LFound := SearchNode(TMyrConstDeclNode(ANode).TypeExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrConstDeclNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrTypeDeclNode then
    begin
      LFound := SearchNode(TMyrTypeDeclNode(ANode).TypeDef);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrBinaryExprNode then
    begin
      LFound := SearchNode(TMyrBinaryExprNode(ANode).Left);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrBinaryExprNode(ANode).Right);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrUnaryExprNode then
    begin
      LFound := SearchNode(TMyrUnaryExprNode(ANode).Operand);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrCallExprNode then
    begin
      LFound := SearchNode(TMyrCallExprNode(ANode).Callee);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrCallExprNode(ANode).Args);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrCallStmtNode then
    begin
      LFound := SearchNode(TMyrCallStmtNode(ANode).CallExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrDotAccessNode then
    begin
      LFound := SearchNode(TMyrDotAccessNode(ANode).BaseExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrIndexAccessNode then
    begin
      LFound := SearchNode(TMyrIndexAccessNode(ANode).BaseExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrIndexAccessNode(ANode).IndexExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrDerefNode then
    begin
      LFound := SearchNode(TMyrDerefNode(ANode).BaseExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrAssignNode then
    begin
      LFound := SearchNode(TMyrAssignNode(ANode).Target);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrAssignNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrIfNode then
    begin
      LFound := SearchNode(TMyrIfNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrIfNode(ANode).ThenBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrIfNode(ANode).ElseBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrWhileNode then
    begin
      LFound := SearchNode(TMyrWhileNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrWhileNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrForNode then
    begin
      LFound := SearchNode(TMyrForNode(ANode).StartExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrForNode(ANode).EndExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrForNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrRepeatNode then
    begin
      LFound := SearchInList(TMyrRepeatNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrRepeatNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrReturnNode then
    begin
      LFound := SearchNode(TMyrReturnNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrGuardNode then
    begin
      LFound := SearchInList(TMyrGuardNode(ANode).GuardBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrGuardNode(ANode).ExceptBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrGuardNode(ANode).FinallyBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrMatchNode then
    begin
      LFound := SearchNode(TMyrMatchNode(ANode).Expr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrTypeCastExprNode then
    begin
      LFound := SearchNode(TMyrTypeCastExprNode(ANode).Expr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrRecordTypeNode then
    begin
      LFound := SearchInList(TMyrRecordTypeNode(ANode).Fields);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrPrintNode then
    begin
      LFound := SearchInList(TMyrPrintNode(ANode).Args);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrTestBlockNode then
    begin
      LFound := SearchInList(TMyrTestBlockNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end;

    // No child matched -- this node is the deepest match
    Result := ANode;
  end;

  function SearchInList(const AList: TObjectList<TMyrASTNode>): TMyrASTNode;
  var
    LI: Integer;
    LFound: TMyrASTNode;
  begin
    Result := nil;
    if AList = nil then Exit;
    for LI := 0 to AList.Count - 1 do
    begin
      LFound := SearchNode(AList[LI]);
      if LFound <> nil then
        Exit(LFound);
    end;
  end;

var
  LModule: TMyrModuleNode;
begin
  Result := nil;
  LModule := GetModule();
  if LModule <> nil then
    Result := SearchNode(LModule);
end;

function TMyrLSPDocument.FindCallAtPosition(
  const APosition: TMyrLSPPosition): TMyrCallExprNode;

  function ContainsPos(const ARange: TSourceRange): Boolean;
  var
    LLine: UInt64;
    LChar: UInt64;
  begin
    LLine := UInt64(APosition.Line + 1);
    LChar := UInt64(APosition.Character + 1);
    if (LLine < ARange.StartLine) or (LLine > ARange.EndLine) then
      Exit(False);
    if ARange.StartLine = ARange.EndLine then
      Exit((LChar >= ARange.StartColumn) and (LChar <= ARange.EndColumn));
    if LLine = ARange.StartLine then
      Result := LChar >= ARange.StartColumn
    else if LLine = ARange.EndLine then
      Result := LChar <= ARange.EndColumn
    else
      Result := True;
  end;

  function SearchInList(const AList: TObjectList<TMyrASTNode>): TMyrCallExprNode; forward;

  function SearchNode(const ANode: TMyrASTNode): TMyrCallExprNode;
  var
    LFound: TMyrCallExprNode;
  begin
    Result := nil;
    if ANode = nil then Exit;
    if ANode.Location.IsEmpty() then Exit;
    if not ContainsPos(ANode.Location) then Exit;

    // If this IS a call expression, return it (don't descend into args)
    if ANode is TMyrCallExprNode then
      Exit(TMyrCallExprNode(ANode));

    // Try children -- looking for a call
    if ANode is TMyrModuleNode then
    begin
      LFound := SearchInList(TMyrModuleNode(ANode).Declarations);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrModuleNode(ANode).InitBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrModuleNode(ANode).FinalBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrModuleNode(ANode).MainBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrRoutineDeclNode then
    begin
      LFound := SearchInList(TMyrRoutineDeclNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrCallStmtNode then
    begin
      LFound := SearchNode(TMyrCallStmtNode(ANode).CallExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrAssignNode then
    begin
      LFound := SearchNode(TMyrAssignNode(ANode).Target);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrAssignNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrBinaryExprNode then
    begin
      LFound := SearchNode(TMyrBinaryExprNode(ANode).Left);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrBinaryExprNode(ANode).Right);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrUnaryExprNode then
    begin
      LFound := SearchNode(TMyrUnaryExprNode(ANode).Operand);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrIfNode then
    begin
      LFound := SearchNode(TMyrIfNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrIfNode(ANode).ThenBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrIfNode(ANode).ElseBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrWhileNode then
    begin
      LFound := SearchNode(TMyrWhileNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrWhileNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrForNode then
    begin
      LFound := SearchNode(TMyrForNode(ANode).StartExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TMyrForNode(ANode).EndExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TMyrForNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrReturnNode then
    begin
      LFound := SearchNode(TMyrReturnNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TMyrVarDeclNode then
    begin
      LFound := SearchNode(TMyrVarDeclNode(ANode).InitExpr);
      if LFound <> nil then Exit(LFound);
    end;
  end;

  function SearchInList(const AList: TObjectList<TMyrASTNode>): TMyrCallExprNode;
  var
    LI: Integer;
    LFound: TMyrCallExprNode;
  begin
    Result := nil;
    if AList = nil then Exit;
    for LI := 0 to AList.Count - 1 do
    begin
      LFound := SearchNode(AList[LI]);
      if LFound <> nil then
        Exit(LFound);
    end;
  end;

var
  LModule: TMyrModuleNode;
begin
  Result := nil;
  LModule := GetModule();
  if LModule <> nil then
    Result := SearchNode(LModule);
end;

{ TMyrLSPService }
constructor TMyrLSPService.Create();
begin
  inherited Create();

  FDocuments := TObjectDictionary<string, TMyrLSPDocument>.Create([doOwnsValues]);
  FLexer := TMyrLexer.Create();
end;

destructor TMyrLSPService.Destroy();
begin
  FreeAndNil(FLexer);
  FreeAndNil(FDocuments);

  inherited Destroy();
end;

function TMyrLSPService.GetDocument(
  const AUri: string): TMyrLSPDocument;
begin
  if not FDocuments.TryGetValue(AUri, Result) then
    Result := nil;
end;

procedure TMyrLSPService.OpenDocument(const AUri: string;
  const AContent: string);
var
  LDoc: TMyrLSPDocument;
begin
  LDoc := TMyrLSPDocument.Create();
  LDoc.SetUri(AUri);
  LDoc.SetContent(AContent);
  LDoc.SetVersion(1);
  LDoc.Parse();
  FDocuments.AddOrSetValue(AUri, LDoc);
end;

procedure TMyrLSPService.UpdateDocument(const AUri: string;
  const AContent: string; const AVersion: Integer);
var
  LDoc: TMyrLSPDocument;
begin
  LDoc := GetDocument(AUri);
  if LDoc = nil then
  begin
    OpenDocument(AUri, AContent);
    Exit;
  end;
  LDoc.SetContent(AContent);
  LDoc.SetVersion(AVersion);
  LDoc.Parse();
end;

procedure TMyrLSPService.CloseDocument(const AUri: string);
begin
  FDocuments.Remove(AUri);
end;

function TMyrLSPService.HasDocument(const AUri: string): Boolean;
begin
  Result := FDocuments.ContainsKey(AUri);
end;

function TMyrLSPService.TypeRefToString(const ANode: TMyrASTNode): string;
begin
  Result := '';
  if ANode = nil then Exit;

  if ANode is TMyrTypeDeclNode then
    Result := TMyrTypeDeclNode(ANode).DeclName
  else if ANode is TMyrTypeRefNode then
  begin
    if TMyrTypeRefNode(ANode).TokenKind <> tkIdentifier then
      Result := TMyrTypeRefNode(ANode).CppTypeText  // primitive
    else if Length(TMyrTypeRefNode(ANode).QualParts) > 0 then
      Result := String.Join('.', TMyrTypeRefNode(ANode).QualParts)
    else
      Result := '?';
  end
  else if ANode is TMyrArrayTypeNode then
    Result := 'array of ' + TypeRefToString(TMyrArrayTypeNode(ANode).ElementType)
  else if ANode is TMyrPointerTypeNode then
    Result := 'pointer to ' + TypeRefToString(TMyrPointerTypeNode(ANode).TargetType)
  else if ANode is TMyrSetTypeNode then
    Result := 'set of ' + TypeRefToString(TMyrSetTypeNode(ANode).ElementType)
  else if ANode is TMyrRecordTypeNode then
    Result := 'record'
  else if ANode is TMyrChoicesTypeNode then
    Result := 'choices'
  else if ANode is TMyrRoutineTypeNode then
    Result := 'routine type';
end;

function TMyrLSPService.BuildSignatureString(
  const ARoutine: TMyrRoutineDeclNode): string;
var
  LI: Integer;
  LParam: TMyrParamDeclNode;
  LParts: TStringBuilder;
begin
  Result := '';
  if ARoutine = nil then Exit;

  LParts := TStringBuilder.Create();
  try
    for LI := 0 to ARoutine.Params.Count - 1 do
    begin
      LParam := ARoutine.Params[LI];
      if LI > 0 then LParts.Append('; ');
      case LParam.ParamMode of
        pmVar: LParts.Append('var ');
        pmConst: LParts.Append('const ');
      end;
      LParts.Append(LParam.ParamName);
      if LParam.TypeExpr <> nil then
        LParts.Append(': ' + TypeRefToString(LParam.TypeExpr));
    end;

    if ARoutine.ReturnType <> nil then
      Result := '(' + LParts.ToString() + '): ' + TypeRefToString(ARoutine.ReturnType)
    else
      Result := '(' + LParts.ToString() + ')';
  finally
    LParts.Free();
  end;
end;

function TMyrLSPService.BuildSnippetInsertText(const AName: string;
  const ARoutine: TMyrRoutineDeclNode): string;
var
  LI: Integer;
  LParam: TMyrParamDeclNode;
  LParts: TStringBuilder;
begin
  Result := AName;
  if (ARoutine = nil) or (ARoutine.Params.Count = 0) then Exit;

  LParts := TStringBuilder.Create();
  try
    for LI := 0 to ARoutine.Params.Count - 1 do
    begin
      LParam := ARoutine.Params[LI];
      if LI > 0 then LParts.Append(', ');
      LParts.AppendFormat('${%d:%s}', [LI + 1, LParam.ParamName]);
    end;
    Result := AName + '(' + LParts.ToString() + ')';
  finally
    LParts.Free();
  end;
end;

function TMyrLSPService.DeclToCompletionKind(const ANode: TMyrASTNode): Integer;
begin
  if ANode is TMyrRoutineDeclNode then Result := 3       // Function
  else if ANode is TMyrOverloadGroupNode then Result := 3
  else if ANode is TMyrTypeDeclNode then Result := 7     // Class
  else if ANode is TMyrVarDeclNode then Result := 6      // Variable
  else if ANode is TMyrConstDeclNode then Result := 21   // Constant
  else if ANode is TMyrParamDeclNode then Result := 6    // Variable
  else if ANode is TMyrFieldDeclNode then Result := 5    // Field
  else if ANode is TMyrChoicesValueNode then Result := 20 // EnumMember
  else Result := 1;
end;

function TMyrLSPService.DeclToSymbolKind(const ANode: TMyrASTNode): Integer;
begin
  if ANode is TMyrRoutineDeclNode then Result := 12       // Function
  else if ANode is TMyrOverloadGroupNode then Result := 12
  else if ANode is TMyrTypeDeclNode then
  begin
    if TMyrTypeDeclNode(ANode).TypeDef is TMyrRecordTypeNode then
      Result := 23   // Struct
    else if TMyrTypeDeclNode(ANode).TypeDef is TMyrChoicesTypeNode then
      Result := 10   // Enum
    else
      Result := 5;   // Class
  end
  else if ANode is TMyrVarDeclNode then Result := 13      // Variable
  else if ANode is TMyrConstDeclNode then Result := 14    // Constant
  else if ANode is TMyrFieldDeclNode then Result := 8     // Field
  else Result := 1;
end;

class function TMyrLSPService.ErrorSeverityToLSPSeverity(
  const ASeverity: TErrorSeverity): Integer;
begin
  case ASeverity of
    esHint:    Result := 4;
    esWarning: Result := 2;
    esError:   Result := 1;
    esFatal:   Result := 1;
  else
    Result := 1;
  end;
end;

class function TMyrLSPService.FilePathToUri(const APath: string): string;
var
  LNormalized: string;
begin
  LNormalized := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Result := 'file:///' + LNormalized;
end;

class function TMyrLSPService.UriToFilePath(const AUri: string): string;
begin
  Result := AUri;
  if Result.StartsWith('file:///') then
    Result := Copy(Result, 9, MaxInt);
  Result := StringReplace(Result, '/', PathDelim, [rfReplaceAll]);
end;

function TMyrLSPService.GetKeywordCompletions(): TArray<TMyrLSPCompletionItem>;
var
  LWords: TArray<string>;
  LI: Integer;
  LItem: TMyrLSPCompletionItem;
begin
  LWords := FLexer.GetRegisteredWords(tcKeyword);
  SetLength(Result, Length(LWords));
  for LI := 0 to High(LWords) do
  begin
    LItem.LabelText := LWords[LI];
    LItem.Kind := 14;  // Keyword
    LItem.Detail := 'keyword';
    LItem.Documentation := '';
    LItem.InsertText := LWords[LI];
    LItem.InsertTextFormat := 1;
    LItem.SortText := '9' + LWords[LI];
    Result[LI] := LItem;
  end;
end;

function TMyrLSPService.GetBuiltinTypeCompletions(): TArray<TMyrLSPCompletionItem>;
var
  LWords: TArray<string>;
  LI: Integer;
  LItem: TMyrLSPCompletionItem;
begin
  LWords := FLexer.GetRegisteredWords(tcPrimitive);
  SetLength(Result, Length(LWords));
  for LI := 0 to High(LWords) do
  begin
    LItem.LabelText := LWords[LI];
    LItem.Kind := 7;   // Class (type)
    LItem.Detail := 'built-in type';
    LItem.Documentation := '';
    LItem.InsertText := LWords[LI];
    LItem.InsertTextFormat := 1;
    LItem.SortText := '8' + LWords[LI];
    Result[LI] := LItem;
  end;
end;

function TMyrLSPService.GetDiagnostics(
  const AUri: string): TArray<TMyrLSPDiagnostic>;
var
  LDoc: TMyrLSPDocument;
  LItems: TList<TError>;
  LI: Integer;
  LJ: Integer;
  LError: TError;
  LDiag: TMyrLSPDiagnostic;
  LRelated: TMyrLSPDiagnosticRelated;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  if LDoc.GetErrors() = nil then Exit;

  LItems := LDoc.GetErrors().GetItems();
  SetLength(Result, LItems.Count);
  for LI := 0 to LItems.Count - 1 do
  begin
    LError := LItems[LI];
    LDiag.Range := TMyrLSPRange.FromSourceRange(LError.Range);
    LDiag.Severity := ErrorSeverityToLSPSeverity(LError.Severity);
    LDiag.Code := LError.Code;
    LDiag.Source := 'myrissa';
    LDiag.Message := LError.Message;
    SetLength(LDiag.Related, Length(LError.Related));
    for LJ := 0 to High(LError.Related) do
    begin
      LRelated.Location.Uri := AUri;
      LRelated.Location.Range := TMyrLSPRange.FromSourceRange(
        LError.Related[LJ].Range);
      LRelated.Message := LError.Related[LJ].Msg;
      LDiag.Related[LJ] := LRelated;
    end;
    Result[LI] := LDiag;
  end;
end;

function TMyrLSPService.GetHover(const AUri: string; const ALine: Integer;
  const ACharacter: Integer): TMyrLSPHover;
var
  LDoc: TMyrLSPDocument;
  LPosition: TMyrLSPPosition;
  LNode: TMyrASTNode;
  LDecl: TMyrASTNode;
  LContent: string;
begin
  Result.Contents := '';
  Result.HasRange := False;

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  // Resolve the declaration this node points to
  LDecl := nil;
  if LNode is TMyrIdentifierNode then
    LDecl := TMyrIdentifierNode(LNode).ResolvedDecl
  else if LNode is TMyrDotAccessNode then
    LDecl := TMyrDotAccessNode(LNode).ResolvedDecl
  else if (LNode is TMyrDeclNode) or (LNode is TMyrFieldDeclNode) or
          (LNode is TMyrParamDeclNode) or (LNode is TMyrChoicesValueNode) then
    LDecl := LNode;

  if LDecl <> nil then
  begin
    if LDecl is TMyrRoutineDeclNode then
    begin
      LContent := '```myrissa' + #10;
      LContent := LContent + 'routine ' + TMyrRoutineDeclNode(LDecl).DeclName;
      LContent := LContent + BuildSignatureString(TMyrRoutineDeclNode(LDecl));
      LContent := LContent + #10 + '```';
    end
    else if LDecl is TMyrOverloadGroupNode then
    begin
      LContent := '```myrissa' + #10;
      LContent := LContent + 'routine ' + TMyrOverloadGroupNode(LDecl).DeclName;
      LContent := LContent + ' (overloaded, ' +
        IntToStr(TMyrOverloadGroupNode(LDecl).Overloads.Count) + ' variants)';
      LContent := LContent + #10 + '```';
    end
    else if LDecl is TMyrTypeDeclNode then
      LContent := '**type** `' + TMyrTypeDeclNode(LDecl).DeclName + '`'
    else if LDecl is TMyrVarDeclNode then
    begin
      LContent := '**var** `' + TMyrVarDeclNode(LDecl).DeclName + '`';
      if TMyrVarDeclNode(LDecl).TypeExpr <> nil then
        LContent := LContent + ': `' + TypeRefToString(TMyrVarDeclNode(LDecl).TypeExpr) + '`';
    end
    else if LDecl is TMyrConstDeclNode then
      LContent := '**const** `' + TMyrConstDeclNode(LDecl).DeclName + '`'
    else if LDecl is TMyrParamDeclNode then
    begin
      LContent := '**param** `' + TMyrParamDeclNode(LDecl).ParamName + '`';
      if TMyrParamDeclNode(LDecl).TypeExpr <> nil then
        LContent := LContent + ': `' + TypeRefToString(TMyrParamDeclNode(LDecl).TypeExpr) + '`';
    end
    else if LDecl is TMyrFieldDeclNode then
    begin
      LContent := '**field** `' + TMyrFieldDeclNode(LDecl).FieldName + '`';
      if TMyrFieldDeclNode(LDecl).TypeExpr <> nil then
        LContent := LContent + ': `' + TypeRefToString(TMyrFieldDeclNode(LDecl).TypeExpr) + '`';
    end
    else if LDecl is TMyrChoicesValueNode then
      LContent := '**choices value** `' + TMyrChoicesValueNode(LDecl).MemberName + '`'
    else if LDecl is TMyrDeclNode then
      LContent := '`' + TMyrDeclNode(LDecl).DeclName + '`'
    else
      LContent := '';

    if LContent <> '' then
    begin
      Result.Contents := LContent;
      Result.Range := TMyrLSPRange.FromSourceRange(LNode.Location);
      Result.HasRange := True;
      Exit;
    end;
  end;

  // Fallback: show resolved type for expressions
  if (LNode is TMyrExprNode) and (TMyrExprNode(LNode).ResolvedType <> nil) then
  begin
    Result.Contents := '`' + TypeRefToString(TMyrExprNode(LNode).ResolvedType) + '`';
    Result.Range := TMyrLSPRange.FromSourceRange(LNode.Location);
    Result.HasRange := True;
    Exit;
  end;

  // Literal fallbacks
  if LNode is TMyrIntLiteralNode then
    Result.Contents := '**integer** `' + IntToStr(TMyrIntLiteralNode(LNode).IntValue) + '`'
  else if LNode is TMyrFloatLiteralNode then
    Result.Contents := '**float** `' + FloatToStr(TMyrFloatLiteralNode(LNode).FloatValue) + '`'
  else if LNode is TMyrStringLiteralNode then
    Result.Contents := '**string**'
  else if LNode is TMyrBoolLiteralNode then
  begin
    if TMyrBoolLiteralNode(LNode).BoolValue then
      Result.Contents := '**boolean** `true`'
    else
      Result.Contents := '**boolean** `false`';
  end
  else if LNode is TMyrNilLiteralNode then
    Result.Contents := '**nil**';
end;

function TMyrLSPService.GetDefinition(const AUri: string;
  const ALine: Integer; const ACharacter: Integer): TMyrLSPLocation;
var
  LDoc: TMyrLSPDocument;
  LPosition: TMyrLSPPosition;
  LNode: TMyrASTNode;
  LDecl: TMyrASTNode;
begin
  Result.Uri := '';
  Result.Range.Clear();

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  LDecl := nil;
  if LNode is TMyrIdentifierNode then
    LDecl := TMyrIdentifierNode(LNode).ResolvedDecl
  else if LNode is TMyrDotAccessNode then
    LDecl := TMyrDotAccessNode(LNode).ResolvedDecl
  else if LNode is TMyrCallExprNode then
    LDecl := TMyrCallExprNode(LNode).ResolvedRoutine;

  if (LDecl <> nil) and (not LDecl.Location.IsEmpty()) then
  begin
    Result.Uri := AUri;
    Result.Range := TMyrLSPRange.FromSourceRange(LDecl.Location);
  end;
end;

function TMyrLSPService.GetTypeDefinition(const AUri: string;
  const ALine: Integer; const ACharacter: Integer): TMyrLSPLocation;
var
  LDoc: TMyrLSPDocument;
  LPosition: TMyrLSPPosition;
  LNode: TMyrASTNode;
  LType: TMyrASTNode;
begin
  Result.Uri := '';
  Result.Range.Clear();

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  LType := nil;
  if LNode is TMyrExprNode then
    LType := TMyrExprNode(LNode).ResolvedType;

  if (LType <> nil) and (not LType.Location.IsEmpty()) then
  begin
    Result.Uri := AUri;
    Result.Range := TMyrLSPRange.FromSourceRange(LType.Location);
  end;
end;

function TMyrLSPService.GetCompletions(const AUri: string;
  const ALine: Integer;
  const ACharacter: Integer): TArray<TMyrLSPCompletionItem>;
var
  LDoc: TMyrLSPDocument;
  LModule: TMyrModuleNode;
  LI: Integer;
  LDecl: TMyrASTNode;
  LItem: TMyrLSPCompletionItem;
  LKeywords: TArray<TMyrLSPCompletionItem>;
  LBuiltins: TArray<TMyrLSPCompletionItem>;
begin
  SetLength(Result, 0);

  LDoc := GetDocument(AUri);
  LModule := nil;
  if LDoc <> nil then
    LModule := LDoc.GetModule();

  // Walk module declarations for completion items
  if LModule <> nil then
  begin
    for LI := 0 to LModule.Declarations.Count - 1 do
    begin
      LDecl := LModule.Declarations[LI];
      if not (LDecl is TMyrDeclNode) then Continue;
      if TMyrDeclNode(LDecl).DeclName = '' then Continue;

      LItem.LabelText := TMyrDeclNode(LDecl).DeclName;
      LItem.Kind := DeclToCompletionKind(LDecl);
      LItem.SortText := '1' + TMyrDeclNode(LDecl).DeclName;
      LItem.InsertTextFormat := 1;
      LItem.Documentation := '';
      LItem.Detail := '';

      if LDecl is TMyrRoutineDeclNode then
      begin
        LItem.InsertText := BuildSnippetInsertText(
          TMyrDeclNode(LDecl).DeclName, TMyrRoutineDeclNode(LDecl));
        LItem.InsertTextFormat := 2;
        LItem.Detail := BuildSignatureString(TMyrRoutineDeclNode(LDecl));
      end
      else if LDecl is TMyrVarDeclNode then
      begin
        LItem.InsertText := TMyrDeclNode(LDecl).DeclName;
        if TMyrVarDeclNode(LDecl).TypeExpr <> nil then
          LItem.Detail := TypeRefToString(TMyrVarDeclNode(LDecl).TypeExpr);
      end
      else
        LItem.InsertText := TMyrDeclNode(LDecl).DeclName;

      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LItem;
    end;
  end;

  // Always include keywords and builtin types
  LKeywords := GetKeywordCompletions();
  for LI := 0 to High(LKeywords) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LKeywords[LI];
  end;

  LBuiltins := GetBuiltinTypeCompletions();
  for LI := 0 to High(LBuiltins) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LBuiltins[LI];
  end;
end;

procedure TMyrLSPService.WalkASTForReferences(const ANode: TMyrASTNode;
  const ATarget: TMyrASTNode; const AUri: string;
  var ALocations: TArray<TMyrLSPLocation>);
var
  LLocation: TMyrLSPLocation;
begin
  if ANode = nil then Exit;

  // Check if this node references the target
  if (ANode is TMyrIdentifierNode) and
     (TMyrIdentifierNode(ANode).ResolvedDecl = ATarget) then
  begin
    LLocation.Uri := AUri;
    LLocation.Range := TMyrLSPRange.FromSourceRange(ANode.Location);
    SetLength(ALocations, Length(ALocations) + 1);
    ALocations[High(ALocations)] := LLocation;
  end
  else if (ANode is TMyrDotAccessNode) and
          (TMyrDotAccessNode(ANode).ResolvedDecl = ATarget) then
  begin
    LLocation.Uri := AUri;
    LLocation.Range := TMyrLSPRange.FromSourceRange(ANode.Location);
    SetLength(ALocations, Length(ALocations) + 1);
    ALocations[High(ALocations)] := LLocation;
  end;

  // Recurse into children
  WalkChildren(ANode, ATarget, AUri, ALocations);
end;

procedure TMyrLSPService.WalkChildren(const ANode: TMyrASTNode;
  const ATarget: TMyrASTNode; const AUri: string;
  var ALocations: TArray<TMyrLSPLocation>);
var
  LI: Integer;
begin
  if ANode is TMyrModuleNode then
  begin
    WalkListForReferences(TMyrModuleNode(ANode).Declarations, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrModuleNode(ANode).InitBody, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrModuleNode(ANode).FinalBody, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrModuleNode(ANode).MainBody, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrRoutineDeclNode then
  begin
    for LI := 0 to TMyrRoutineDeclNode(ANode).Params.Count - 1 do
      WalkASTForReferences(TMyrRoutineDeclNode(ANode).Params[LI], ATarget, AUri, ALocations);
    WalkASTForReferences(TMyrRoutineDeclNode(ANode).ReturnType, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrRoutineDeclNode(ANode).Body, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrBinaryExprNode then
  begin
    WalkASTForReferences(TMyrBinaryExprNode(ANode).Left, ATarget, AUri, ALocations);
    WalkASTForReferences(TMyrBinaryExprNode(ANode).Right, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrUnaryExprNode then
    WalkASTForReferences(TMyrUnaryExprNode(ANode).Operand, ATarget, AUri, ALocations)
  else if ANode is TMyrCallExprNode then
  begin
    WalkASTForReferences(TMyrCallExprNode(ANode).Callee, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrCallExprNode(ANode).Args, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrCallStmtNode then
    WalkASTForReferences(TMyrCallStmtNode(ANode).CallExpr, ATarget, AUri, ALocations)
  else if ANode is TMyrDotAccessNode then
    WalkASTForReferences(TMyrDotAccessNode(ANode).BaseExpr, ATarget, AUri, ALocations)
  else if ANode is TMyrIndexAccessNode then
  begin
    WalkASTForReferences(TMyrIndexAccessNode(ANode).BaseExpr, ATarget, AUri, ALocations);
    WalkASTForReferences(TMyrIndexAccessNode(ANode).IndexExpr, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrAssignNode then
  begin
    WalkASTForReferences(TMyrAssignNode(ANode).Target, ATarget, AUri, ALocations);
    WalkASTForReferences(TMyrAssignNode(ANode).ValueExpr, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrIfNode then
  begin
    WalkASTForReferences(TMyrIfNode(ANode).Condition, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrIfNode(ANode).ThenBody, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrIfNode(ANode).ElseBody, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrWhileNode then
  begin
    WalkASTForReferences(TMyrWhileNode(ANode).Condition, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrWhileNode(ANode).Body, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrForNode then
  begin
    WalkASTForReferences(TMyrForNode(ANode).StartExpr, ATarget, AUri, ALocations);
    WalkASTForReferences(TMyrForNode(ANode).EndExpr, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrForNode(ANode).Body, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrRepeatNode then
  begin
    WalkListForReferences(TMyrRepeatNode(ANode).Body, ATarget, AUri, ALocations);
    WalkASTForReferences(TMyrRepeatNode(ANode).Condition, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrReturnNode then
    WalkASTForReferences(TMyrReturnNode(ANode).ValueExpr, ATarget, AUri, ALocations)
  else if ANode is TMyrGuardNode then
  begin
    WalkListForReferences(TMyrGuardNode(ANode).GuardBody, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrGuardNode(ANode).ExceptBody, ATarget, AUri, ALocations);
    WalkListForReferences(TMyrGuardNode(ANode).FinallyBody, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrVarDeclNode then
  begin
    WalkASTForReferences(TMyrVarDeclNode(ANode).TypeExpr, ATarget, AUri, ALocations);
    WalkASTForReferences(TMyrVarDeclNode(ANode).InitExpr, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrConstDeclNode then
  begin
    WalkASTForReferences(TMyrConstDeclNode(ANode).TypeExpr, ATarget, AUri, ALocations);
    WalkASTForReferences(TMyrConstDeclNode(ANode).ValueExpr, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrTypeDeclNode then
    WalkASTForReferences(TMyrTypeDeclNode(ANode).TypeDef, ATarget, AUri, ALocations)
  else if ANode is TMyrPrintNode then
  begin
    WalkListForReferences(TMyrPrintNode(ANode).Args, ATarget, AUri, ALocations);
  end
  else if ANode is TMyrDerefNode then
    WalkASTForReferences(TMyrDerefNode(ANode).BaseExpr, ATarget, AUri, ALocations)
  else if ANode is TMyrTypeCastExprNode then
    WalkASTForReferences(TMyrTypeCastExprNode(ANode).Expr, ATarget, AUri, ALocations)
  else if ANode is TMyrTestBlockNode then
    WalkListForReferences(TMyrTestBlockNode(ANode).Body, ATarget, AUri, ALocations)
  else if ANode is TMyrRecordTypeNode then
    WalkListForReferences(TMyrRecordTypeNode(ANode).Fields, ATarget, AUri, ALocations);
end;

procedure TMyrLSPService.WalkListForReferences(
  const AList: TObjectList<TMyrASTNode>;
  const ATarget: TMyrASTNode; const AUri: string;
  var ALocations: TArray<TMyrLSPLocation>);
var
  LI: Integer;
begin
  if AList = nil then Exit;
  for LI := 0 to AList.Count - 1 do
    WalkASTForReferences(AList[LI], ATarget, AUri, ALocations);
end;

function TMyrLSPService.GetReferences(const AUri: string;
  const ALine: Integer; const ACharacter: Integer;
  const AIncludeDeclaration: Boolean): TArray<TMyrLSPLocation>;
var
  LDoc: TMyrLSPDocument;
  LPosition: TMyrLSPPosition;
  LNode: TMyrASTNode;
  LTarget: TMyrASTNode;
  LLocation: TMyrLSPLocation;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  // Find the declaration this node refers to
  LTarget := nil;
  if LNode is TMyrIdentifierNode then
    LTarget := TMyrIdentifierNode(LNode).ResolvedDecl
  else if LNode is TMyrDotAccessNode then
    LTarget := TMyrDotAccessNode(LNode).ResolvedDecl
  else if LNode is TMyrDeclNode then
    LTarget := LNode;  // cursor is on the declaration itself
  if LTarget = nil then Exit;

  // Include the declaration itself
  if AIncludeDeclaration and (not LTarget.Location.IsEmpty()) then
  begin
    LLocation.Uri := AUri;
    LLocation.Range := TMyrLSPRange.FromSourceRange(LTarget.Location);
    SetLength(Result, 1);
    Result[0] := LLocation;
  end;

  // Walk entire AST for references
  if LDoc.GetModule() <> nil then
    WalkASTForReferences(LDoc.GetModule(), LTarget, AUri, Result);
end;

function TMyrLSPService.GetDocumentSymbols(
  const AUri: string): TArray<TMyrLSPDocumentSymbol>;
var
  LDoc: TMyrLSPDocument;
  LModule: TMyrModuleNode;
  LI: Integer;
  LDecl: TMyrASTNode;
  LSym: TMyrLSPDocumentSymbol;

  function BuildDocSymbol(const ADecl: TMyrASTNode): TMyrLSPDocumentSymbol;
  var
    LJ: Integer;
    LChildSym: TMyrLSPDocumentSymbol;
    LField: TMyrASTNode;
    LTypeDef: TMyrASTNode;
  begin
    if ADecl is TMyrDeclNode then
      Result.SymbolName := TMyrDeclNode(ADecl).DeclName
    else if ADecl is TMyrFieldDeclNode then
      Result.SymbolName := TMyrFieldDeclNode(ADecl).FieldName
    else
      Result.SymbolName := '?';

    Result.Detail := '';
    Result.Kind := DeclToSymbolKind(ADecl);
    Result.Range := TMyrLSPRange.FromSourceRange(ADecl.Location);
    Result.SelectionRange := Result.Range;
    SetLength(Result.Children, 0);

    // Recurse into record fields
    if ADecl is TMyrTypeDeclNode then
    begin
      LTypeDef := TMyrTypeDeclNode(ADecl).TypeDef;
      if LTypeDef is TMyrRecordTypeNode then
      begin
        for LJ := 0 to TMyrRecordTypeNode(LTypeDef).Fields.Count - 1 do
        begin
          LField := TMyrRecordTypeNode(LTypeDef).Fields[LJ];
          if LField is TMyrFieldDeclNode then
          begin
            LChildSym := BuildDocSymbol(LField);
            SetLength(Result.Children, Length(Result.Children) + 1);
            Result.Children[High(Result.Children)] := LChildSym;
          end;
        end;
      end
      else if LTypeDef is TMyrChoicesTypeNode then
      begin
        for LJ := 0 to TMyrChoicesTypeNode(LTypeDef).Members.Count - 1 do
        begin
          LChildSym.SymbolName := TMyrChoicesTypeNode(LTypeDef).Members[LJ].MemberName;
          LChildSym.Kind := 22;  // EnumMember
          LChildSym.Detail := '';
          LChildSym.Range := TMyrLSPRange.FromSourceRange(
            TMyrChoicesTypeNode(LTypeDef).Members[LJ].Location);
          LChildSym.SelectionRange := LChildSym.Range;
          SetLength(LChildSym.Children, 0);
          SetLength(Result.Children, Length(Result.Children) + 1);
          Result.Children[High(Result.Children)] := LChildSym;
        end;
      end;
    end
    // Recurse into routine params
    else if ADecl is TMyrRoutineDeclNode then
    begin
      Result.Detail := BuildSignatureString(TMyrRoutineDeclNode(ADecl));
    end;
  end;

begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;

  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if not (LDecl is TMyrDeclNode) then Continue;
    if TMyrDeclNode(LDecl).DeclName = '' then Continue;

    LSym := BuildDocSymbol(LDecl);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LSym;
  end;
end;

function TMyrLSPService.GetSignatureHelp(const AUri: string;
  const ALine: Integer;
  const ACharacter: Integer): TMyrLSPSignatureHelp;
var
  LDoc: TMyrLSPDocument;
  LPosition: TMyrLSPPosition;
  LCallNode: TMyrCallExprNode;
  LRoutine: TMyrRoutineDeclNode;
  LI: Integer;
  LSig: TMyrLSPSignatureInfo;
  LParam: TMyrLSPParameterInfo;
begin
  SetLength(Result.Signatures, 0);
  Result.ActiveSignature := 0;
  Result.ActiveParameter := 0;

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;

  // Find enclosing call expression (stops at call, doesn't descend into args)
  LCallNode := LDoc.FindCallAtPosition(LPosition);
  if LCallNode = nil then Exit;

  LRoutine := nil;
  if LCallNode.ResolvedRoutine is TMyrRoutineDeclNode then
    LRoutine := TMyrRoutineDeclNode(LCallNode.ResolvedRoutine);
  if LRoutine = nil then Exit;

  LSig.LabelText := LRoutine.DeclName + BuildSignatureString(LRoutine);
  LSig.Documentation := '';
  SetLength(LSig.Parameters, LRoutine.Params.Count);
  for LI := 0 to LRoutine.Params.Count - 1 do
  begin
    LParam.LabelText := LRoutine.Params[LI].ParamName;
    if LRoutine.Params[LI].TypeExpr <> nil then
      LParam.LabelText := LParam.LabelText + ': ' +
        TypeRefToString(LRoutine.Params[LI].TypeExpr);
    LParam.Documentation := '';
    LSig.Parameters[LI] := LParam;
  end;

  SetLength(Result.Signatures, 1);
  Result.Signatures[0] := LSig;
end;

function TMyrLSPService.GetFoldingRanges(
  const AUri: string): TArray<TMyrLSPFoldingRange>;

  procedure CollectBodyFolding(const ABody: TObjectList<TMyrASTNode>;
    var ARanges: TArray<TMyrLSPFoldingRange>); forward;

  procedure CollectFolding(const ANode: TMyrASTNode;
    var ARanges: TArray<TMyrLSPFoldingRange>);
  var
    LRange: TMyrLSPFoldingRange;
    LStartLine: Integer;
    LEndLine: Integer;
    LI: Integer;
  begin
    if ANode = nil then Exit;
    if ANode.Location.IsEmpty() then Exit;

    LStartLine := Integer(ANode.Location.StartLine) - 1;
    LEndLine := Integer(ANode.Location.EndLine) - 1;

    // Only add if it spans multiple lines
    if LEndLine > LStartLine then
    begin
      if (ANode is TMyrRoutineDeclNode) or (ANode is TMyrIfNode) or
         (ANode is TMyrWhileNode) or (ANode is TMyrForNode) or
         (ANode is TMyrRepeatNode) or (ANode is TMyrMatchNode) or
         (ANode is TMyrGuardNode) or (ANode is TMyrTestBlockNode) or
         (ANode is TMyrRecordTypeNode) or (ANode is TMyrTypeDeclNode) then
      begin
        LRange.StartLine := LStartLine;
        LRange.EndLine := LEndLine;
        LRange.Kind := 'region';
        SetLength(ARanges, Length(ARanges) + 1);
        ARanges[High(ARanges)] := LRange;
      end;
    end;

    // Recurse
    if ANode is TMyrModuleNode then
    begin
      for LI := 0 to TMyrModuleNode(ANode).Declarations.Count - 1 do
        CollectFolding(TMyrModuleNode(ANode).Declarations[LI], ARanges);
      // Add folding for module body sections
      CollectBodyFolding(TMyrModuleNode(ANode).InitBody, ARanges);
      CollectBodyFolding(TMyrModuleNode(ANode).MainBody, ARanges);
      CollectBodyFolding(TMyrModuleNode(ANode).FinalBody, ARanges);
    end
    else if ANode is TMyrRoutineDeclNode then
    begin
      for LI := 0 to TMyrRoutineDeclNode(ANode).Body.Count - 1 do
        CollectFolding(TMyrRoutineDeclNode(ANode).Body[LI], ARanges);
    end;
  end;

  procedure CollectBodyFolding(const ABody: TObjectList<TMyrASTNode>;
    var ARanges: TArray<TMyrLSPFoldingRange>);
  var
    LFirst: TMyrASTNode;
    LLast: TMyrASTNode;
    LStartLine: Integer;
    LEndLine: Integer;
    LRange: TMyrLSPFoldingRange;
    LI: Integer;
  begin
    if (ABody = nil) or (ABody.Count = 0) then Exit;
    LFirst := ABody[0];
    LLast := ABody[ABody.Count - 1];
    if LFirst.Location.IsEmpty() or LLast.Location.IsEmpty() then Exit;
    // Use the line before the first statement (the begin keyword) as start
    LStartLine := Integer(LFirst.Location.StartLine) - 1 - 1;
    LEndLine := Integer(LLast.Location.EndLine) - 1;
    if LEndLine > LStartLine then
    begin
      LRange.StartLine := LStartLine;
      LRange.EndLine := LEndLine;
      LRange.Kind := 'region';
      SetLength(ARanges, Length(ARanges) + 1);
      ARanges[High(ARanges)] := LRange;
    end;
    // Recurse into body statements for nested blocks
    for LI := 0 to ABody.Count - 1 do
      CollectFolding(ABody[LI], ARanges);
  end;

var
  LDoc: TMyrLSPDocument;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  if LDoc.GetModule() = nil then Exit;
  CollectFolding(LDoc.GetModule(), Result);
end;

function TMyrLSPService.GetSemanticTokens(const AUri: string): TArray<Integer>;
var
  LDoc: TMyrLSPDocument;
  LTokens: TList<TMyrToken>;
  LI: Integer;
  LToken: TMyrToken;
  LPrevLine: Integer;
  LPrevChar: Integer;
  LLine: Integer;
  LChar: Integer;
  LDeltaLine: Integer;
  LDeltaChar: Integer;
  LLen: Integer;
  LTokenType: Integer;
  LList: TList<Integer>;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LTokens := LDoc.GetTokens();
  if LTokens = nil then Exit;

  LList := TList<Integer>.Create();
  try
    LPrevLine := 0;
    LPrevChar := 0;

    for LI := 0 to LTokens.Count - 1 do
    begin
      LToken := LTokens[LI];
      if LToken.Kind = tkEOF then Continue;

      // Map category to semantic token type
      // Types: 0=namespace, 1=type, 2=class, 3=enum, 4=interface,
      //        5=struct, 6=typeParameter, 7=parameter, 8=variable,
      //        9=property, 10=enumMember, 11=event, 12=function,
      //        13=method, 14=macro, 15=keyword, 16=modifier,
      //        17=comment, 18=string, 19=number, 20=regexp, 21=operator
      case LToken.Category of
        tcKeyword:    LTokenType := 15;
        tcPrimitive:  LTokenType := 1;
        tcOperator:   LTokenType := 21;
        tcLiteral:
        begin
          if LToken.Kind in [tkIntLiteral, tkFloatLiteral] then
            LTokenType := 19
          else
            LTokenType := 18;
        end;
        tcDirective:  LTokenType := 14;
        tcIdentifier: LTokenType := 8;  // default to variable
      else
        Continue;  // skip delimiters, etc.
      end;

      LLine := Integer(LToken.Location.StartLine) - 1;
      LChar := Integer(LToken.Location.StartColumn) - 1;
      LLen := Length(LToken.RawText);

      LDeltaLine := LLine - LPrevLine;
      if LDeltaLine = 0 then
        LDeltaChar := LChar - LPrevChar
      else
        LDeltaChar := LChar;

      LList.Add(LDeltaLine);
      LList.Add(LDeltaChar);
      LList.Add(LLen);
      LList.Add(LTokenType);
      LList.Add(0);  // modifiers

      LPrevLine := LLine;
      LPrevChar := LChar;
    end;

    SetLength(Result, LList.Count);
    for LI := 0 to LList.Count - 1 do
      Result[LI] := LList[LI];
  finally
    LList.Free();
  end;
end;

function TMyrLSPService.GetDocumentFormatting(const AUri: string;
  const ATabSize: Integer;
  const AInsertSpaces: Boolean): TArray<TMyrLSPTextEdit>;
var
  LDoc: TMyrLSPDocument;
  LTokens: TList<TMyrToken>;
  LI: Integer;
  LToken: TMyrToken;
  LEdit: TMyrLSPTextEdit;
  LCanonical: string;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LTokens := LDoc.GetTokens();
  if LTokens = nil then Exit;

  // Keyword casing: normalize keywords to lowercase canonical form
  for LI := 0 to LTokens.Count - 1 do
  begin
    LToken := LTokens[LI];
    if LToken.Kind = tkEOF then Continue;
    if LToken.Category <> tcKeyword then Continue;
    LCanonical := LToken.TokenText;  // TokenText is canonical (lowercased)
    if LToken.RawText <> LCanonical then
    begin
      LEdit.Range := TMyrLSPRange.FromSourceRange(LToken.Location);
      LEdit.NewText := LCanonical;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LEdit;
    end;
  end;

  // Trailing whitespace removal
  for LI := 0 to LDoc.GetLineCount() - 1 do
  begin
    LCanonical := LDoc.GetLine(LI);
    if (LCanonical <> '') and (LCanonical[Length(LCanonical)] <= ' ') then
    begin
      LEdit.Range.StartPos.Line := LI;
      LEdit.Range.StartPos.Character := Length(TrimRight(LCanonical));
      LEdit.Range.EndPos.Line := LI;
      LEdit.Range.EndPos.Character := Length(LCanonical);
      LEdit.NewText := '';
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LEdit;
    end;
  end;
end;

function TMyrLSPService.GetInlayHints(const AUri: string;
  const AStartLine: Integer; const AStartChar: Integer;
  const AEndLine: Integer;
  const AEndChar: Integer): TArray<TMyrLSPInlayHint>;
var
  LDoc: TMyrLSPDocument;
  LModule: TMyrModuleNode;

  procedure CollectInlayHints(const ANode: TMyrASTNode;
    var AHints: TArray<TMyrLSPInlayHint>);
  var
    LI: Integer;
    LHint: TMyrLSPInlayHint;
    LLine: Integer;
    LRoutine: TMyrRoutineDeclNode;
  begin
    if ANode = nil then Exit;

    // Parameter name hints on call expressions
    if ANode is TMyrCallExprNode then
    begin
      LRoutine := nil;
      if TMyrCallExprNode(ANode).ResolvedRoutine is TMyrRoutineDeclNode then
        LRoutine := TMyrRoutineDeclNode(TMyrCallExprNode(ANode).ResolvedRoutine);
      if (LRoutine <> nil) and (TMyrCallExprNode(ANode).Args.Count > 0) then
      begin
        for LI := 0 to Min(TMyrCallExprNode(ANode).Args.Count,
          LRoutine.Params.Count) - 1 do
        begin
          LLine := Integer(TMyrCallExprNode(ANode).Args[LI].Location.StartLine) - 1;
          if (LLine >= AStartLine) and (LLine <= AEndLine) then
          begin
            LHint.Position.Line := LLine;
            LHint.Position.Character :=
              Integer(TMyrCallExprNode(ANode).Args[LI].Location.StartColumn) - 1;
            LHint.LabelText := LRoutine.Params[LI].ParamName + ':';
            LHint.Kind := 2;  // Parameter
            SetLength(AHints, Length(AHints) + 1);
            AHints[High(AHints)] := LHint;
          end;
        end;
      end;
    end

    // Type hints on variable declarations without explicit type
    else if ANode is TMyrVarDeclNode then
    begin
      if (TMyrVarDeclNode(ANode).TypeExpr = nil) and
         (TMyrExprNode(ANode).ResolvedType <> nil) then
      begin
        LLine := Integer(ANode.Location.StartLine) - 1;
        if (LLine >= AStartLine) and (LLine <= AEndLine) then
        begin
          LHint.Position.Line := LLine;
          LHint.Position.Character := Integer(ANode.Location.EndColumn);
          LHint.LabelText := ': ' + TypeRefToString(TMyrExprNode(ANode).ResolvedType);
          LHint.Kind := 1;  // Type
          SetLength(AHints, Length(AHints) + 1);
          AHints[High(AHints)] := LHint;
        end;
      end;
    end;

    // Recurse
    if ANode is TMyrModuleNode then
    begin
      for LI := 0 to TMyrModuleNode(ANode).Declarations.Count - 1 do
        CollectInlayHints(TMyrModuleNode(ANode).Declarations[LI], AHints);
      for LI := 0 to TMyrModuleNode(ANode).MainBody.Count - 1 do
        CollectInlayHints(TMyrModuleNode(ANode).MainBody[LI], AHints);
      for LI := 0 to TMyrModuleNode(ANode).InitBody.Count - 1 do
        CollectInlayHints(TMyrModuleNode(ANode).InitBody[LI], AHints);
    end
    else if ANode is TMyrRoutineDeclNode then
    begin
      for LI := 0 to TMyrRoutineDeclNode(ANode).Body.Count - 1 do
        CollectInlayHints(TMyrRoutineDeclNode(ANode).Body[LI], AHints);
    end
    else if ANode is TMyrIfNode then
    begin
      CollectInlayHints(TMyrIfNode(ANode).Condition, AHints);
      for LI := 0 to TMyrIfNode(ANode).ThenBody.Count - 1 do
        CollectInlayHints(TMyrIfNode(ANode).ThenBody[LI], AHints);
      for LI := 0 to TMyrIfNode(ANode).ElseBody.Count - 1 do
        CollectInlayHints(TMyrIfNode(ANode).ElseBody[LI], AHints);
    end
    else if ANode is TMyrWhileNode then
    begin
      CollectInlayHints(TMyrWhileNode(ANode).Condition, AHints);
      for LI := 0 to TMyrWhileNode(ANode).Body.Count - 1 do
        CollectInlayHints(TMyrWhileNode(ANode).Body[LI], AHints);
    end
    else if ANode is TMyrForNode then
    begin
      for LI := 0 to TMyrForNode(ANode).Body.Count - 1 do
        CollectInlayHints(TMyrForNode(ANode).Body[LI], AHints);
    end
    else if ANode is TMyrCallStmtNode then
      CollectInlayHints(TMyrCallStmtNode(ANode).CallExpr, AHints)
    else if ANode is TMyrAssignNode then
      CollectInlayHints(TMyrAssignNode(ANode).ValueExpr, AHints);
  end;

begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;
  CollectInlayHints(LModule, Result);
end;

function TMyrLSPService.GetRenameEdits(const AUri: string;
  const ALine: Integer; const ACharacter: Integer;
  const ANewName: string): TMyrLSPWorkspaceEdit;
var
  LDoc: TMyrLSPDocument;
  LPosition: TMyrLSPPosition;
  LNode: TMyrASTNode;
  LTarget: TMyrASTNode;
  LLocations: TArray<TMyrLSPLocation>;
  LI: Integer;
  LEdit: TMyrLSPTextEdit;
begin
  Result.Uri := AUri;
  SetLength(Result.Edits, 0);

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  // Find what we're renaming
  LTarget := nil;
  if LNode is TMyrIdentifierNode then
    LTarget := TMyrIdentifierNode(LNode).ResolvedDecl
  else if LNode is TMyrDotAccessNode then
    LTarget := TMyrDotAccessNode(LNode).ResolvedDecl
  else if LNode is TMyrDeclNode then
    LTarget := LNode;
  if LTarget = nil then Exit;

  // Collect all references
  SetLength(LLocations, 0);

  // Include the declaration itself
  if not LTarget.Location.IsEmpty() then
  begin
    SetLength(LLocations, 1);
    LLocations[0].Uri := AUri;
    LLocations[0].Range := TMyrLSPRange.FromSourceRange(LTarget.Location);
  end;

  // Walk AST for all uses
  if LDoc.GetModule() <> nil then
    WalkASTForReferences(LDoc.GetModule(), LTarget, AUri, LLocations);

  // Convert locations to edits
  SetLength(Result.Edits, Length(LLocations));
  for LI := 0 to High(LLocations) do
  begin
    LEdit.Range := LLocations[LI].Range;
    LEdit.NewText := ANewName;
    Result.Edits[LI] := LEdit;
  end;
end;

function TMyrLSPService.GetWorkspaceSymbols(const AQuery: string;
  const AUri: string): TArray<TMyrLSPSymbolInformation>;
var
  LDoc: TMyrLSPDocument;
  LModule: TMyrModuleNode;
  LI: Integer;
  LDecl: TMyrASTNode;
  LInfo: TMyrLSPSymbolInformation;
  LName: string;
  LQueryLower: string;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;

  LQueryLower := LowerCase(AQuery);

  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if not (LDecl is TMyrDeclNode) then Continue;
    LName := TMyrDeclNode(LDecl).DeclName;
    if LName = '' then Continue;

    // Filter by query (empty query = return all)
    if (LQueryLower <> '') and (not LowerCase(LName).Contains(LQueryLower)) then
      Continue;

    LInfo.SymbolName := LName;
    LInfo.Kind := DeclToSymbolKind(LDecl);
    LInfo.Uri := AUri;
    LInfo.Range := TMyrLSPRange.FromSourceRange(LDecl.Location);

    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LInfo;
  end;
end;

function TMyrLSPService.PrepareCallHierarchy(const AUri: string;
  const ALine: Integer;
  const ACharacter: Integer): TArray<TMyrLSPCallHierarchyItem>;
var
  LDoc: TMyrLSPDocument;
  LPosition: TMyrLSPPosition;
  LNode: TMyrASTNode;
  LDecl: TMyrASTNode;
  LItem: TMyrLSPCallHierarchyItem;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  // Resolve to a routine declaration
  LDecl := nil;
  if LNode is TMyrIdentifierNode then
    LDecl := TMyrIdentifierNode(LNode).ResolvedDecl
  else if LNode is TMyrDotAccessNode then
    LDecl := TMyrDotAccessNode(LNode).ResolvedDecl
  else if LNode is TMyrRoutineDeclNode then
    LDecl := LNode;

  if not (LDecl is TMyrRoutineDeclNode) then Exit;

  LItem.ItemName := TMyrRoutineDeclNode(LDecl).DeclName;
  LItem.Kind := 12;  // Function
  LItem.Uri := AUri;
  LItem.Range := TMyrLSPRange.FromSourceRange(LDecl.Location);
  LItem.SelectionRange := LItem.Range;

  SetLength(Result, 1);
  Result[0] := LItem;
end;

function TMyrLSPService.GetIncomingCalls(const AUri: string;
  const AName: string): TArray<TMyrLSPCallHierarchyCall>;
var
  LDoc: TMyrLSPDocument;
  LModule: TMyrModuleNode;
  LI: Integer;
  LDecl: TMyrASTNode;
  LTarget: TMyrRoutineDeclNode;

  procedure FindCallsInRoutine(const ARoutine: TMyrRoutineDeclNode;
    const ATarget: TMyrRoutineDeclNode;
    var ACalls: TArray<TMyrLSPCallHierarchyCall>);
  var
    LLocations: TArray<TMyrLSPLocation>;
    LCall: TMyrLSPCallHierarchyCall;
  begin
    SetLength(LLocations, 0);
    WalkListForReferences(ARoutine.Body, ATarget, AUri, LLocations);
    if Length(LLocations) > 0 then
    begin
      LCall.Item.ItemName := ARoutine.DeclName;
      LCall.Item.Kind := 12;
      LCall.Item.Uri := AUri;
      LCall.Item.Range := TMyrLSPRange.FromSourceRange(ARoutine.Location);
      LCall.Item.SelectionRange := LCall.Item.Range;
      LCall.FromRanges := TArray<TMyrLSPRange>.Create(LLocations[0].Range);
      SetLength(ACalls, Length(ACalls) + 1);
      ACalls[High(ACalls)] := LCall;
    end;
  end;

begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;

  // Find the target routine by name
  LTarget := nil;
  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if (LDecl is TMyrRoutineDeclNode) and
       (TMyrRoutineDeclNode(LDecl).DeclName = AName) then
    begin
      LTarget := TMyrRoutineDeclNode(LDecl);
      Break;
    end;
  end;
  if LTarget = nil then Exit;

  // Search all routines for calls to the target
  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if (LDecl is TMyrRoutineDeclNode) and (LDecl <> LTarget) then
      FindCallsInRoutine(TMyrRoutineDeclNode(LDecl), LTarget, Result);
  end;
end;

function TMyrLSPService.GetOutgoingCalls(const AUri: string;
  const AName: string): TArray<TMyrLSPCallHierarchyCall>;
var
  LDoc: TMyrLSPDocument;
  LModule: TMyrModuleNode;
  LI: Integer;
  LDecl: TMyrASTNode;
  LSource: TMyrRoutineDeclNode;

  procedure CollectOutgoing(const ANode: TMyrASTNode;
    var ACalls: TArray<TMyrLSPCallHierarchyCall>);
  var
    LJ: Integer;
    LCallee: TMyrASTNode;
    LCall: TMyrLSPCallHierarchyCall;
  begin
    if ANode = nil then Exit;

    if ANode is TMyrCallExprNode then
    begin
      LCallee := TMyrCallExprNode(ANode).ResolvedRoutine;
      if (LCallee is TMyrRoutineDeclNode) then
      begin
        LCall.Item.ItemName := TMyrRoutineDeclNode(LCallee).DeclName;
        LCall.Item.Kind := 12;
        LCall.Item.Uri := AUri;
        LCall.Item.Range := TMyrLSPRange.FromSourceRange(LCallee.Location);
        LCall.Item.SelectionRange := LCall.Item.Range;
        LCall.FromRanges := TArray<TMyrLSPRange>.Create(
          TMyrLSPRange.FromSourceRange(ANode.Location));
        SetLength(ACalls, Length(ACalls) + 1);
        ACalls[High(ACalls)] := LCall;
      end;
    end
    else if ANode is TMyrCallStmtNode then
      CollectOutgoing(TMyrCallStmtNode(ANode).CallExpr, ACalls);

    // Recurse into children
    if ANode is TMyrRoutineDeclNode then
    begin
      for LJ := 0 to TMyrRoutineDeclNode(ANode).Body.Count - 1 do
        CollectOutgoing(TMyrRoutineDeclNode(ANode).Body[LJ], ACalls);
    end
    else if ANode is TMyrIfNode then
    begin
      CollectOutgoing(TMyrIfNode(ANode).Condition, ACalls);
      for LJ := 0 to TMyrIfNode(ANode).ThenBody.Count - 1 do
        CollectOutgoing(TMyrIfNode(ANode).ThenBody[LJ], ACalls);
      for LJ := 0 to TMyrIfNode(ANode).ElseBody.Count - 1 do
        CollectOutgoing(TMyrIfNode(ANode).ElseBody[LJ], ACalls);
    end
    else if ANode is TMyrWhileNode then
    begin
      CollectOutgoing(TMyrWhileNode(ANode).Condition, ACalls);
      for LJ := 0 to TMyrWhileNode(ANode).Body.Count - 1 do
        CollectOutgoing(TMyrWhileNode(ANode).Body[LJ], ACalls);
    end
    else if ANode is TMyrForNode then
    begin
      for LJ := 0 to TMyrForNode(ANode).Body.Count - 1 do
        CollectOutgoing(TMyrForNode(ANode).Body[LJ], ACalls);
    end
    else if ANode is TMyrAssignNode then
    begin
      CollectOutgoing(TMyrAssignNode(ANode).ValueExpr, ACalls);
    end
    else if ANode is TMyrReturnNode then
      CollectOutgoing(TMyrReturnNode(ANode).ValueExpr, ACalls)
    else if ANode is TMyrBinaryExprNode then
    begin
      CollectOutgoing(TMyrBinaryExprNode(ANode).Left, ACalls);
      CollectOutgoing(TMyrBinaryExprNode(ANode).Right, ACalls);
    end
    else if ANode is TMyrUnaryExprNode then
      CollectOutgoing(TMyrUnaryExprNode(ANode).Operand, ACalls);
  end;

begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;

  // Find the source routine by name
  LSource := nil;
  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if (LDecl is TMyrRoutineDeclNode) and
       (TMyrRoutineDeclNode(LDecl).DeclName = AName) then
    begin
      LSource := TMyrRoutineDeclNode(LDecl);
      Break;
    end;
  end;
  if LSource = nil then Exit;

  CollectOutgoing(LSource, Result);
end;

{ TMyrLSPServer }
constructor TMyrLSPServer.Create();
begin
  inherited Create();

  FService := TMyrLSPService.Create();
  FInitialized := False;
  FShutdownRequested := False;
  FInputStream := nil;
  FOutputStream := nil;
  FOwnsStreams := False;
end;

destructor TMyrLSPServer.Destroy();
begin
  FreeAndNil(FService);
  if FOwnsStreams then
  begin
    FreeAndNil(FInputStream);
    FreeAndNil(FOutputStream);
  end;

  inherited Destroy();
end;

procedure TMyrLSPServer.SetStreams(const AInput: TStream;
  const AOutput: TStream);
begin
  FInputStream := AInput;
  FOutputStream := AOutput;
end;

function TMyrLSPServer.GetService(): TMyrLSPService;
begin
  Result := FService;
end;

procedure TMyrLSPServer.Log(const AMsg: string);
begin
  if FLogEnabled then
    MyrLogStdErr('myrlsp: ' + AMsg);
end;

function TMyrLSPServer.ReadMessage(): TJSONObject;
var
  LHeader: string;
  LContentLength: Integer;
  LCh: AnsiChar;
  LBody: TBytes;
  LBodyStr: string;
begin
  Result := nil;
  LContentLength := -1;

  // Read headers (Content-Length: N\r\n\r\n)
  while True do
  begin
    LHeader := '';
    while True do
    begin
      if FInputStream.Read(LCh, 1) <> 1 then Exit;
      if LCh = #13 then
      begin
        if FInputStream.Read(LCh, 1) <> 1 then Exit;
        Break;
      end;
      LHeader := LHeader + Char(LCh);
    end;

    if LHeader = '' then Break;  // empty line = end of headers

    if LHeader.StartsWith('Content-Length:') then
      LContentLength := StrToIntDef(Trim(Copy(LHeader, 16, MaxInt)), -1);
  end;

  if LContentLength <= 0 then Exit;

  // Read body
  SetLength(LBody, LContentLength);
  if FInputStream.Read(LBody[0], LContentLength) <> LContentLength then Exit;

  LBodyStr := TEncoding.UTF8.GetString(LBody);
  try
    Result := TJSONObject.ParseJSONValue(LBodyStr) as TJSONObject;
  except
    Result := nil;
  end;
end;

procedure TMyrLSPServer.WriteMessage(const AMessage: TJSONObject);
var
  LBody: string;
  LBodyBytes: TBytes;
  LHeader: string;
  LHeaderBytes: TBytes;
begin
  LBody := AMessage.ToJSON();
  LBodyBytes := TEncoding.UTF8.GetBytes(LBody);
  LHeader := 'Content-Length: ' + IntToStr(Length(LBodyBytes)) + #13#10 + #13#10;
  LHeaderBytes := TEncoding.ASCII.GetBytes(LHeader);
  FOutputStream.Write(LHeaderBytes[0], Length(LHeaderBytes));
  FOutputStream.Write(LBodyBytes[0], Length(LBodyBytes));
end;

procedure TMyrLSPServer.SendResponse(const AId: TJSONValue;
  const AResult: TJSONValue);
var
  LMsg: TJSONObject;
begin
  LMsg := TJSONObject.Create();
  try
    LMsg.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      LMsg.AddPair('id', AId.Clone() as TJSONValue)
    else
      LMsg.AddPair('id', TJSONNull.Create());
    if AResult <> nil then
      LMsg.AddPair('result', AResult)
    else
      LMsg.AddPair('result', TJSONNull.Create());
    WriteMessage(LMsg);
  finally
    LMsg.Free();
  end;
end;

procedure TMyrLSPServer.SendError(const AId: TJSONValue;
  const ACode: Integer; const AMessage: string);
var
  LMsg: TJSONObject;
  LError: TJSONObject;
begin
  LMsg := TJSONObject.Create();
  try
    LMsg.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      LMsg.AddPair('id', AId.Clone() as TJSONValue)
    else
      LMsg.AddPair('id', TJSONNull.Create());
    LError := TJSONObject.Create();
    LError.AddPair('code', TJSONNumber.Create(ACode));
    LError.AddPair('message', AMessage);
    LMsg.AddPair('error', LError);
    WriteMessage(LMsg);
  finally
    LMsg.Free();
  end;
end;

procedure TMyrLSPServer.SendNotification(const AMethod: string;
  const AParams: TJSONValue);
var
  LMsg: TJSONObject;
begin
  LMsg := TJSONObject.Create();
  try
    LMsg.AddPair('jsonrpc', '2.0');
    LMsg.AddPair('method', AMethod);
    if AParams <> nil then
      LMsg.AddPair('params', AParams)
    else
      LMsg.AddPair('params', TJSONObject.Create());
    WriteMessage(LMsg);
  finally
    LMsg.Free();
  end;
end;

procedure TMyrLSPServer.PublishDiagnostics(const AUri: string);
var
  LDiags: TArray<TMyrLSPDiagnostic>;
  LParams: TJSONObject;
  LDiagArray: TJSONArray;
  LI: Integer;
begin
  LDiags := FService.GetDiagnostics(AUri);
  LParams := TJSONObject.Create();
  LParams.AddPair('uri', AUri);
  LDiagArray := TJSONArray.Create();
  for LI := 0 to High(LDiags) do
    LDiagArray.AddElement(LDiags[LI].ToJSON());
  LParams.AddPair('diagnostics', LDiagArray);
  SendNotification('textDocument/publishDiagnostics', LParams);
end;

procedure TMyrLSPServer.HandleInitialize(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LResult: TJSONObject;
  LCaps: TJSONObject;
  LTextSync: TJSONObject;
  LCompOpts: TJSONObject;
  LSigOpts: TJSONObject;
  LSigChars: TJSONArray;
  LSemanticOpts: TJSONObject;
  LLegend: TJSONObject;
  LTokenTypes: TJSONArray;
  LTokenMods: TJSONArray;
begin
  LResult := TJSONObject.Create();
  LCaps := TJSONObject.Create();

  // Text document sync: full document on every change
  LTextSync := TJSONObject.Create();
  LTextSync.AddPair('openClose', TJSONBool.Create(True));
  LTextSync.AddPair('change', TJSONNumber.Create(1));  // Full
  LCaps.AddPair('textDocumentSync', LTextSync);

  // Completion
  LCompOpts := TJSONObject.Create();
  LCompOpts.AddPair('resolveProvider', TJSONBool.Create(False));
  LCaps.AddPair('completionProvider', LCompOpts);

  // Hover
  LCaps.AddPair('hoverProvider', TJSONBool.Create(True));

  // Go to definition
  LCaps.AddPair('definitionProvider', TJSONBool.Create(True));

  // Go to type definition
  LCaps.AddPair('typeDefinitionProvider', TJSONBool.Create(True));

  // Find references
  LCaps.AddPair('referencesProvider', TJSONBool.Create(True));

  // Document symbols
  LCaps.AddPair('documentSymbolProvider', TJSONBool.Create(True));

  // Signature help
  LSigOpts := TJSONObject.Create();
  LSigChars := TJSONArray.Create();
  LSigChars.Add('(');
  LSigChars.Add(',');
  LSigOpts.AddPair('triggerCharacters', LSigChars);
  LCaps.AddPair('signatureHelpProvider', LSigOpts);

  // Folding
  LCaps.AddPair('foldingRangeProvider', TJSONBool.Create(True));

  // Semantic tokens
  LSemanticOpts := TJSONObject.Create();
  LLegend := TJSONObject.Create();
  LTokenTypes := TJSONArray.Create();
  LTokenTypes.Add('namespace');
  LTokenTypes.Add('type');
  LTokenTypes.Add('class');
  LTokenTypes.Add('enum');
  LTokenTypes.Add('interface');
  LTokenTypes.Add('struct');
  LTokenTypes.Add('typeParameter');
  LTokenTypes.Add('parameter');
  LTokenTypes.Add('variable');
  LTokenTypes.Add('property');
  LTokenTypes.Add('enumMember');
  LTokenTypes.Add('event');
  LTokenTypes.Add('function');
  LTokenTypes.Add('method');
  LTokenTypes.Add('macro');
  LTokenTypes.Add('keyword');
  LTokenTypes.Add('modifier');
  LTokenTypes.Add('comment');
  LTokenTypes.Add('string');
  LTokenTypes.Add('number');
  LTokenTypes.Add('regexp');
  LTokenTypes.Add('operator');
  LLegend.AddPair('tokenTypes', LTokenTypes);
  LTokenMods := TJSONArray.Create();
  LTokenMods.Add('declaration');
  LTokenMods.Add('definition');
  LLegend.AddPair('tokenModifiers', LTokenMods);
  LSemanticOpts.AddPair('legend', LLegend);
  LSemanticOpts.AddPair('full', TJSONBool.Create(True));
  LCaps.AddPair('semanticTokensProvider', LSemanticOpts);

  // Document formatting
  LCaps.AddPair('documentFormattingProvider', TJSONBool.Create(True));

  // Code action
  LCaps.AddPair('codeActionProvider', TJSONBool.Create(True));

  // Inlay hints
  LCaps.AddPair('inlayHintProvider', TJSONBool.Create(True));

  // Rename
  LCaps.AddPair('renameProvider', TJSONBool.Create(True));

  // Workspace symbol
  LCaps.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));

  // Call hierarchy
  LCaps.AddPair('callHierarchyProvider', TJSONBool.Create(True));

  LResult.AddPair('capabilities', LCaps);

  // Server info
  var LServerInfo := TJSONObject.Create();
  LServerInfo.AddPair('name', 'myrlsp');
  LServerInfo.AddPair('version', '0.1.0');
  LResult.AddPair('serverInfo', LServerInfo);

  SendResponse(AId, LResult);
  FInitialized := True;
end;

procedure TMyrLSPServer.HandleInitialized(const AParams: TJSONObject);
begin
  // Client is ready -- nothing to do
end;

procedure TMyrLSPServer.HandleShutdown(const AId: TJSONValue);
begin
  FShutdownRequested := True;
  Log('shutdown requested');
  SendResponse(AId, TJSONNull.Create());
end;

procedure TMyrLSPServer.HandleExit();
begin
  if FShutdownRequested then
    FExitCode := 0
  else
    FExitCode := 1;
  FRunning := False;
end;

procedure TMyrLSPServer.HandleTextDocumentDidOpen(
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LText: string;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then Exit;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LText := LTextDoc.GetValue<string>('text', '');

  if LUri <> '' then
  begin
    FService.OpenDocument(LUri, LText);
    PublishDiagnostics(LUri);
  end;
end;

procedure TMyrLSPServer.HandleTextDocumentDidChange(
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LVersion: Integer;
  LChanges: TJSONArray;
  LChange: TJSONObject;
  LText: string;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then Exit;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LVersion := LTextDoc.GetValue<Integer>('version', 0);

  LChanges := AParams.GetValue<TJSONArray>('contentChanges', nil);
  if (LChanges = nil) or (LChanges.Count = 0) then Exit;

  // Full sync mode -- last change has the complete text
  LChange := LChanges.Items[LChanges.Count - 1] as TJSONObject;
  LText := LChange.GetValue<string>('text', '');

  if LUri <> '' then
  begin
    FService.UpdateDocument(LUri, LText, LVersion);
    PublishDiagnostics(LUri);
  end;
end;

procedure TMyrLSPServer.HandleTextDocumentDidClose(
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LParams: TJSONObject;
  LDiagArray: TJSONArray;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then Exit;

  LUri := LTextDoc.GetValue<string>('uri', '');
  if LUri <> '' then
  begin
    // Clear diagnostics
    LParams := TJSONObject.Create();
    LParams.AddPair('uri', LUri);
    LDiagArray := TJSONArray.Create();
    LParams.AddPair('diagnostics', LDiagArray);
    SendNotification('textDocument/publishDiagnostics', LParams);

    FService.CloseDocument(LUri);
  end;
end;

procedure TMyrLSPServer.HandleTextDocumentCompletion(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LItems: TArray<TMyrLSPCompletionItem>;
  LResult: TJSONObject;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LItems := FService.GetCompletions(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  LResult := TJSONObject.Create();
  LResult.AddPair('isIncomplete', TJSONBool.Create(False));
  LArray := TJSONArray.Create();
  for LI := 0 to High(LItems) do
    LArray.AddElement(LItems[LI].ToJSON());
  LResult.AddPair('items', LArray);
  SendResponse(AId, LResult);
end;

procedure TMyrLSPServer.HandleTextDocumentHover(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LHover: TMyrLSPHover;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LHover := FService.GetHover(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if LHover.IsEmpty() then
    SendResponse(AId, TJSONNull.Create())
  else
    SendResponse(AId, LHover.ToJSON());
end;

procedure TMyrLSPServer.HandleTextDocumentDefinition(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LLocation: TMyrLSPLocation;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LLocation := FService.GetDefinition(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if LLocation.IsEmpty() then
    SendResponse(AId, TJSONNull.Create())
  else
    SendResponse(AId, LLocation.ToJSON());
end;

procedure TMyrLSPServer.HandleTextDocumentTypeDefinition(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LLocation: TMyrLSPLocation;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LLocation := FService.GetTypeDefinition(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if LLocation.IsEmpty() then
    SendResponse(AId, TJSONNull.Create())
  else
    SendResponse(AId, LLocation.ToJSON());
end;

procedure TMyrLSPServer.HandleTextDocumentReferences(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LContext: TJSONObject;
  LUri: string;
  LIncludeDecl: Boolean;
  LLocations: TArray<TMyrLSPLocation>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LContext := AParams.GetValue<TJSONObject>('context', nil);
  LIncludeDecl := True;
  if LContext <> nil then
    LIncludeDecl := LContext.GetValue<Boolean>('includeDeclaration', True);

  LLocations := FService.GetReferences(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0),
    LIncludeDecl);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LLocations) do
    LArray.AddElement(LLocations[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TMyrLSPServer.HandleTextDocumentDocumentSymbol(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LSymbols: TArray<TMyrLSPDocumentSymbol>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LSymbols := FService.GetDocumentSymbols(LUri);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LSymbols) do
    LArray.AddElement(LSymbols[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TMyrLSPServer.HandleTextDocumentSignatureHelp(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LSigHelp: TMyrLSPSignatureHelp;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LSigHelp := FService.GetSignatureHelp(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if Length(LSigHelp.Signatures) = 0 then
    SendResponse(AId, TJSONNull.Create())
  else
    SendResponse(AId, LSigHelp.ToJSON());
end;

procedure TMyrLSPServer.HandleTextDocumentFoldingRange(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LRanges: TArray<TMyrLSPFoldingRange>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LRanges := FService.GetFoldingRanges(LUri);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LRanges) do
    LArray.AddElement(LRanges[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TMyrLSPServer.HandleTextDocumentSemanticTokensFull(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LData: TArray<Integer>;
  LResult: TJSONObject;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LData := FService.GetSemanticTokens(LUri);

  LResult := TJSONObject.Create();
  LArray := TJSONArray.Create();
  for LI := 0 to High(LData) do
    LArray.Add(LData[LI]);
  LResult.AddPair('data', LArray);
  SendResponse(AId, LResult);
end;

procedure TMyrLSPServer.HandleTextDocumentFormatting(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LOptions: TJSONObject;
  LUri: string;
  LTabSize: Integer;
  LInsertSpaces: Boolean;
  LEdits: TArray<TMyrLSPTextEdit>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LOptions := AParams.GetValue<TJSONObject>('options', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LTabSize := 2;
  LInsertSpaces := True;
  if LOptions <> nil then
  begin
    LTabSize := LOptions.GetValue<Integer>('tabSize', 2);
    LInsertSpaces := LOptions.GetValue<Boolean>('insertSpaces', True);
  end;

  LEdits := FService.GetDocumentFormatting(LUri, LTabSize, LInsertSpaces);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LEdits) do
    LArray.AddElement(LEdits[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TMyrLSPServer.HandleTextDocumentCodeAction(const AId: TJSONValue;
  const AParams: TJSONObject);
begin
  // No code actions implemented yet
  SendResponse(AId, TJSONArray.Create());
end;

procedure TMyrLSPServer.HandleTextDocumentInlayHint(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LRangeObj: TJSONObject;
  LUri: string;
  LLSPRange: TMyrLSPRange;
  LHints: TArray<TMyrLSPInlayHint>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LLSPRange.Clear();
  LRangeObj := AParams.GetValue<TJSONObject>('range', nil);
  if LRangeObj <> nil then
    LLSPRange := TMyrLSPRange.FromJSON(LRangeObj);

  LHints := FService.GetInlayHints(LUri,
    LLSPRange.StartPos.Line, LLSPRange.StartPos.Character,
    LLSPRange.EndPos.Line, LLSPRange.EndPos.Character);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LHints) do
    LArray.AddElement(LHints[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TMyrLSPServer.HandleTextDocumentRename(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LNewName: string;
  LEdit: TMyrLSPWorkspaceEdit;
  LResult: TJSONObject;
  LChanges: TJSONObject;
  LEditsArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LNewName := AParams.GetValue<string>('newName', '');

  LEdit := FService.GetRenameEdits(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0),
    LNewName);

  if Length(LEdit.Edits) = 0 then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LResult := TJSONObject.Create();
  LChanges := TJSONObject.Create();
  LEditsArray := TJSONArray.Create();
  for LI := 0 to High(LEdit.Edits) do
    LEditsArray.AddElement(LEdit.Edits[LI].ToJSON());
  LChanges.AddPair(LEdit.Uri, LEditsArray);
  LResult.AddPair('changes', LChanges);
  SendResponse(AId, LResult);
end;

procedure TMyrLSPServer.HandleWorkspaceSymbol(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LQuery: string;
  LSymbols: TArray<TMyrLSPSymbolInformation>;
  LArray: TJSONArray;
  LI: Integer;
  LPair: TPair<string, TMyrLSPDocument>;
begin
  LQuery := AParams.GetValue<string>('query', '');

  LArray := TJSONArray.Create();
  // Search all open documents
  for LPair in FService.FDocuments do
  begin
    LSymbols := FService.GetWorkspaceSymbols(LQuery, LPair.Key);
    for LI := 0 to High(LSymbols) do
      LArray.AddElement(LSymbols[LI].ToJSON());
  end;
  SendResponse(AId, LArray);
end;

procedure TMyrLSPServer.HandleTextDocumentPrepareCallHierarchy(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LItems: TArray<TMyrLSPCallHierarchyItem>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LItems := FService.PrepareCallHierarchy(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if Length(LItems) = 0 then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LArray := TJSONArray.Create();
  for LI := 0 to High(LItems) do
    LArray.AddElement(LItems[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TMyrLSPServer.HandleCallHierarchyIncomingCalls(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LItem: TJSONObject;
  LUri: string;
  LName: string;
  LCalls: TArray<TMyrLSPCallHierarchyCall>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LItem := AParams.GetValue<TJSONObject>('item', nil);
  if LItem = nil then
  begin
    SendResponse(AId, TJSONArray.Create());
    Exit;
  end;

  LUri := LItem.GetValue<string>('uri', '');
  LName := LItem.GetValue<string>('name', '');

  LCalls := FService.GetIncomingCalls(LUri, LName);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LCalls) do
    LArray.AddElement(LCalls[LI].ToJSON('from'));
  SendResponse(AId, LArray);
end;

procedure TMyrLSPServer.HandleCallHierarchyOutgoingCalls(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LItem: TJSONObject;
  LUri: string;
  LName: string;
  LCalls: TArray<TMyrLSPCallHierarchyCall>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LItem := AParams.GetValue<TJSONObject>('item', nil);
  if LItem = nil then
  begin
    SendResponse(AId, TJSONArray.Create());
    Exit;
  end;

  LUri := LItem.GetValue<string>('uri', '');
  LName := LItem.GetValue<string>('name', '');

  LCalls := FService.GetOutgoingCalls(LUri, LName);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LCalls) do
    LArray.AddElement(LCalls[LI].ToJSON('to'));
  SendResponse(AId, LArray);
end;

procedure TMyrLSPServer.DispatchMessage(const AMessage: TJSONObject);
var
  LMethod: string;
  LId: TJSONValue;
  LParams: TJSONObject;
begin
  LMethod := AMessage.GetValue<string>('method', '');
  LId := AMessage.GetValue('id');
  LParams := AMessage.GetValue<TJSONObject>('params', nil);

  // Requests (have id)
  if LId <> nil then
  begin
    if LMethod = 'initialize' then
      HandleInitialize(LId, LParams)
    else if LMethod = 'shutdown' then
      HandleShutdown(LId)
    else if LMethod = 'textDocument/completion' then
      HandleTextDocumentCompletion(LId, LParams)
    else if LMethod = 'textDocument/hover' then
      HandleTextDocumentHover(LId, LParams)
    else if LMethod = 'textDocument/definition' then
      HandleTextDocumentDefinition(LId, LParams)
    else if LMethod = 'textDocument/typeDefinition' then
      HandleTextDocumentTypeDefinition(LId, LParams)
    else if LMethod = 'textDocument/references' then
      HandleTextDocumentReferences(LId, LParams)
    else if LMethod = 'textDocument/documentSymbol' then
      HandleTextDocumentDocumentSymbol(LId, LParams)
    else if LMethod = 'textDocument/signatureHelp' then
      HandleTextDocumentSignatureHelp(LId, LParams)
    else if LMethod = 'textDocument/foldingRange' then
      HandleTextDocumentFoldingRange(LId, LParams)
    else if LMethod = 'textDocument/semanticTokens/full' then
      HandleTextDocumentSemanticTokensFull(LId, LParams)
    else if LMethod = 'textDocument/formatting' then
      HandleTextDocumentFormatting(LId, LParams)
    else if LMethod = 'textDocument/codeAction' then
      HandleTextDocumentCodeAction(LId, LParams)
    else if LMethod = 'textDocument/inlayHint' then
      HandleTextDocumentInlayHint(LId, LParams)
    else if LMethod = 'textDocument/rename' then
      HandleTextDocumentRename(LId, LParams)
    else if LMethod = 'workspace/symbol' then
      HandleWorkspaceSymbol(LId, LParams)
    else if LMethod = 'textDocument/prepareCallHierarchy' then
      HandleTextDocumentPrepareCallHierarchy(LId, LParams)
    else if LMethod = 'callHierarchy/incomingCalls' then
      HandleCallHierarchyIncomingCalls(LId, LParams)
    else if LMethod = 'callHierarchy/outgoingCalls' then
      HandleCallHierarchyOutgoingCalls(LId, LParams)
    else
      SendError(LId, -32601, 'Method not found: ' + LMethod);
  end
  else
  begin
    // Notifications (no id)
    if LMethod = 'initialized' then
      HandleInitialized(LParams)
    else if LMethod = 'exit' then
      HandleExit()
    else if LMethod = 'textDocument/didOpen' then
      HandleTextDocumentDidOpen(LParams)
    else if LMethod = 'textDocument/didChange' then
      HandleTextDocumentDidChange(LParams)
    else if LMethod = 'textDocument/didClose' then
      HandleTextDocumentDidClose(LParams);
    // Unknown notifications are silently ignored per spec
  end;
end;

function TMyrLSPServer.Run(): DWORD;
var
  LMsg: TJSONObject;
begin
  // Default to stdin/stdout if no streams set
  if FInputStream = nil then
  begin
    FInputStream := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
    FOutputStream := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
    FOwnsStreams := True;
  end;

  FRunning := True;
  FExitCode := 0;

  Log('started');

  while FRunning do
  begin
    LMsg := ReadMessage();
    if LMsg = nil then Break;
    try
      DispatchMessage(LMsg);
    finally
      LMsg.Free();
    end;
  end;

  Log('exiting with code ' + IntToStr(FExitCode));
  Result := FExitCode;
end;

end.
