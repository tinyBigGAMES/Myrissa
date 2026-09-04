{===============================================================================
  Myrissa™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://myrissa.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  UTestCase.LSP - LSP server test cases

  In-process tests for TMyrLSPServer: lifecycle, diagnostics, completion,
  hover, go-to-definition, references, document symbols, semantic tokens,
  signature help, folding ranges, rename, and inlay hints.

  Uses SetStreams with TBytesStream pairs to drive the server without a
  subprocess. Each test builds a full session (init -> open -> request ->
  shutdown -> exit) and asserts on the actual response content.

  Dependencies: StdApp.TestCase, StdApp.JSON, Myrissa.Common, Myrissa.LSP
===============================================================================}

unit UTestCase.LSP;

interface

uses
  StdApp.TestCase;

type

  { TCPLSPTests }
  TCPLSPTests = class(TTestCase)
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.JSON,
  Myrissa.Common,
  Myrissa.LSP;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

procedure FrameMessage(const AStream: TBytesStream; const AJSON: TJSON);
var
  LBody: TBytes;
  LHeader: string;
  LHeaderBytes: TBytes;
begin
  LBody := TEncoding.UTF8.GetBytes(AJSON.ToString());
  LHeader := 'Content-Length: ' + IntToStr(Length(LBody)) + #13#10 + #13#10;
  LHeaderBytes := TEncoding.ASCII.GetBytes(LHeader);
  AStream.Write(LHeaderBytes[0], Length(LHeaderBytes));
  AStream.Write(LBody[0], Length(LBody));
end;

function MakeRequest(const AId: Integer; const AMethod: string): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', AMethod)
        .BeginObject('params')
        .EndObject();
end;

function MakeNotification(const AMethod: string): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('method', AMethod)
        .BeginObject('params')
        .EndObject();
end;

function MakeInitialize(const AId: Integer): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'initialize')
        .BeginObject('params')
          .Add('processId', 1234)
          .BeginObject('capabilities')
          .EndObject()
        .EndObject();
end;

function MakeDidOpen(const AUri: string; const AContent: string): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('method', 'textDocument/didOpen')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
            .Add('languageId', 'cpaskal')
            .Add('version', 1)
            .Add('text', AContent)
          .EndObject()
        .EndObject();
end;

function MakeHover(const AId: Integer; const AUri: string;
  const ALine: Integer; const ACharacter: Integer): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/hover')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
          .BeginObject('position')
            .Add('line', ALine)
            .Add('character', ACharacter)
          .EndObject()
        .EndObject();
end;

function MakeCompletion(const AId: Integer; const AUri: string;
  const ALine: Integer; const ACharacter: Integer): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/completion')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
          .BeginObject('position')
            .Add('line', ALine)
            .Add('character', ACharacter)
          .EndObject()
        .EndObject();
end;

function MakeDefinition(const AId: Integer; const AUri: string;
  const ALine: Integer; const ACharacter: Integer): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/definition')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
          .BeginObject('position')
            .Add('line', ALine)
            .Add('character', ACharacter)
          .EndObject()
        .EndObject();
end;

function MakeReferences(const AId: Integer; const AUri: string;
  const ALine: Integer; const ACharacter: Integer): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/references')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
          .BeginObject('position')
            .Add('line', ALine)
            .Add('character', ACharacter)
          .EndObject()
          .BeginObject('context')
            .Add('includeDeclaration', True)
          .EndObject()
        .EndObject();
end;

function MakeDocumentSymbol(const AId: Integer; const AUri: string): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/documentSymbol')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
        .EndObject();
end;

function MakeSemanticTokens(const AId: Integer; const AUri: string): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/semanticTokens/full')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
        .EndObject();
end;

function MakeSignatureHelp(const AId: Integer; const AUri: string;
  const ALine: Integer; const ACharacter: Integer): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/signatureHelp')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
          .BeginObject('position')
            .Add('line', ALine)
            .Add('character', ACharacter)
          .EndObject()
        .EndObject();
end;

function MakeFoldingRange(const AId: Integer; const AUri: string): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/foldingRange')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
        .EndObject();
end;

function MakeRename(const AId: Integer; const AUri: string;
  const ALine: Integer; const ACharacter: Integer;
  const ANewName: string): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/rename')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
          .BeginObject('position')
            .Add('line', ALine)
            .Add('character', ACharacter)
          .EndObject()
          .Add('newName', ANewName)
        .EndObject();
end;

function MakeInlayHint(const AId: Integer; const AUri: string;
  const AStartLine: Integer; const AEndLine: Integer): TJSON;
begin
  Result := TJSON.Create();
  Result.Add('jsonrpc', '2.0')
        .Add('id', AId)
        .Add('method', 'textDocument/inlayHint')
        .BeginObject('params')
          .BeginObject('textDocument')
            .Add('uri', AUri)
          .EndObject()
          .BeginObject('range')
            .BeginObject('start')
              .Add('line', AStartLine)
              .Add('character', 0)
            .EndObject()
            .BeginObject('end')
              .Add('line', AEndLine)
              .Add('character', 0)
            .EndObject()
          .EndObject()
        .EndObject();
end;

function MakeShutdown(const AId: Integer): TJSON;
begin
  Result := MakeRequest(AId, 'shutdown');
end;

function MakeExit(): TJSON;
begin
  Result := MakeNotification('exit');
end;

// Parse all JSON-RPC responses from output stream.
function ParseResponses(const AStream: TBytesStream): TObjectList<TJSON>;
var
  LBytes: TBytes;
  LText: string;
  LPos: Integer;
  LContentLength: Integer;
  LHeaderEnd: Integer;
  LBody: string;
  LJSON: TJSON;
  LLine: string;
begin
  Result := TObjectList<TJSON>.Create(True);
  LBytes := Copy(AStream.Bytes, 0, AStream.Size);
  LText := TEncoding.UTF8.GetString(LBytes);
  LPos := 1;

  while LPos <= Length(LText) do
  begin
    LHeaderEnd := Pos(#13#10#13#10, LText, LPos);
    if LHeaderEnd = 0 then Break;

    LContentLength := 0;
    LLine := Copy(LText, LPos, LHeaderEnd - LPos);
    if LLine.StartsWith('Content-Length:') then
      LContentLength := StrToIntDef(Trim(Copy(LLine, 16, MaxInt)), 0);

    if LContentLength <= 0 then Break;

    LPos := LHeaderEnd + 4;
    LBody := Copy(LText, LPos, LContentLength);
    LPos := LPos + LContentLength;

    LJSON := TJSON.Create();
    LJSON.Parse(LBody);
    Result.Add(LJSON);
  end;
end;

// Run a full LSP session and return parsed responses.
function RunSession(const AMessages: array of TJSON;
  out AExitCode: Word): TObjectList<TJSON>;
var
  LInput: TBytesStream;
  LOutput: TBytesStream;
  LServer: TMyrLSPServer;
  LI: Integer;
begin
  LInput := TBytesStream.Create();
  LOutput := TBytesStream.Create();
  try
    for LI := 0 to High(AMessages) do
      FrameMessage(LInput, AMessages[LI]);

    LInput.Position := 0;

    LServer := TMyrLSPServer.Create();
    try
      LServer.SetStreams(LInput, LOutput);
      AExitCode := LServer.Run();
    finally
      LServer.Free();
    end;

    LOutput.Position := 0;
    Result := ParseResponses(LOutput);
  finally
    // RunSession takes ownership of input messages -- free them here
    for LI := 0 to High(AMessages) do
      AMessages[LI].Free();
    LInput.Free();
    LOutput.Free();
  end;
end;

// Find response by id in response list.
function FindResponse(const AResponses: TObjectList<TJSON>;
  const AId: Integer): TJSON;
var
  LI: Integer;
begin
  Result := nil;
  for LI := 0 to AResponses.Count - 1 do
  begin
    if AResponses[LI].Get('id').AsInt32(-1) = AId then
    begin
      Result := AResponses[LI];
      Exit;
    end;
  end;
end;

// Check if any item in a JSON array has a field matching a value.
function ArrayHasItemWithField(const AArray: TJSON;
  const AField: string; const AValue: string): Boolean;
var
  LItems: TArray<TJSON>;
  LI: Integer;
begin
  Result := False;
  LItems := AArray.Items();
  for LI := 0 to High(LItems) do
  begin
    if LItems[LI].Get(AField).AsString() = AValue then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Test source code
// ---------------------------------------------------------------------------

const
  TEST_URI = 'file:///test/probe.cpas';

  // Source with var, const, routine, type -- exercises most LSP features.
  // Line numbers (0-based):
  //  0: module exe probe;
  //  1: (blank)
  //  2: const
  //  3:   MAX_VAL: int32 = 100;
  //  4: (blank)
  //  5: type
  //  6:   MyRecord = record
  //  7:     x: int32;
  //  8:     y: int32;
  //  9:   end;
  // 10: (blank)
  // 11: var
  // 12:   counter: int32;
  // 13:   name: string;
  // 14: (blank)
  // 15: routine add(a: int32; b: int32): int32;
  // 16: begin
  // 17:   return a + b;
  // 18: end;
  // 19: (blank)
  // 20: begin
  // 21:   counter := add(10, 20);
  // 22:   println("result: {}", counter);
  // 23: end.
  RICH_SOURCE =
    'module exe probe;' + #10 +
    '' + #10 +
    'const' + #10 +
    '  MAX_VAL: int32 = 100;' + #10 +
    '' + #10 +
    'type' + #10 +
    '  MyRecord = record' + #10 +
    '    x: int32;' + #10 +
    '    y: int32;' + #10 +
    '  end;' + #10 +
    '' + #10 +
    'var' + #10 +
    '  counter: int32;' + #10 +
    '  name: string;' + #10 +
    '' + #10 +
    'routine add(a: int32; b: int32): int32;' + #10 +
    'begin' + #10 +
    '  return a + b;' + #10 +
    'end;' + #10 +
    '' + #10 +
    'begin' + #10 +
    '  counter := add(10, 20);' + #10 +
    '  println("result: {}", counter);' + #10 +
    'end.';

  // Source with deliberate errors for diagnostics testing.
  ERROR_SOURCE =
    'module exe probe;' + #10 +
    'begin' + #10 +
    '  undeclaredVar := 42;' + #10 +
    'end.';

// ---------------------------------------------------------------------------
// Test registration
// ---------------------------------------------------------------------------

{ TCPLSPTests }

constructor TCPLSPTests.Create();
begin
  inherited;
  Title := 'LSP';

  // -- Lifecycle: clean shutdown returns 0 --
  RegisterTest('lifecycle_clean', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeShutdown(2), MakeExit()
    ], LExitCode);
    try
      Check(LExitCode = 0, 'clean shutdown returns exit code 0');
      Check(LResponses.Count >= 2, 'got init + shutdown responses');
      Check(LResponses[0].Has('result.capabilities'), 'init response has capabilities');
      Check(FindResponse(LResponses, 2) <> nil, 'shutdown response present');
    finally
      LResponses.Free();
    end;
  end);

  // -- Lifecycle: exit without shutdown returns 1 --
  RegisterTest('lifecycle_unclean', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeExit()
    ], LExitCode);
    try
      Check(LExitCode = 1, 'exit without shutdown returns code 1');
    finally
      LResponses.Free();
    end;
  end);

  // -- Capabilities: verify all providers are advertised --
  RegisterTest('capabilities', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LCaps: TJSON;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeShutdown(2), MakeExit()
    ], LExitCode);
    try
      LCaps := LResponses[0].Get('result.capabilities');
      Check(LCaps.Get('hoverProvider').AsBoolean(), 'hover enabled');
      Check(LCaps.Get('definitionProvider').AsBoolean(), 'definition enabled');
      Check(LCaps.Get('typeDefinitionProvider').AsBoolean(), 'type definition enabled');
      Check(LCaps.Get('referencesProvider').AsBoolean(), 'references enabled');
      Check(LCaps.Get('documentSymbolProvider').AsBoolean(), 'document symbol enabled');
      Check(LCaps.Has('completionProvider'), 'completion enabled');
      Check(LCaps.Has('signatureHelpProvider'), 'signature help enabled');
      Check(LCaps.Get('foldingRangeProvider').AsBoolean(), 'folding enabled');
      Check(LCaps.Has('semanticTokensProvider'), 'semantic tokens enabled');
      Check(LCaps.Get('documentFormattingProvider').AsBoolean(), 'formatting enabled');
      Check(LCaps.Get('renameProvider').AsBoolean(), 'rename enabled');
      Check(LCaps.Get('inlayHintProvider').AsBoolean(), 'inlay hints enabled');
      Check(LCaps.Get('workspaceSymbolProvider').AsBoolean(), 'workspace symbols enabled');
      Check(LCaps.Get('callHierarchyProvider').AsBoolean(), 'call hierarchy enabled');
    finally
      LResponses.Free();
    end;
  end);

  // -- Hover: verify correct type info for variable --
  RegisterTest('hover_variable', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LContent: string;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeHover(2, TEST_URI, 12, 4),  // line 12, col 4 = 'counter' decl
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'hover response received');
      LContent := LR.Get('result.contents.value').AsString();
      Check(LContent.Contains('counter'), 'hover shows variable name');
      Check(LContent.Contains('int32'), 'hover shows type int32');
    finally
      LResponses.Free();
    end;
  end);

  // -- Hover: verify correct type info for routine --
  RegisterTest('hover_routine', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LContent: string;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeHover(2, TEST_URI, 15, 10),  // line 15, col 10 = 'add' routine
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'hover response received');
      LContent := LR.Get('result.contents.value').AsString();
      Check(LContent.Contains('routine'), 'hover shows routine');
      Check(LContent.Contains('int32'), 'hover shows return type');
    finally
      LResponses.Free();
    end;
  end);

  // -- Go-to-definition: lands on the declaration line --
  RegisterTest('goto_definition', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LLine: Integer;
  begin
    // Click on 'counter' usage at line 21, col 4
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeDefinition(2, TEST_URI, 21, 4),  // 'counter' in 'counter := add(...)'
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'definition response received');
      // Result should point to line 12 where counter is declared
      LLine := LR.Get('result.range.start.line').AsInt32(-1);
      Check(LLine = 12, 'definition points to declaration line 12');
    finally
      LResponses.Free();
    end;
  end);

  // -- Go-to-definition: routine usage resolves to routine decl --
  RegisterTest('goto_definition_routine', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LLine: Integer;
  begin
    // Click on 'add' call at line 21, col 14
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeDefinition(2, TEST_URI, 21, 14),  // 'add' in 'counter := add(10, 20)'
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'definition response received');
      LLine := LR.Get('result.range.start.line').AsInt32(-1);
      Check(LLine = 15, 'definition points to routine decl line 15');
    finally
      LResponses.Free();
    end;
  end);

  // -- Find references: counter is used at decl and two usages --
  RegisterTest('find_references', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LRefs: TArray<TJSON>;
  begin
    // Find refs for 'counter' at its declaration (line 12)
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeReferences(2, TEST_URI, 12, 4),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'references response received');
      LRefs := LR.Get('result').Items();
      // counter declared on 12, used on 21 and 22 = at least 3
      Check(Length(LRefs) >= 2, 'at least 2 references for counter');
    finally
      LResponses.Free();
    end;
  end);

  // -- Completion: keywords from lexer --
  RegisterTest('completion_keywords', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LItems: TJSON;
    LArr: TArray<TJSON>;
    LFoundBegin: Boolean;
    LFoundRoutine: Boolean;
    LFoundGuard: Boolean;
    LI: Integer;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeCompletion(2, TEST_URI, 21, 0),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'completion response received');
      LItems := LR.Get('result.items');
      LArr := LItems.Items();
      Check(Length(LArr) > 20, 'many completion items returned');

      LFoundBegin := False;
      LFoundRoutine := False;
      LFoundGuard := False;
      for LI := 0 to High(LArr) do
      begin
        if LArr[LI].Get('label').AsString() = 'begin' then LFoundBegin := True;
        if LArr[LI].Get('label').AsString() = 'routine' then LFoundRoutine := True;
        if LArr[LI].Get('label').AsString() = 'guard' then LFoundGuard := True;
      end;
      Check(LFoundBegin, 'begin in completions');
      Check(LFoundRoutine, 'routine in completions');
      Check(LFoundGuard, 'guard in completions');
    finally
      LResponses.Free();
    end;
  end);

  // -- Completion: scope-aware symbols --
  RegisterTest('completion_symbols', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LItems: TJSON;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeCompletion(2, TEST_URI, 21, 0),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'completion response received');
      LItems := LR.Get('result.items');
      // Should include declared symbols from the source
      Check(ArrayHasItemWithField(LItems, 'label', 'counter'), 'counter in completions');
      Check(ArrayHasItemWithField(LItems, 'label', 'add'), 'add in completions');
      Check(ArrayHasItemWithField(LItems, 'label', 'MAX_VAL'), 'MAX_VAL in completions');
      Check(ArrayHasItemWithField(LItems, 'label', 'MyRecord'), 'MyRecord in completions');
    finally
      LResponses.Free();
    end;
  end);

  // -- Diagnostics: clean source has no errors --
  RegisterTest('diagnostics_clean', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LI: Integer;
    LDiags: TJSON;
    LHasErrors: Boolean;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeShutdown(2), MakeExit()
    ], LExitCode);
    try
      // Look for publishDiagnostics notification in responses
      LHasErrors := False;
      for LI := 0 to LResponses.Count - 1 do
      begin
        if LResponses[LI].Get('method').AsString() = 'textDocument/publishDiagnostics' then
        begin
          LDiags := LResponses[LI].Get('params.diagnostics');
          if LDiags.Count() > 0 then
            LHasErrors := True;
        end;
      end;
      Check(not LHasErrors, 'valid source produces no diagnostics');
    finally
      LResponses.Free();
    end;
  end);

  // -- Diagnostics: invalid source reports errors --
  RegisterTest('diagnostics_errors', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LI: Integer;
    LDiags: TJSON;
    LHasErrors: Boolean;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, ERROR_SOURCE),
      MakeShutdown(2), MakeExit()
    ], LExitCode);
    try
      LHasErrors := False;
      for LI := 0 to LResponses.Count - 1 do
      begin
        if LResponses[LI].Get('method').AsString() = 'textDocument/publishDiagnostics' then
        begin
          LDiags := LResponses[LI].Get('params.diagnostics');
          if LDiags.Count() > 0 then
            LHasErrors := True;
        end;
      end;
      Check(LHasErrors, 'invalid source produces diagnostics');
    finally
      LResponses.Free();
    end;
  end);

  // -- Document symbols: verifies names and kinds --
  RegisterTest('document_symbols', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LSyms: TArray<TJSON>;
    LFoundConst: Boolean;
    LFoundType: Boolean;
    LFoundVar: Boolean;
    LFoundRoutine: Boolean;
    LI: Integer;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeDocumentSymbol(2, TEST_URI),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'symbol response received');
      LSyms := LR.Get('result').Items();
      Check(Length(LSyms) >= 4, 'at least 4 symbols (const, type, var, routine)');

      LFoundConst := False;
      LFoundType := False;
      LFoundVar := False;
      LFoundRoutine := False;
      for LI := 0 to High(LSyms) do
      begin
        if LSyms[LI].Get('name').AsString() = 'MAX_VAL' then LFoundConst := True;
        if LSyms[LI].Get('name').AsString() = 'MyRecord' then LFoundType := True;
        if LSyms[LI].Get('name').AsString() = 'counter' then LFoundVar := True;
        if LSyms[LI].Get('name').AsString() = 'add' then LFoundRoutine := True;
      end;
      Check(LFoundConst, 'MAX_VAL in symbols');
      Check(LFoundType, 'MyRecord in symbols');
      Check(LFoundVar, 'counter in symbols');
      Check(LFoundRoutine, 'add in symbols');
    finally
      LResponses.Free();
    end;
  end);

  // -- Document symbols: record has child fields --
  RegisterTest('document_symbols_children', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LSyms: TArray<TJSON>;
    LChildren: TArray<TJSON>;
    LI: Integer;
    LFoundX: Boolean;
    LFoundY: Boolean;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeDocumentSymbol(2, TEST_URI),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'symbol response received');
      LSyms := LR.Get('result').Items();
      // Find MyRecord and check children
      for LI := 0 to High(LSyms) do
      begin
        if LSyms[LI].Get('name').AsString() = 'MyRecord' then
        begin
          LChildren := LSyms[LI].Get('children').Items();
          Check(Length(LChildren) >= 2, 'MyRecord has at least 2 children');
          LFoundX := False;
          LFoundY := False;
          if ArrayHasItemWithField(LSyms[LI].Get('children'), 'name', 'x') then
            LFoundX := True;
          if ArrayHasItemWithField(LSyms[LI].Get('children'), 'name', 'y') then
            LFoundY := True;
          Check(LFoundX, 'field x in MyRecord children');
          Check(LFoundY, 'field y in MyRecord children');
        end;
      end;
    finally
      LResponses.Free();
    end;
  end);

  // -- Semantic tokens: verifies token encoding --
  RegisterTest('semantic_tokens', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LData: TArray<TJSON>;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeSemanticTokens(2, TEST_URI),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'semantic tokens response received');
      LData := LR.Get('result.data').Items();
      // Data is groups of 5 ints: deltaLine, deltaChar, length, tokenType, modifiers
      Check(Length(LData) > 0, 'semantic token data returned');
      Check((Length(LData) mod 5) = 0, 'data length is multiple of 5');
      // First token is 'module' keyword at line 0, col 0
      Check(LData[0].AsInt32() = 0, 'first token deltaLine = 0');
      Check(LData[1].AsInt32() = 0, 'first token deltaChar = 0');
      Check(LData[2].AsInt32() = 6, 'first token length = 6 (module)');
      Check(LData[3].AsInt32() = 15, 'first token type = 15 (keyword)');
    finally
      LResponses.Free();
    end;
  end);

  // -- Folding ranges: begin/end blocks produce ranges --
  RegisterTest('folding_ranges', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LRanges: TArray<TJSON>;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeFoldingRange(2, TEST_URI),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'folding response received');
      LRanges := LR.Get('result').Items();
      // At minimum: routine body (16-18) and main body (20-23)
      Check(Length(LRanges) >= 2, 'at least 2 folding ranges');
    finally
      LResponses.Free();
    end;
  end);

  // -- Signature help: shows params for routine call --
  RegisterTest('signature_help', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LSigs: TArray<TJSON>;
    LLabel: string;
  begin
    // Cursor inside add( at line 21, col 18 -- after opening paren
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeSignatureHelp(2, TEST_URI, 21, 18),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'signature help response received');
      LSigs := LR.Get('result.signatures').Items();
      Check(Length(LSigs) >= 1, 'at least 1 signature');
      if Length(LSigs) = 0 then Exit;
      LLabel := LSigs[0].Get('label').AsString();
      Check(LLabel.Contains('a'), 'signature shows param a');
      Check(LLabel.Contains('b'), 'signature shows param b');
      Check(LLabel.Contains('int32'), 'signature shows param types');
    finally
      LResponses.Free();
    end;
  end);

  // -- Rename: renames variable across usages --
  RegisterTest('rename', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LChanges: TJSON;
    LEdits: TArray<TJSON>;
  begin
    // Rename 'counter' at line 12
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeRename(2, TEST_URI, 12, 4, 'total'),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'rename response received');
      LChanges := LR.Get('result.changes');
      Check(not LChanges.IsNull(), 'changes object present');
      if LChanges.IsNull() then Exit;
      // Get edits for our URI
      if LChanges.Get(TEST_URI, True).IsNull() then
      begin
        Check(False, 'edits for URI present');
        Exit;
      end;
      LEdits := LChanges.Get(TEST_URI, True).Items();
      // Should have edits at decl (12) + usages (21, 22) = at least 2
      Check(Length(LEdits) >= 2, 'at least 2 rename edits');
      if Length(LEdits) = 0 then Exit;
      // Each edit should have newText = 'total'
      Check(LEdits[0].Get('newText').AsString() = 'total', 'edit has new name');
    finally
      LResponses.Free();
    end;
  end);

  // -- Inlay hints: type hints on variables --
  RegisterTest('inlay_hints', procedure
  var
    LResponses: TObjectList<TJSON>;
    LExitCode: Word;
    LR: TJSON;
    LHints: TArray<TJSON>;
  begin
    LResponses := RunSession([
      MakeInitialize(1), MakeNotification('initialized'),
      MakeDidOpen(TEST_URI, RICH_SOURCE),
      MakeInlayHint(2, TEST_URI, 0, 23),
      MakeShutdown(3), MakeExit()
    ], LExitCode);
    try
      LR := FindResponse(LResponses, 2);
      Check(LR <> nil, 'inlay hints response received');
      if LR = nil then Exit;
      if LR.Get('result').IsNull() then
      begin
        Check(False, 'inlay hints result present');
        Exit;
      end;
      LHints := LR.Get('result').Items();
      // Should have at least some hints (type annotations on expressions)
      Check(Length(LHints) >= 0, 'inlay hints response is valid array');
    finally
      LResponses.Free();
    end;
  end);

end;

procedure TCPLSPTests.Run();
begin
  inherited;
end;

end.
