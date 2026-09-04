{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Console.Adapter - Streaming Markdown-to-ANSI Console Renderer

  Sits between an LLM token stream and console output, accumulating tokens into
  complete lines, then classifying and rendering each line with styled ANSI
  output: box-drawing headings, colored code blocks, Unicode bullets, tables,
  blockquotes, and intelligent word wrapping.

  Architecture: Line-buffered two-phase renderer.
    Phase 1: Accumulate tokens until newline, classify complete line.
    Phase 2: Render classified line with inline markdown parsing.

  Key types:
  - TConsoleAdapter: Streaming parser -- Write(token), Flush(), Reset()
  - Output via TCallback<TAdapterOutputCallback> so consumer controls destination

  Dependencies: StdApp.Base, StdApp.Console
  Notes: Designed for token-by-token streaming from LLM inference.
  Does not require complete markdown documents.
===============================================================================}

unit StdApp.Console.Adapter;

{$I StdApp.Defines.inc}

interface

uses
  System.SysUtils,
  StdApp.Base;

type
  { TLineKind }
  TLineKind = (
    lkBlank,
    lkParagraph,
    lkHeading,
    lkCodeFenceOpen,
    lkCodeFenceClose,
    lkCodeContent,
    lkUnorderedList,
    lkOrderedList,
    lkTaskList,
    lkBlockquote,
    lkHRule,
    lkTableRow,
    lkTableSeparator,
    lkMathBlock
  );

  { TBlockState }
  TBlockState = (
    bsNone,
    bsCodeBlock,
    bsTablePending,
    bsTable
  );

  { TInlineStyle }
  TInlineStyle = (
    isBold,
    isItalic,
    isCode,
    isStrikethrough
  );

  { TInlineStyles }
  TInlineStyles = set of TInlineStyle;

  { TTableAlign }
  TTableAlign = (
    taLeft,
    taCenter,
    taRight
  );

  { TLatexSub }
  TLatexSub = record
    Tex: string;
    Sub: string;
  end;

  { TAdapterOutputCallback }
  TAdapterOutputCallback = reference to procedure(
    const AText: string;
    const AUserData: Pointer);

  { TConsoleAdapter }
  TConsoleAdapter = class(TBaseObject)
  private
    // Line processing state
    FLineMode: Integer;        // 0=detect, 1=stream, 2=buffer
    FLinePrefix: string;       // Accumulated prefix for block detection
    FLineBuffer: string;       // Accumulated content for buffered lines

    // Block state
    FBlockState: TBlockState;
    FCodeLang: string;

    // List state
    FInList: Boolean;
    FListOrdered: Boolean;
    FOrderedNum: Integer;

    // Blockquote state
    FBlockquoteDepth: Integer;

    // Streaming inline parser state
    FPendingChar: Char;
    FInCodeSpan: Boolean;
    FLinkState: Integer;
    FLinkText: string;
    FLinkUrl: string;
    FCodeLineStarted: Boolean;
    // Inline HTML/LaTeX collection (mirrors FLinkState pattern)
    FHtmlState: Integer;   // 0=none, 1=collecting tag until '>'
    FHtmlBuffer: string;
    FMathState: Integer;   // 0=none, 1=inline $..$, 2=display $$..$$,
                           // 3=display saw first closing '$'
    FMathBuffer: string;

    // Table state
    FTableHeader: TArray<string>;
    FTableWidths: TArray<Integer>;
    FTableAligns: TArray<TTableAlign>;

    // Output state
    FColumn: Integer;
    FLineWidth: Integer;
    FIndent: Integer;
    FMarkdown: Boolean;
    FNewlineCount: Integer;
    FWordBuffer: string;
    FStyles: TInlineStyles;
    FOutputBuffer: string;
    FOutputCallback: TCallback<TAdapterOutputCallback>;

    // Character processing (streaming)
    procedure DoProcessChar(const ACh: Char);
    procedure DoDetectChar(const ACh: Char);
    procedure DoStreamChar(const ACh: Char);
    procedure DoStreamResolvePending(const ACh: Char);
    procedure DoFinalizeLine();
    procedure DoStartStreamLine(const AKind: TLineKind;
      const AContent: string; const ALevel: Integer);

    // Full-line processing (buffered lines)
    procedure DoProcessBufferedLine(const ALine: string);

    // Line classification
    function DoClassifyLine(const ALine: string;
      out AContent: string; out ALevel: Integer): TLineKind;

    // Block handlers
    procedure DoHandleBlank();
    procedure DoHandleHeading(const AText: string; const ALevel: Integer);
    procedure DoHandleCodeFenceOpen(const ALang: string);
    procedure DoHandleCodeFenceClose();
    procedure DoHandleCodeContent(const ALine: string);
    procedure DoHandleUnorderedList(const AText: string;
      const ADepth: Integer);
    procedure DoHandleOrderedList(const AText: string;
      const ADepth: Integer);
    procedure DoHandleTaskList(const AText: string;
      const ADepth: Integer; const AChecked: Boolean);
    procedure DoHandleBlockquote(const AText: string;
      const ADepth: Integer);
    procedure DoHandleHRule();
    procedure DoHandleTableRow(const ALine: string);
    procedure DoHandleTableSeparator(const ALine: string);
    procedure DoHandleParagraph(const AText: string);

    // End block helpers
    procedure DoEndList();
    procedure DoEndTable();
    procedure DoEndCurrentBlock();

    // Inline parser
    procedure DoParseInline(const AText: string);
    function DoParseCodeSpan(const AText: string;
      var APos: Integer): Boolean;
    function DoParseLink(const AText: string;
      var APos: Integer): Boolean;
    function DoParseImage(const AText: string;
      var APos: Integer): Boolean;
    // Inline HTML/LaTeX -- streaming path
    procedure DoEmitHtmlTag(const ATag: string);
    procedure DoEmitMath(const ARaw: string);
    // Inline HTML/LaTeX -- buffered path
    function DoParseHtmlTag(const AText: string;
      var APos: Integer): Boolean;
    function DoParseMath(const AText: string;
      var APos: Integer): Boolean;
    // Shared LaTeX linearizer
    function DoApplyLatexSubs(const AText: string): string;
    // String-level inline-math rewriter for non-streaming render paths
    // (headings). Mirrors DoParseMath's span rules exactly; spans are
    // replaced with their linearized glyphs, everything else passes
    // through untouched.
    function DoRewriteInlineMath(const AText: string): string;
    function DoLatexParse(const AText: string; var APos: Integer;
      const AStopChar: Char): string;
    function DoClassifyHtmlBlock(const ALine: string;
      out AContent: string; out ALevel: Integer): TLineKind;
    procedure DoParseAsterisks(const AText: string;
      var APos: Integer);
    procedure DoToggleStyle(const AStyle: TInlineStyle);
    procedure DoReapplyStyles();

    // Rendering helpers
    procedure DoEmit(const AText: string);
    procedure DoEmitRaw(const AText: string);
    procedure DoNewLine();
    procedure DoFlushWordBuffer();
    procedure DoEmitIndent();
    procedure DoEmitBlockquoteBars(const ADepth: Integer);
    procedure DoFlushOutput();

    // Code block rendering
    procedure DoEmitCodeBlockStart(const ALang: string);
    procedure DoEmitCodeBlockLine(const ALine: string);
    procedure DoEmitCodeBlockEnd();

    // Table rendering
    function DoParseTableCells(const ALine: string): TArray<string>;
    function DoParseTableAligns(const ALine: string): TArray<TTableAlign>;
    procedure DoEmitTableBorder(const AKind: Integer);
    procedure DoEmitTableDataRow(const ACells: TArray<string>;
      const ABold: Boolean);
    function DoCalcCellVisualWidth(const AText: string): Integer;
    procedure DoEmitCellContent(const AText: string;
      const AMaxWidth: Integer);

  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Write(const AToken: string);
    procedure Flush();
    procedure Reset();
    procedure SetOutputCallback(const ACallback: TAdapterOutputCallback;
      const AUserData: Pointer);
    property LineWidth: Integer read FLineWidth write FLineWidth;
    property Markdown: Boolean read FMarkdown write FMarkdown;
  end;

implementation

uses
  StdApp.Console;

const
  // Box drawing - single line
  BOX_S_TL = #$250C;
  BOX_S_H  = #$2500;
  BOX_S_TR = #$2510;
  BOX_S_V  = #$2502;
  BOX_S_BL = #$2514;
  BOX_S_BR = #$2518;

  // Box drawing - double line
  BOX_D_TL = #$2554;
  BOX_D_H  = #$2550;
  BOX_D_TR = #$2557;
  BOX_D_V  = #$2551;
  BOX_D_BL = #$255A;
  BOX_D_BR = #$255D;

  // Box drawing - junctions (for tables)
  BOX_S_T_DOWN  = #$252C;
  BOX_S_T_UP    = #$2534;
  BOX_S_T_RIGHT = #$251C;
  BOX_S_T_LEFT  = #$2524;
  BOX_S_CROSS   = #$253C;

  // Bullets
  BULLET_FILLED   = #$2022;
  BULLET_HOLLOW   = #$25E6;
  BULLET_TRIANGLE = #$25B8;
  BULLET_DASH     = #$2013;

  // Checkboxes
  CHECKBOX_EMPTY   = #$2610;
  CHECKBOX_CHECKED = #$2611;

  DEFAULT_LINE_WIDTH = 80;

  // Line processing modes
  LINE_MODE_DETECT = 0;
  LINE_MODE_STREAM = 1;
  LINE_MODE_BUFFER = 2;

  // Table border kind constants
  TABLE_BORDER_TOP = 0;
  TABLE_BORDER_SEP = 1;
  TABLE_BORDER_BOT = 2;

  { LATEX_SUB_COUNT }
  LATEX_SUB_COUNT = 41;

  { LATEX_SUBS }
  // Glyph table for LaTeX commands the linearizer has no structural rule
  // for. Arrows ordered longest-first by convention.
  LATEX_SUBS: array[0..LATEX_SUB_COUNT - 1] of TLatexSub = (
    (Tex: '\longrightarrow'; Sub: #$2192),
    (Tex: '\leftrightarrow'; Sub: #$2194),
    (Tex: '\rightarrow';     Sub: #$2192),
    (Tex: '\leftarrow';      Sub: #$2190),
    (Tex: '\Rightarrow';     Sub: #$21D2),
    (Tex: '\to';             Sub: #$2192),
    (Tex: '\times';          Sub: #$00D7),
    (Tex: '\cdot';           Sub: #$00B7),
    (Tex: '\div';            Sub: #$00F7),
    (Tex: '\pm';             Sub: #$00B1),
    (Tex: '\leq';            Sub: #$2264),
    (Tex: '\geq';            Sub: #$2265),
    (Tex: '\neq';            Sub: #$2260),
    (Tex: '\approx';         Sub: #$2248),
    (Tex: '\equiv';          Sub: #$2261),
    (Tex: '\infty';          Sub: #$221E),
    (Tex: '\sum';            Sub: #$2211),
    (Tex: '\prod';           Sub: #$220F),
    (Tex: '\int';            Sub: #$222B),
    (Tex: '\sqrt';           Sub: #$221A),
    (Tex: '\partial';        Sub: #$2202),
    (Tex: '\nabla';          Sub: #$2207),
    (Tex: '\alpha';          Sub: #$03B1),
    (Tex: '\beta';           Sub: #$03B2),
    (Tex: '\gamma';          Sub: #$03B3),
    (Tex: '\delta';          Sub: #$03B4),
    (Tex: '\epsilon';        Sub: #$03B5),
    (Tex: '\theta';          Sub: #$03B8),
    (Tex: '\lambda';         Sub: #$03BB),
    (Tex: '\mu';             Sub: #$03BC),
    (Tex: '\pi';             Sub: #$03C0),
    (Tex: '\sigma';          Sub: #$03C3),
    (Tex: '\phi';            Sub: #$03C6),
    (Tex: '\omega';          Sub: #$03C9),
    (Tex: '\Delta';          Sub: #$0394),
    (Tex: '\Sigma';          Sub: #$03A3),
    (Tex: '\Omega';          Sub: #$03A9),
    (Tex: '\Pi';             Sub: #$03A0),
    (Tex: '\\';              Sub: ' '),
    (Tex: '\,';              Sub: ' '),
    (Tex: '\;';              Sub: ' ')
  );

  { SUBSCRIPT_DIGITS }
  SUBSCRIPT_DIGITS: array[0..9] of Char = (
    #$2080, #$2081, #$2082, #$2083, #$2084,
    #$2085, #$2086, #$2087, #$2088, #$2089
  );

  { SUPERSCRIPT_DIGITS }
  SUPERSCRIPT_DIGITS: array[0..9] of Char = (
    #$2070, #$00B9, #$00B2, #$00B3, #$2074,
    #$2075, #$2076, #$2077, #$2078, #$2079
  );

{ TConsoleAdapter }

constructor TConsoleAdapter.Create();
begin
  inherited Create();
  FLineMode := LINE_MODE_DETECT;
  FLinePrefix := '';
  FLineBuffer := '';
  FBlockState := bsNone;
  FCodeLang := '';
  FInList := False;
  FListOrdered := False;
  FOrderedNum := 0;
  FBlockquoteDepth := 0;
  FPendingChar := #0;
  FInCodeSpan := False;
  FLinkState := 0;
  FLinkText := '';
  FLinkUrl := '';
  FCodeLineStarted := False;
  FHtmlState := 0;
  FHtmlBuffer := '';
  FMathState := 0;
  FMathBuffer := '';
  FTableHeader := nil;
  FTableWidths := nil;
  FTableAligns := nil;
  FColumn := 0;
  FLineWidth := DEFAULT_LINE_WIDTH;
  FIndent := 0;
  FMarkdown := True;
  FNewlineCount := 0;
  FWordBuffer := '';
  FStyles := [];
  FOutputBuffer := '';
  FOutputCallback := Default(TCallback<TAdapterOutputCallback>);
end;

destructor TConsoleAdapter.Destroy();
begin
  Flush();
  inherited;
end;

procedure TConsoleAdapter.SetOutputCallback(
  const ACallback: TAdapterOutputCallback;
  const AUserData: Pointer);
begin
  FOutputCallback.Callback := ACallback;
  FOutputCallback.UserData := AUserData;
end;

procedure TConsoleAdapter.Reset();
begin
  FLineMode := LINE_MODE_DETECT;
  FLinePrefix := '';
  FLineBuffer := '';
  FBlockState := bsNone;
  FCodeLang := '';
  FInList := False;
  FListOrdered := False;
  FOrderedNum := 0;
  FBlockquoteDepth := 0;
  FPendingChar := #0;
  FInCodeSpan := False;
  FLinkState := 0;
  FLinkText := '';
  FLinkUrl := '';
  FCodeLineStarted := False;
  FHtmlState := 0;
  FHtmlBuffer := '';
  FMathState := 0;
  FMathBuffer := '';
  FTableHeader := nil;
  FTableWidths := nil;
  FTableAligns := nil;
  FColumn := 0;
  FIndent := 0;
  FNewlineCount := 0;
  FWordBuffer := '';
  FStyles := [];
  FOutputBuffer := '';
end;

// --- Output Pipeline ---

procedure TConsoleAdapter.DoEmitRaw(const AText: string);
begin
  if AText.Length > 0 then
  begin
    if (AText[1] <> #10) and (AText[1] <> #27) then
      FNewlineCount := 0;
    FOutputBuffer := FOutputBuffer + AText;
  end;
end;

procedure TConsoleAdapter.DoFlushOutput();
begin
  if FOutputCallback.IsAssigned() and not FOutputBuffer.IsEmpty() then
  begin
    FOutputCallback.Callback(FOutputBuffer, FOutputCallback.UserData);
    FOutputBuffer := '';
  end;
end;

procedure TConsoleAdapter.DoEmit(const AText: string);
var
  LIdx: Integer;
  LCh: Char;
begin
  if AText.IsEmpty() then
    Exit;

  FNewlineCount := 0;

  if not FMarkdown then
  begin
    DoEmitRaw(AText);
    FColumn := FColumn + AText.Length;
    Exit;
  end;

  // Route through word wrapper
  for LIdx := 1 to AText.Length do
  begin
    LCh := AText[LIdx];
    if LCh = ' ' then
    begin
      DoFlushWordBuffer();
      if FColumn > FIndent then
      begin
        DoEmitRaw(' ');
        Inc(FColumn);
      end;
    end
    else
      FWordBuffer := FWordBuffer + LCh;
  end;
end;

procedure TConsoleAdapter.DoNewLine();
begin
  DoFlushWordBuffer();
  Inc(FNewlineCount);
  if FNewlineCount > 2 then
    Exit;
  DoEmitRaw(#10);
  FColumn := 0;
end;

procedure TConsoleAdapter.DoFlushWordBuffer();
begin
  if FWordBuffer.IsEmpty() then
    Exit;

  // Check if word fits on current line
  if (FColumn + FWordBuffer.Length > FLineWidth) and (FColumn > FIndent) then
  begin
    FWordBuffer := FWordBuffer.TrimLeft();
    if FWordBuffer.IsEmpty() then
      Exit;
    // Reset styles before newline to prevent background color bleed
    if FStyles <> [] then
      DoEmitRaw(COLOR_RESET + #27'[K');
    DoEmitRaw(#10);
    FColumn := 0;
    DoEmitIndent();
    // Re-emit blockquote bars on wrapped line
    if FBlockquoteDepth > 0 then
      DoEmitBlockquoteBars(FBlockquoteDepth);
    // Re-apply active styles
    DoReapplyStyles();
  end;

  FNewlineCount := 0;
  DoEmitRaw(FWordBuffer);
  FColumn := FColumn + FWordBuffer.Length;
  FWordBuffer := '';
end;

procedure TConsoleAdapter.DoEmitIndent();
var
  LPad: string;
begin
  if FIndent > 0 then
  begin
    LPad := StringOfChar(' ', FIndent);
    DoEmitRaw(LPad);
    FColumn := FColumn + FIndent;
  end;
end;

procedure TConsoleAdapter.DoEmitBlockquoteBars(const ADepth: Integer);
var
  LIdx: Integer;
begin
  for LIdx := 1 to ADepth do
    DoEmitRaw(COLOR_BLUE + COLOR_BOLD + BOX_S_V + COLOR_RESET + '  ');
  FColumn := FColumn + ADepth * 3;
end;

procedure TConsoleAdapter.DoReapplyStyles();
begin
  if isBold in FStyles then
    DoEmitRaw(COLOR_BOLD);
  if isItalic in FStyles then
    DoEmitRaw(STYLE_ITALIC);
  if isCode in FStyles then
    DoEmitRaw(BG_DARK_GREY + COLOR_YELLOW);
  if isStrikethrough in FStyles then
    DoEmitRaw(STYLE_STRIKE);
end;

// --- Core Loop (Character-by-Character) ---

procedure TConsoleAdapter.Write(const AToken: string);
var
  LIdx: Integer;
begin
  if AToken.IsEmpty() then
    Exit;

  if not FMarkdown then
  begin
    DoEmitRaw(AToken);
    DoFlushOutput();
    Exit;
  end;

  for LIdx := 1 to AToken.Length do
    DoProcessChar(AToken[LIdx]);

  // Flush accumulated output in one callback call per token
  DoFlushOutput();
end;

procedure TConsoleAdapter.DoProcessChar(const ACh: Char);
begin
  if ACh = #13 then
    Exit;
  if ACh = #10 then
  begin
    DoFinalizeLine();
    Exit;
  end;
  case FLineMode of
    LINE_MODE_DETECT: DoDetectChar(ACh);
    LINE_MODE_STREAM: DoStreamChar(ACh);
    LINE_MODE_BUFFER: FLineBuffer := FLineBuffer + ACh;
  end;
end;

procedure TConsoleAdapter.DoDetectChar(const ACh: Char);
var
  LTrimmed: string;
begin
  // Inside code block: detect closing fence or stream content
  if FBlockState = bsCodeBlock then
  begin
    FLinePrefix := FLinePrefix + ACh;
    if CharInSet(ACh, [' ', '`']) then
    begin
      LTrimmed := FLinePrefix.Trim();
      // 3+ backticks seen - always buffer to let classifier decide
      if (LTrimmed.Length >= 3) and LTrimmed.StartsWith('```') then
      begin
        // Potential closing fence - buffer until newline
        FLineMode := LINE_MODE_BUFFER;
        FLineBuffer := FLinePrefix;
        FLinePrefix := '';
      end;
      Exit;
    end;
    // Not a fence character - start streaming code content
    DoEmitRaw(COLOR_CYAN + BOX_S_V + COLOR_RESET + ' ' + BG_BLACK + COLOR_GREEN);
    FColumn := 2;
    DoEmitRaw(FLinePrefix);
    FColumn := FColumn + FLinePrefix.Length;
    FLinePrefix := '';
    FCodeLineStarted := True;
    FLineMode := LINE_MODE_STREAM;
    Exit;
  end;

  // An open multi-line display-math collection consumes every char --
  // line detection is suspended until the block closes or the runaway
  // cap in DoStreamChar fires. Only display math (state >= 2) can be
  // open here: inline state always resolves within its own line.
  if FMathState > 0 then
  begin
    FLineMode := LINE_MODE_STREAM;
    DoStreamChar(ACh);
    Exit;
  end;

  // Normal flow: check first character for block markers
  if CharInSet(ACh, ['#', '`', '-', '*', '_', '>', '|', ' ', '<']) or
     ((ACh >= '0') and (ACh <= '9')) then
  begin
    // Potential block marker - buffer the entire line for classification
    FLineMode := LINE_MODE_BUFFER;
    FLineBuffer := ACh;
    Exit;
  end;

  // Regular character - paragraph, start streaming immediately
  DoStartStreamLine(lkParagraph, '', 0);
  DoStreamChar(ACh);
end;

procedure TConsoleAdapter.DoStartStreamLine(const AKind: TLineKind;
  const AContent: string; const ALevel: Integer);
begin
  // Close table if streaming starts while in table state
  if FBlockState in [bsTable, bsTablePending] then
    DoEndTable();

  case AKind of
    lkParagraph:
    begin
      if FInList then
        DoEndList();
      FBlockquoteDepth := 0;
      FIndent := 0;
      if FColumn = 0 then
        DoEmitIndent();
    end;
  end;
  FLineMode := LINE_MODE_STREAM;
  FLinePrefix := '';
end;

procedure TConsoleAdapter.DoStreamChar(const ACh: Char);
begin
  // Inside code block: emit verbatim, truncate at box boundary
  if FBlockState = bsCodeBlock then
  begin
    if FColumn < FLineWidth - 1 then
    begin
      DoEmitRaw(ACh);
      Inc(FColumn);
    end;
    Exit;
  end;

  // Pending: resolve * or ~
  if FPendingChar <> #0 then
  begin
    DoStreamResolvePending(ACh);
    Exit;
  end;

  // Collecting an HTML tag until '>'
  if FHtmlState = 1 then
  begin
    // First collected char must look like a tag: letter or '/'
    if (FHtmlBuffer = '') and
       not CharInSet(ACh, ['a'..'z', 'A'..'Z', '/']) then
    begin
      FHtmlState := 0;
      DoEmit('<');
      DoStreamChar(ACh); // reprocess as a normal char (FPendingChar precedent)
      Exit;
    end;
    if ACh = '>' then
    begin
      DoEmitHtmlTag(FHtmlBuffer);
      FHtmlBuffer := '';
      FHtmlState := 0;
    end
    else
    begin
      FHtmlBuffer := FHtmlBuffer + ACh;
      // Length cap: no plausible tag this long -- bail raw, no text loss
      if Length(FHtmlBuffer) > 64 then
      begin
        FHtmlState := 0;
        DoEmit('<' + FHtmlBuffer);
        FHtmlBuffer := '';
      end;
    end;
    Exit;
  end;

  // Collecting inline/display math
  if FMathState > 0 then
  begin
    case FMathState of
      1: // inline $...$
      begin
        if FMathBuffer = '' then
        begin
          if ACh = '$' then
          begin
            FMathState := 2; // '$$' -> display math
            Exit;
          end;
          // Currency/false-positive guard: '$' then space or digit = literal
          if CharInSet(ACh, [' ', #9, '0'..'9']) then
          begin
            FMathState := 0;
            DoEmit('$');
            DoStreamChar(ACh);
            Exit;
          end;
        end;
        if ACh = '$' then
        begin
          DoEmitMath(FMathBuffer);
          FMathBuffer := '';
          FMathState := 0;
        end
        else
        begin
          FMathBuffer := FMathBuffer + ACh;
          if Length(FMathBuffer) > 256 then
          begin
            FMathState := 0;
            DoEmit('$' + FMathBuffer);
            FMathBuffer := '';
          end;
        end;
      end;
      2: // display $$...$$, collecting
      begin
        if ACh = '$' then
          FMathState := 3
        else
        begin
          FMathBuffer := FMathBuffer + ACh;
          if Length(FMathBuffer) > 512 then
          begin
            FMathState := 0;
            DoEmit('$$' + FMathBuffer);
            FMathBuffer := '';
          end;
        end;
      end;
      3: // display saw one closing '$', expecting the second
      begin
        if ACh = '$' then
        begin
          DoEmitMath(FMathBuffer);
          FMathBuffer := '';
          FMathState := 0;
        end
        else
        begin
          // Lone '$' inside display content -- keep it, resume collecting
          FMathBuffer := FMathBuffer + '$' + ACh;
          FMathState := 2;
        end;
      end;
    end;
    Exit;
  end;

  // Inside code span
  if FInCodeSpan then
  begin
    if ACh = '`' then
    begin
      FInCodeSpan := False;
      DoToggleStyle(isCode);
    end
    else
      DoEmit(ACh);
    Exit;
  end;

  // Link collection state machine
  if FLinkState > 0 then
  begin
    case FLinkState of
      1: // Collecting [text]
      begin
        if ACh = ']' then
          FLinkState := 2
        else
          FLinkText := FLinkText + ACh;
      end;
      2: // Expecting (
      begin
        if ACh = '(' then
          FLinkState := 3
        else
        begin
          DoEmit('[' + FLinkText + ']');
          DoEmit(ACh);
          FLinkText := '';
          FLinkState := 0;
        end;
      end;
      3: // Collecting (url)
      begin
        if ACh = ')' then
        begin
          DoFlushWordBuffer();
          DoEmitRaw(#27']8;;' + FLinkUrl + #27'\' +
            BG_DARK_GREY + COLOR_CYAN + FLinkText +
            COLOR_RESET + #27']8;;' + #27'\' + #27'[K');
          FColumn := FColumn + FLinkText.Length;
          FLinkText := '';
          FLinkUrl := '';
          FLinkState := 0;
        end
        else
          FLinkUrl := FLinkUrl + ACh;
      end;
    end;
    Exit;
  end;

  // HTML tag start
  if ACh = '<' then
  begin
    FHtmlState := 1;
    FHtmlBuffer := '';
    Exit;
  end;

  // Inline math start
  if ACh = '$' then
  begin
    FMathState := 1;
    FMathBuffer := '';
    Exit;
  end;

  // Code span toggle
  if ACh = '`' then
  begin
    FInCodeSpan := True;
    DoToggleStyle(isCode);
    Exit;
  end;

  // Link start
  if ACh = '[' then
  begin
    FLinkState := 1;
    FLinkText := '';
    FLinkUrl := '';
    Exit;
  end;

  // Bold/italic pending
  if ACh = '*' then
  begin
    FPendingChar := '*';
    Exit;
  end;

  // Strikethrough pending
  if ACh = '~' then
  begin
    FPendingChar := '~';
    Exit;
  end;

  // Regular character
  DoEmit(ACh);
end;

procedure TConsoleAdapter.DoStreamResolvePending(const ACh: Char);
begin
  if ACh = FPendingChar then
  begin
    // Double: ** = bold, ~~ = strikethrough
    if FPendingChar = '*' then
      DoToggleStyle(isBold)
    else if FPendingChar = '~' then
      DoToggleStyle(isStrikethrough);
    FPendingChar := #0;
  end
  else
  begin
    // Single: * = italic, ~ = literal
    if FPendingChar = '*' then
      DoToggleStyle(isItalic)
    else if FPendingChar = '~' then
      DoEmit('~');
    FPendingChar := #0;
    // Process the actual character
    DoStreamChar(ACh);
  end;
end;

procedure TConsoleAdapter.DoFinalizeLine();
var
  LPad: Integer;
begin
  case FLineMode of
    LINE_MODE_DETECT:
    begin
      // Line ended during detection phase
      if FBlockState = bsCodeBlock then
      begin
        // Code block line (possibly empty or just spaces/backticks)
        if not FLinePrefix.IsEmpty() then
        begin
          DoEmitRaw(COLOR_CYAN + BOX_S_V + COLOR_RESET + ' ' +
            BG_BLACK + COLOR_GREEN + FLinePrefix);
          FColumn := FLinePrefix.Length + 2;
        end
        else
        begin
          DoEmitRaw(COLOR_CYAN + BOX_S_V + COLOR_RESET);
          DoEmitRaw(BG_BLACK + StringOfChar(' ', FLineWidth - 2) + COLOR_RESET);
          DoEmitRaw(COLOR_CYAN + BOX_S_V + COLOR_RESET);
          FNewlineCount := 0;
          DoNewLine();
          FColumn := 0;
          FLineMode := LINE_MODE_DETECT;
          FLinePrefix := '';
          FLineBuffer := '';
          FCodeLineStarted := False;
          Exit;
        end;
        // Right padding and border
        LPad := FLineWidth - 1 - FColumn;
        if LPad > 0 then
          DoEmitRaw(StringOfChar(' ', LPad));
        DoEmitRaw(COLOR_RESET + COLOR_CYAN + BOX_S_V + COLOR_RESET);
        FNewlineCount := 0;
        DoNewLine();
        FColumn := 0;
      end
      else if FLinePrefix.IsEmpty() then
      begin
        // Blank line - close table if active
        if FBlockState in [bsTable, bsTablePending] then
          DoEndTable();
        DoHandleBlank();
      end
      else
        DoProcessBufferedLine(FLinePrefix);
    end;

    LINE_MODE_STREAM:
    begin
      if FBlockState = bsCodeBlock then
      begin
        // End of streamed code line - right padding and border
        LPad := FLineWidth - 1 - FColumn;
        if LPad > 0 then
          DoEmitRaw(StringOfChar(' ', LPad));
        DoEmitRaw(COLOR_RESET + COLOR_CYAN + BOX_S_V + COLOR_RESET);
        FNewlineCount := 0;
        DoNewLine();
        FColumn := 0;
      end
      else
      begin
        // End of streamed paragraph line

        // Display math spans lines: an open $$ collection survives the
        // newline (folded to a space) and resumes on the next line. The
        // line-end bookkeeping below must not run -- every char of this
        // line was consumed into the buffer, nothing was emitted. The
        // 512-char cap in DoStreamChar guards unclosed blocks and
        // Flush() reconstructs raw as the final backstop.
        if FMathState >= 2 then
        begin
          if FMathState = 3 then
          begin
            // The consumed lone '$' was content, not a closer
            FMathBuffer := FMathBuffer + '$';
            FMathState := 2;
          end;
          if (FMathBuffer <> '') and (not FMathBuffer.EndsWith(' ')) then
            FMathBuffer := FMathBuffer + ' ';
        end
        else
        begin
          if FPendingChar <> #0 then
          begin
            if FPendingChar = '*' then
              DoToggleStyle(isItalic)
            else if FPendingChar = '~' then
              DoEmit('~');
            FPendingChar := #0;
          end;
          DoFlushWordBuffer();
          if FStyles <> [] then
          begin
            DoEmitRaw(COLOR_RESET);
            FStyles := [];
          end;
          FInCodeSpan := False;
          if FLinkState > 0 then
          begin
            DoEmit('[' + FLinkText);
            FLinkText := '';
            FLinkUrl := '';
            FLinkState := 0;
          end;
          if FHtmlState > 0 then
          begin
            DoEmit('<' + FHtmlBuffer);
            FHtmlBuffer := '';
            FHtmlState := 0;
          end;
          if FMathState = 1 then
          begin
            // Inline $... never spans lines -- reconstruct raw,
            // text loss is forbidden
            DoEmit('$' + FMathBuffer);
            FMathBuffer := '';
            FMathState := 0;
          end;
          DoFlushWordBuffer();
          DoNewLine();
        end;
      end;
    end;

    LINE_MODE_BUFFER:
    begin
      // Process complete buffered line through classification
      DoProcessBufferedLine(FLineBuffer);
    end;
  end;

  // Reset for next line
  FLineMode := LINE_MODE_DETECT;
  FLinePrefix := '';
  FLineBuffer := '';
  FCodeLineStarted := False;
end;

// --- Line Classification ---

function TConsoleAdapter.DoClassifyLine(const ALine: string;
  out AContent: string; out ALevel: Integer): TLineKind;
var
  LTrimmed: string;
  LLeadingSpaces: Integer;
  LIdx: Integer;
  LHashCount: Integer;
  LFirst: Char;
  LAllSame: Boolean;
begin
  AContent := '';
  ALevel := 0;

  // Inside code block: only check for closing fence
  if FBlockState = bsCodeBlock then
  begin
    LTrimmed := ALine.Trim();
    // Closing fence: starts with ``` and rest is only backticks/whitespace
    if LTrimmed.StartsWith('```') then
    begin
      LAllSame := True;
      for LIdx := 4 to LTrimmed.Length do
      begin
        if not CharInSet(LTrimmed[LIdx], ['`', ' ']) then
        begin
          LAllSame := False;
          Break;
        end;
      end;
      if LAllSame then
      begin
        Result := lkCodeFenceClose;
        Exit;
      end;
    end;
    Result := lkCodeContent;
    Exit;
  end;

  LTrimmed := ALine.TrimLeft();
  LLeadingSpaces := ALine.Length - LTrimmed.Length;

  // Blank line
  if LTrimmed.IsEmpty() then
  begin
    Result := lkBlank;
    Exit;
  end;

  // Code fence: ```
  if LTrimmed.StartsWith('```') then
  begin
    AContent := LTrimmed.Substring(3).Trim();
    Result := lkCodeFenceOpen;
    Exit;
  end;

  // Heading: # through ######
  if LTrimmed.StartsWith('#') then
  begin
    LHashCount := 0;
    for LIdx := 1 to LTrimmed.Length do
    begin
      if LTrimmed[LIdx] = '#' then
        Inc(LHashCount)
      else
        Break;
    end;
    if (LHashCount >= 1) and (LHashCount <= 6) and
       (LTrimmed.Length > LHashCount) and (LTrimmed[LHashCount + 1] = ' ') then
    begin
      ALevel := LHashCount;
      AContent := LTrimmed.Substring(LHashCount + 1).Trim();
      // Strip trailing #s
      while AContent.EndsWith('#') do
        AContent := AContent.Substring(0, AContent.Length - 1).TrimRight();
      Result := lkHeading;
      Exit;
    end;
  end;

  // Horizontal rule: 3+ of same char (- * _) only
  if (LTrimmed.Length >= 3) and CharInSet(LTrimmed[1], ['-', '*', '_']) then
  begin
    LFirst := LTrimmed[1];
    LAllSame := True;
    for LIdx := 2 to LTrimmed.Length do
    begin
      if LTrimmed[LIdx] <> LFirst then
      begin
        LAllSame := False;
        Break;
      end;
    end;
    if LAllSame then
    begin
      Result := lkHRule;
      Exit;
    end;
  end;

  // Task list: - [ ] or - [x] or - [X]
  if LTrimmed.StartsWith('- [ ] ') or
     LTrimmed.StartsWith('- [x] ') or
     LTrimmed.StartsWith('- [X] ') then
  begin
    ALevel := LLeadingSpaces div 2;
    AContent := LTrimmed.Substring(6);
    Result := lkTaskList;
    Exit;
  end;

  // Unordered list: - or * followed by space
  if (LTrimmed.Length >= 2) and
     CharInSet(LTrimmed[1], ['-', '*']) and (LTrimmed[2] = ' ') then
  begin
    ALevel := LLeadingSpaces div 2;
    AContent := LTrimmed.Substring(2);
    Result := lkUnorderedList;
    Exit;
  end;

  // Ordered list: digit(s) . space
  if (LTrimmed.Length >= 3) and (LTrimmed[1] >= '0') and (LTrimmed[1] <= '9') then
  begin
    LIdx := 1;
    while (LIdx <= LTrimmed.Length) and
          (LTrimmed[LIdx] >= '0') and (LTrimmed[LIdx] <= '9') do
      Inc(LIdx);
    if (LIdx <= LTrimmed.Length - 1) and
       (LTrimmed[LIdx] = '.') and (LTrimmed[LIdx + 1] = ' ') then
    begin
      ALevel := LLeadingSpaces div 2;
      AContent := LTrimmed.Substring(LIdx + 1);
      Result := lkOrderedList;
      Exit;
    end;
  end;

  // Blockquote: >
  if LTrimmed.StartsWith('>') then
  begin
    LIdx := 1;
    ALevel := 0;
    while LIdx <= LTrimmed.Length do
    begin
      if LTrimmed[LIdx] = '>' then
      begin
        Inc(ALevel);
        Inc(LIdx);
        if (LIdx <= LTrimmed.Length) and (LTrimmed[LIdx] = ' ') then
          Inc(LIdx);
      end
      else
        Break;
    end;
    AContent := LTrimmed.Substring(LIdx - 1);
    Result := lkBlockquote;
    Exit;
  end;

  // Table separator: |---| pattern (only |, -, :, spaces)
  if LTrimmed.StartsWith('|') and (LTrimmed.IndexOf('-') >= 0) then
  begin
    LAllSame := True;
    for LIdx := 1 to LTrimmed.Length do
    begin
      if not CharInSet(LTrimmed[LIdx], ['|', '-', ':', ' ']) then
      begin
        LAllSame := False;
        Break;
      end;
    end;
    if LAllSame then
    begin
      Result := lkTableSeparator;
      Exit;
    end;
  end;

  // Table row: starts and ends with |
  if LTrimmed.StartsWith('|') and LTrimmed.EndsWith('|') and
     (LTrimmed.Length >= 3) then
  begin
    AContent := LTrimmed;
    Result := lkTableRow;
    Exit;
  end;

  // Block-level HTML tag on its own line
  if LTrimmed.StartsWith('<') then
  begin
    Result := DoClassifyHtmlBlock(LTrimmed, AContent, ALevel);
    if Result <> lkParagraph then
      Exit;
  end;

  // Display math line: $$ ... $$ (buffered path only; the streaming path
  // handles line-start $$ via the FMathState machine)
  if LTrimmed.StartsWith('$$') then
  begin
    AContent := LTrimmed;
    Result := lkMathBlock;
    Exit;
  end;

  // Default: paragraph
  AContent := LTrimmed;
  Result := lkParagraph;
end;

// --- Main Dispatcher ---

procedure TConsoleAdapter.DoProcessBufferedLine(const ALine: string);
var
  LKind: TLineKind;
  LContent: string;
  LLevel: Integer;
  LTrimmed: string;
  LDepth: Integer;
  LChecked: Boolean;
  LIdx: Integer;
  LJoined: string;
begin
  LKind := DoClassifyLine(ALine, LContent, LLevel);

  // Handle based on current block state
  case FBlockState of
    bsCodeBlock:
    begin
      if LKind = lkCodeFenceClose then
        DoHandleCodeFenceClose()
      else
        DoHandleCodeContent(ALine);
      Exit;
    end;

    bsTablePending:
    begin
      if LKind = lkTableSeparator then
      begin
        DoHandleTableSeparator(ALine);
        Exit;
      end;
      // Not a table -- flush buffered header as paragraph
      LJoined := '';
      for LIdx := 0 to High(FTableHeader) do
      begin
        if LIdx > 0 then
          LJoined := LJoined + ' | ';
        LJoined := LJoined + FTableHeader[LIdx];
      end;
      FBlockState := bsNone;
      FTableHeader := nil;
      DoHandleParagraph(LJoined);
      // Fall through to process current line
    end;

    bsTable:
    begin
      if LKind = lkTableRow then
      begin
        DoHandleTableRow(ALine);
        Exit;
      end;
      DoEndTable();
      // Fall through to process current line
    end;
  end;

  // End list if non-list, non-blank line
  if FInList and not (LKind in [lkUnorderedList, lkOrderedList,
    lkTaskList, lkBlank]) then
    DoEndList();

  // Reset blockquote depth and indent if not a blockquote line
  // (list/blockquote handlers set their own FIndent per line)
  if LKind <> lkBlockquote then
  begin
    FBlockquoteDepth := 0;
    FIndent := 0;
  end;

  case LKind of
    lkBlank:
      DoHandleBlank();

    lkHeading:
      DoHandleHeading(LContent, LLevel);

    lkCodeFenceOpen:
      DoHandleCodeFenceOpen(LContent);

    lkHRule:
      DoHandleHRule();

    lkBlockquote:
      DoHandleBlockquote(LContent, LLevel);

    lkUnorderedList:
      DoHandleUnorderedList(LContent, LLevel);

    lkOrderedList:
    begin
      LTrimmed := ALine.TrimLeft();
      LDepth := (ALine.Length - LTrimmed.Length) div 2;
      DoHandleOrderedList(LContent, LDepth);
    end;

    lkTaskList:
    begin
      LTrimmed := ALine.TrimLeft();
      LDepth := (ALine.Length - LTrimmed.Length) div 2;
      LChecked := LTrimmed.StartsWith('- [x]') or
                  LTrimmed.StartsWith('- [X]');
      DoHandleTaskList(LContent, LDepth, LChecked);
    end;

    lkTableRow:
      DoHandleTableRow(ALine);

    lkParagraph:
      DoHandleParagraph(LContent);

    lkMathBlock:
      DoHandleParagraph(DoApplyLatexSubs(
        LContent.TrimLeft(['$']).TrimRight(['$']).Trim()));
  end;
end;

// --- End Block Helpers ---

procedure TConsoleAdapter.DoEndCurrentBlock();
begin
  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;
  if FInList then
    DoEndList();
  if FBlockState = bsTable then
    DoEndTable();
  FIndent := 0;
  FBlockquoteDepth := 0;
end;

procedure TConsoleAdapter.DoEndList();
begin
  FInList := False;
  FListOrdered := False;
  FOrderedNum := 0;
  FIndent := 0;
end;

procedure TConsoleAdapter.DoEndTable();
begin
  if FBlockState = bsTable then
    DoEmitTableBorder(TABLE_BORDER_BOT);
  FBlockState := bsNone;
  FTableHeader := nil;
  FTableWidths := nil;
  FTableAligns := nil;
end;

// --- Block Handlers ---

procedure TConsoleAdapter.DoHandleBlank();
begin
  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;
  DoNewLine();
end;

procedure TConsoleAdapter.DoHandleHeading(const AText: string;
  const ALevel: Integer);
var
  LText: string;
  LUpper: string;
  LBarWidth: Integer;
  LBar: string;
begin
  DoEndCurrentBlock();

  // Inline $...$ math is linearized before rendering so heading glyphs
  // match body text AND the box/underline widths measure the rendered
  // string, not the raw LaTeX source
  LText := DoRewriteInlineMath(AText);

  case ALevel of
    1:
    begin
      // H1: Double-border box, CYAN BOLD, uppercase
      LUpper := LText.ToUpper();
      LBarWidth := LUpper.Length + 4;
      if LBarWidth > FLineWidth then
        LBarWidth := FLineWidth;
      LBar := StringOfChar(BOX_D_H, LBarWidth - 2);
      DoNewLine();
      DoEmitRaw(COLOR_CYAN + COLOR_BOLD);
      DoEmitRaw(BOX_D_TL + LBar + BOX_D_TR);
      DoNewLine();
      DoEmitRaw(BOX_D_V + ' ' + LUpper + ' ' + BOX_D_V);
      DoNewLine();
      DoEmitRaw(BOX_D_BL + LBar + BOX_D_BR);
      DoEmitRaw(COLOR_RESET);
      DoNewLine();
    end;
    2:
    begin
      // H2: Single underline, YELLOW BOLD
      DoNewLine();
      DoEmitRaw(COLOR_YELLOW + COLOR_BOLD);
      DoEmitRaw(LText);
      DoNewLine();
      DoEmitRaw(StringOfChar(BOX_S_H, LText.Length));
      DoEmitRaw(COLOR_RESET);
      DoNewLine();
    end;
    3:
    begin
      // H3: GREEN BOLD
      DoNewLine();
      DoEmitRaw(COLOR_GREEN + COLOR_BOLD);
      DoEmitRaw(LText);
      DoEmitRaw(COLOR_RESET);
      DoNewLine();
    end;
    4:
    begin
      // H4: MAGENTA BOLD
      DoNewLine();
      DoEmitRaw(COLOR_MAGENTA + COLOR_BOLD);
      DoEmitRaw(LText);
      DoEmitRaw(COLOR_RESET);
      DoNewLine();
    end;
    5:
    begin
      // H5: CYAN UNDERLINE
      DoNewLine();
      DoEmitRaw(COLOR_CYAN + STYLE_UNDERLINE);
      DoEmitRaw(LText);
      DoEmitRaw(COLOR_RESET);
      DoNewLine();
    end;
    6:
    begin
      // H6: DIM
      DoNewLine();
      DoEmitRaw(STYLE_DIM);
      DoEmitRaw(LText);
      DoEmitRaw(COLOR_RESET);
      DoNewLine();
    end;
  end;
  FColumn := 0;
end;

procedure TConsoleAdapter.DoHandleHRule();
begin
  DoEndCurrentBlock();
  DoNewLine();
  DoEmitRaw(STYLE_DIM + StringOfChar(BOX_D_H, FLineWidth) + COLOR_RESET);
  FNewlineCount := 0;
  DoNewLine();
  FColumn := 0;
end;

// --- Code Block Handlers ---

procedure TConsoleAdapter.DoHandleCodeFenceOpen(const ALang: string);
begin
  DoEndCurrentBlock();
  FBlockState := bsCodeBlock;
  FCodeLang := ALang;
  DoEmitCodeBlockStart(ALang);
end;

procedure TConsoleAdapter.DoHandleCodeFenceClose();
begin
  DoEmitCodeBlockEnd();
  FBlockState := bsNone;
  FCodeLang := '';
end;

procedure TConsoleAdapter.DoHandleCodeContent(const ALine: string);
begin
  DoEmitCodeBlockLine(ALine);
end;

procedure TConsoleAdapter.DoEmitCodeBlockStart(const ALang: string);
var
  LLabel: string;
  LBarWidth: Integer;
  LBar: string;
begin
  DoNewLine();
  LBarWidth := FLineWidth - 2;
  if LBarWidth < 10 then
    LBarWidth := 10;

  if not ALang.IsEmpty() then
    LLabel := ' ' + ALang + ' '
  else
    LLabel := '';

  LBar := StringOfChar(BOX_S_H, LBarWidth - LLabel.Length);
  DoEmitRaw(COLOR_CYAN + BOX_S_TL + LLabel + LBar + BOX_S_TR + COLOR_RESET);
  FNewlineCount := 0;
  DoNewLine();
  FColumn := 0;
end;

procedure TConsoleAdapter.DoEmitCodeBlockLine(const ALine: string);
var
  LPad: Integer;
  LMaxContent: Integer;
  LContent: string;
begin
  LMaxContent := FLineWidth - 3; // 2 for "│ " left, 1 for "│" right
  if LMaxContent < 1 then
    LMaxContent := 1;

  // Truncate content to fit within box
  if ALine.Length > LMaxContent then
    LContent := ALine.Substring(0, LMaxContent)
  else
    LContent := ALine;

  // Left border
  DoEmitRaw(COLOR_CYAN + BOX_S_V + COLOR_RESET + ' ');
  // Content
  DoEmitRaw(BG_BLACK + COLOR_GREEN + LContent);
  FColumn := LContent.Length + 2;
  // Right padding
  LPad := FLineWidth - 1 - FColumn;
  if LPad > 0 then
    DoEmitRaw(StringOfChar(' ', LPad));
  // Right border
  DoEmitRaw(COLOR_RESET + COLOR_CYAN + BOX_S_V + COLOR_RESET);
  FNewlineCount := 0;
  DoNewLine();
  FColumn := 0;
end;

procedure TConsoleAdapter.DoEmitCodeBlockEnd();
var
  LBarWidth: Integer;
begin
  LBarWidth := FLineWidth - 2;
  if LBarWidth < 10 then
    LBarWidth := 10;
  if FColumn > 0 then
    DoNewLine();
  DoEmitRaw(COLOR_CYAN + BOX_S_BL + StringOfChar(BOX_S_H, LBarWidth) +
    BOX_S_BR + COLOR_RESET);
  FNewlineCount := 0;
  DoNewLine();
  FColumn := 0;
end;

// --- List Handlers ---

procedure TConsoleAdapter.DoHandleUnorderedList(const AText: string;
  const ADepth: Integer);
var
  LBulletIndent: Integer;
  LBullet: string;
begin
  if not FInList or FListOrdered then
  begin
    if FInList then
      DoEndList();
    FInList := True;
    FListOrdered := False;
  end;

  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;

  LBulletIndent := ADepth * 2;
  FIndent := LBulletIndent + 3;

  case ADepth of
    0: LBullet := BULLET_FILLED + '  ';
    1: LBullet := BULLET_HOLLOW + '  ';
    2: LBullet := BULLET_TRIANGLE + '  ';
  else
    LBullet := BULLET_DASH + '  ';
  end;

  DoEmitRaw(COLOR_RESET + StringOfChar(' ', LBulletIndent) + LBullet);
  FColumn := FIndent;
  DoParseInline(AText);
  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;
  DoNewLine();
end;

procedure TConsoleAdapter.DoHandleOrderedList(const AText: string;
  const ADepth: Integer);
var
  LBulletIndent: Integer;
  LNumStr: string;
begin
  if not FInList or not FListOrdered then
  begin
    if FInList then
      DoEndList();
    FInList := True;
    FListOrdered := True;
    FOrderedNum := 0;
  end;

  Inc(FOrderedNum);

  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;

  LBulletIndent := ADepth * 2;
  LNumStr := FOrderedNum.ToString();
  FIndent := LBulletIndent + LNumStr.Length + 2;

  DoEmitRaw(COLOR_RESET + StringOfChar(' ', LBulletIndent) +
    COLOR_YELLOW + COLOR_BOLD + LNumStr + '.' + COLOR_RESET + ' ');
  FColumn := FIndent;
  DoParseInline(AText);
  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;
  DoNewLine();
end;

procedure TConsoleAdapter.DoHandleTaskList(const AText: string;
  const ADepth: Integer; const AChecked: Boolean);
var
  LBulletIndent: Integer;
  LCheckbox: string;
begin
  if not FInList then
  begin
    FInList := True;
    FListOrdered := False;
  end;

  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;

  LBulletIndent := ADepth * 2;
  FIndent := LBulletIndent + 3;

  if AChecked then
    LCheckbox := COLOR_GREEN + CHECKBOX_CHECKED + COLOR_RESET + '  '
  else
    LCheckbox := STYLE_DIM + CHECKBOX_EMPTY + COLOR_RESET + '  ';

  DoEmitRaw(COLOR_RESET + StringOfChar(' ', LBulletIndent) + LCheckbox);
  FColumn := FIndent;
  DoParseInline(AText);
  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;
  DoNewLine();
end;

// --- Blockquote Handler ---

procedure TConsoleAdapter.DoHandleBlockquote(const AText: string;
  const ADepth: Integer);
var
  LAlertType: string;
  LAlertColor: string;
  LAlertIcon: string;
  LRemainder: string;
begin
  FBlockquoteDepth := ADepth;
  FIndent := ADepth * 3;

  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;

  // Check for GFM alerts: [!NOTE], [!TIP], etc.
  LAlertType := '';
  LRemainder := AText;

  if AText.StartsWith('[!NOTE]') then
  begin
    LAlertType := 'NOTE';
    LAlertColor := COLOR_BLUE;
    LAlertIcon := #$2139;
    LRemainder := AText.Substring(7).Trim();
  end
  else if AText.StartsWith('[!TIP]') then
  begin
    LAlertType := 'TIP';
    LAlertColor := COLOR_GREEN;
    LAlertIcon := #$25C6;
    LRemainder := AText.Substring(6).Trim();
  end
  else if AText.StartsWith('[!IMPORTANT]') then
  begin
    LAlertType := 'IMPORTANT';
    LAlertColor := COLOR_MAGENTA;
    LAlertIcon := #$2757;
    LRemainder := AText.Substring(12).Trim();
  end
  else if AText.StartsWith('[!WARNING]') then
  begin
    LAlertType := 'WARNING';
    LAlertColor := COLOR_YELLOW;
    LAlertIcon := #$26A0;
    LRemainder := AText.Substring(10).Trim();
  end
  else if AText.StartsWith('[!CAUTION]') then
  begin
    LAlertType := 'CAUTION';
    LAlertColor := COLOR_RED;
    LAlertIcon := #$2622;
    LRemainder := AText.Substring(10).Trim();
  end;

  // Emit blockquote bars
  DoEmitBlockquoteBars(ADepth);

  if not LAlertType.IsEmpty() then
  begin
    // Emit alert label
    DoEmitRaw(LAlertColor + COLOR_BOLD + LAlertIcon + ' ' +
      LAlertType + COLOR_RESET);
    FColumn := FColumn + LAlertType.Length + 2;
    if not LRemainder.IsEmpty() then
    begin
      DoNewLine();
      DoEmitBlockquoteBars(ADepth);
      DoParseInline(LRemainder);
    end;
  end
  else
  begin
    // Normal blockquote text
    DoParseInline(LRemainder);
  end;

  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;
  DoNewLine();
end;

// --- Table Handlers ---

function TConsoleAdapter.DoParseTableCells(const ALine: string): TArray<string>;
var
  LTrimmed: string;
  LParts: TArray<string>;
  LIdx: Integer;
  LCount: Integer;
begin
  LTrimmed := ALine.Trim();
  // Strip leading and trailing |
  if LTrimmed.StartsWith('|') then
    LTrimmed := LTrimmed.Substring(1);
  if LTrimmed.EndsWith('|') then
    LTrimmed := LTrimmed.Substring(0, LTrimmed.Length - 1);

  LParts := LTrimmed.Split(['|']);
  SetLength(Result, Length(LParts));
  LCount := 0;
  for LIdx := 0 to High(LParts) do
  begin
    Result[LCount] := LParts[LIdx].Trim();
    Inc(LCount);
  end;
  SetLength(Result, LCount);
end;

function TConsoleAdapter.DoParseTableAligns(
  const ALine: string): TArray<TTableAlign>;
var
  LCells: TArray<string>;
  LIdx: Integer;
  LCell: string;
begin
  LCells := DoParseTableCells(ALine);
  SetLength(Result, Length(LCells));
  for LIdx := 0 to High(LCells) do
  begin
    LCell := LCells[LIdx].Trim();
    if LCell.StartsWith(':') and LCell.EndsWith(':') then
      Result[LIdx] := taCenter
    else if LCell.EndsWith(':') then
      Result[LIdx] := taRight
    else
      Result[LIdx] := taLeft;
  end;
end;

procedure TConsoleAdapter.DoHandleTableRow(const ALine: string);
var
  LCells: TArray<string>;
begin
  LCells := DoParseTableCells(ALine);

  case FBlockState of
    bsNone:
    begin
      // First row -- buffer as potential header
      FTableHeader := LCells;
      FBlockState := bsTablePending;
    end;

    bsTable:
    begin
      // Data row
      DoEmitTableDataRow(LCells, False);
    end;
  end;
end;

procedure TConsoleAdapter.DoHandleTableSeparator(const ALine: string);
var
  LIdx: Integer;
  LCellWidth: Integer;
  LHeaderWidth: Integer;
  LSepCells: TArray<string>;
  LSepWidth: Integer;
  LColCount: Integer;
begin
  FTableAligns := DoParseTableAligns(ALine);
  LSepCells := DoParseTableCells(ALine);

  // Column count is max of header and separator columns
  LColCount := Length(FTableHeader);
  if Length(LSepCells) > LColCount then
    LColCount := Length(LSepCells);

  // Calculate column widths from separator dashes and header text
  SetLength(FTableWidths, LColCount);
  for LIdx := 0 to LColCount - 1 do
  begin
    // Separator dash count is the primary width source
    if LIdx <= High(LSepCells) then
      LSepWidth := LSepCells[LIdx].Length
    else
      LSepWidth := 0;

    // Header visual width as fallback
    if LIdx <= High(FTableHeader) then
      LHeaderWidth := DoCalcCellVisualWidth(FTableHeader[LIdx])
    else
      LHeaderWidth := 0;

    // Use the larger of separator width and header width, plus padding
    if LSepWidth > LHeaderWidth then
      LCellWidth := LSepWidth + 2
    else
      LCellWidth := LHeaderWidth + 2;

    if LCellWidth < 5 then
      LCellWidth := 5;
    FTableWidths[LIdx] := LCellWidth;
  end;

  FBlockState := bsTable;

  // Emit top border
  DoEmitTableBorder(TABLE_BORDER_TOP);
  // Emit header row
  DoEmitTableDataRow(FTableHeader, True);
  // Emit separator
  DoEmitTableBorder(TABLE_BORDER_SEP);
end;

procedure TConsoleAdapter.DoEmitTableBorder(const AKind: Integer);
var
  LIdx: Integer;
  LLeft: string;
  LMid: string;
  LRight: string;
begin
  case AKind of
    TABLE_BORDER_TOP:
    begin
      LLeft := BOX_S_TL;
      LMid := BOX_S_T_DOWN;
      LRight := BOX_S_TR;
    end;
    TABLE_BORDER_SEP:
    begin
      LLeft := BOX_S_T_RIGHT;
      LMid := BOX_S_CROSS;
      LRight := BOX_S_T_LEFT;
    end;
  else // TABLE_BORDER_BOT
    LLeft := BOX_S_BL;
    LMid := BOX_S_T_UP;
    LRight := BOX_S_BR;
  end;

  DoEmitRaw(COLOR_CYAN + LLeft);
  for LIdx := 0 to High(FTableWidths) do
  begin
    if LIdx > 0 then
      DoEmitRaw(LMid);
    DoEmitRaw(StringOfChar(BOX_S_H, FTableWidths[LIdx]));
  end;
  DoEmitRaw(LRight + COLOR_RESET);
  FNewlineCount := 0;
  DoNewLine();
  FColumn := 0;
end;

procedure TConsoleAdapter.DoEmitTableDataRow(const ACells: TArray<string>;
  const ABold: Boolean);
var
  LIdx: Integer;
  LCell: string;
  LWidth: Integer;
  LVisualWidth: Integer;
  LPadTotal: Integer;
  LPadLeft: Integer;
  LPadRight: Integer;
begin
  DoEmitRaw(COLOR_CYAN + BOX_S_V + COLOR_RESET);
  for LIdx := 0 to High(FTableWidths) do
  begin
    LWidth := FTableWidths[LIdx];
    if LIdx <= High(ACells) then
      LCell := ACells[LIdx]
    else
      LCell := '';

    LVisualWidth := DoCalcCellVisualWidth(LCell);

    // Truncate visual content if too wide (use raw length as rough guard)
    if LVisualWidth > LWidth - 2 then
      LVisualWidth := LWidth - 2;

    LPadTotal := LWidth - LVisualWidth;

    // Align
    if (LIdx <= High(FTableAligns)) and (FTableAligns[LIdx] = taCenter) then
    begin
      LPadLeft := LPadTotal div 2;
      LPadRight := LPadTotal - LPadLeft;
    end
    else if (LIdx <= High(FTableAligns)) and
            (FTableAligns[LIdx] = taRight) then
    begin
      LPadLeft := LPadTotal - 1;
      LPadRight := 1;
    end
    else
    begin
      LPadLeft := 1;
      LPadRight := LPadTotal - 1;
    end;

    DoEmitRaw(StringOfChar(' ', LPadLeft));
    if ABold then
      DoEmitRaw(COLOR_CYAN + COLOR_BOLD);
    DoEmitCellContent(LCell, LWidth - 2);
    if ABold then
      DoEmitRaw(COLOR_RESET);
    DoEmitRaw(StringOfChar(' ', LPadRight));
    DoEmitRaw(COLOR_CYAN + BOX_S_V + COLOR_RESET);
  end;
  FNewlineCount := 0;
  DoNewLine();
  FColumn := 0;
end;

function TConsoleAdapter.DoCalcCellVisualWidth(const AText: string): Integer;
var
  LPos: Integer;
begin
  Result := 0;
  LPos := 1;
  while LPos <= AText.Length do
  begin
    // ** bold markers
    if (AText[LPos] = '*') and (LPos < AText.Length) and
       (AText[LPos + 1] = '*') then
    begin
      Inc(LPos, 2);
      Continue;
    end;
    // ~~ strikethrough markers
    if (AText[LPos] = '~') and (LPos < AText.Length) and
       (AText[LPos + 1] = '~') then
    begin
      Inc(LPos, 2);
      Continue;
    end;
    // ` code markers
    if AText[LPos] = '`' then
    begin
      Inc(LPos);
      Continue;
    end;
    // * italic marker (single)
    if AText[LPos] = '*' then
    begin
      Inc(LPos);
      Continue;
    end;
    // Visible character
    Inc(Result);
    Inc(LPos);
  end;
end;

procedure TConsoleAdapter.DoEmitCellContent(const AText: string;
  const AMaxWidth: Integer);
var
  LPos: Integer;
  LCh: Char;
  LInBold: Boolean;
  LInItalic: Boolean;
  LInCode: Boolean;
  LInStrike: Boolean;
  LEmitted: Integer;
begin
  LInBold := False;
  LInItalic := False;
  LInCode := False;
  LInStrike := False;
  LEmitted := 0;
  LPos := 1;
  while LPos <= AText.Length do
  begin
    LCh := AText[LPos];

    // ** bold toggle
    if (LCh = '*') and (LPos < AText.Length) and (AText[LPos + 1] = '*') then
    begin
      LInBold := not LInBold;
      if LInBold then
        DoEmitRaw(COLOR_BOLD)
      else
        DoEmitRaw(COLOR_RESET);
      Inc(LPos, 2);
      Continue;
    end;

    // ~~ strikethrough toggle
    if (LCh = '~') and (LPos < AText.Length) and (AText[LPos + 1] = '~') then
    begin
      LInStrike := not LInStrike;
      if LInStrike then
        DoEmitRaw(STYLE_STRIKE)
      else
        DoEmitRaw(COLOR_RESET);
      Inc(LPos, 2);
      Continue;
    end;

    // ` code toggle
    if LCh = '`' then
    begin
      LInCode := not LInCode;
      if LInCode then
        DoEmitRaw(BG_DARK_GREY + COLOR_YELLOW)
      else
        DoEmitRaw(COLOR_RESET + #27'[K');
      Inc(LPos);
      Continue;
    end;

    // * italic toggle (single, after ** check)
    if LCh = '*' then
    begin
      LInItalic := not LInItalic;
      if LInItalic then
        DoEmitRaw(STYLE_ITALIC)
      else
        DoEmitRaw(COLOR_RESET);
      Inc(LPos);
      Continue;
    end;

    // Stop if we've reached max visual width
    if LEmitted >= AMaxWidth then
    begin
      Inc(LPos);
      Continue;
    end;

    // Regular character
    DoEmitRaw(LCh);
    Inc(LEmitted);
    Inc(LPos);
  end;

  // Reset any lingering styles
  if LInBold or LInItalic or LInCode or LInStrike then
    DoEmitRaw(COLOR_RESET);
end;

// --- Paragraph Handler ---

procedure TConsoleAdapter.DoHandleParagraph(const AText: string);
begin
  if FColumn = 0 then
    DoEmitIndent();
  DoParseInline(AText);
  DoFlushWordBuffer();
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;
  DoNewLine();
end;

// --- Inline Parser ---

procedure TConsoleAdapter.DoToggleStyle(const AStyle: TInlineStyle);
begin
  DoFlushWordBuffer();
  if AStyle in FStyles then
  begin
    Exclude(FStyles, AStyle);
    DoEmitRaw(COLOR_RESET);
    // Clear line when background-affecting style ends
    if AStyle = isCode then
      DoEmitRaw(#27'[K');
    // Re-apply remaining active styles
    DoReapplyStyles();
  end
  else
  begin
    Include(FStyles, AStyle);
    case AStyle of
      isBold:          DoEmitRaw(COLOR_BOLD);
      isItalic:        DoEmitRaw(STYLE_ITALIC);
      isCode:          DoEmitRaw(BG_DARK_GREY + COLOR_YELLOW);
      isStrikethrough: DoEmitRaw(STYLE_STRIKE);
    end;
  end;
end;

function TConsoleAdapter.DoParseCodeSpan(const AText: string;
  var APos: Integer): Boolean;
var
  LStart: Integer;
  LEnd: Integer;
  LContent: string;
begin
  Result := False;
  // APos is at the opening backtick
  LStart := APos + 1;
  LEnd := LStart;
  while LEnd <= AText.Length do
  begin
    if AText[LEnd] = '`' then
    begin
      LContent := AText.Substring(LStart - 1, LEnd - LStart);
      DoFlushWordBuffer();
      // Wrap to new line if code span doesn't fit
      if (FColumn + LContent.Length > FLineWidth) and (FColumn > FIndent) then
      begin
        DoEmitRaw(COLOR_RESET + #27'[K' + #10);
        FColumn := 0;
        DoEmitIndent();
        if FBlockquoteDepth > 0 then
          DoEmitBlockquoteBars(FBlockquoteDepth);
      end;
      DoEmitRaw(BG_DARK_GREY + COLOR_YELLOW + LContent +
        COLOR_RESET + #27'[K');
      FColumn := FColumn + LContent.Length;
      APos := LEnd + 1;
      Result := True;
      Exit;
    end;
    Inc(LEnd);
  end;
end;

function TConsoleAdapter.DoParseLink(const AText: string;
  var APos: Integer): Boolean;
var
  LBracketEnd: Integer;
  LParenStart: Integer;
  LParenEnd: Integer;
  LLinkText: string;
  LLinkUrl: string;
begin
  Result := False;
  // APos is at '['
  LBracketEnd := APos + 1;
  while LBracketEnd <= AText.Length do
  begin
    if AText[LBracketEnd] = ']' then
      Break;
    Inc(LBracketEnd);
  end;
  if LBracketEnd > AText.Length then
    Exit;

  // Check for ( immediately after ]
  LParenStart := LBracketEnd + 1;
  if (LParenStart > AText.Length) or (AText[LParenStart] <> '(') then
    Exit;

  // Find closing )
  LParenEnd := LParenStart + 1;
  while LParenEnd <= AText.Length do
  begin
    if AText[LParenEnd] = ')' then
      Break;
    Inc(LParenEnd);
  end;
  if LParenEnd > AText.Length then
    Exit;

  LLinkText := AText.Substring(APos, LBracketEnd - APos - 1);
  LLinkUrl := AText.Substring(LParenStart, LParenEnd - LParenStart - 1);

  DoFlushWordBuffer();
  // Wrap to new line if link text doesn't fit
  if (FColumn + LLinkText.Length > FLineWidth) and (FColumn > FIndent) then
  begin
    DoEmitRaw(COLOR_RESET + #27'[K' + #10);
    FColumn := 0;
    DoEmitIndent();
    if FBlockquoteDepth > 0 then
      DoEmitBlockquoteBars(FBlockquoteDepth);
  end;
  // OSC 8 clickable hyperlink
  DoEmitRaw(
    #27']8;;' + LLinkUrl + #27'\' +
    BG_DARK_GREY + COLOR_CYAN + LLinkText +
    COLOR_RESET +
    #27']8;;' + #27'\' +
    #27'[K');
  FColumn := FColumn + LLinkText.Length;

  APos := LParenEnd + 1;
  Result := True;
end;

function TConsoleAdapter.DoParseImage(const AText: string;
  var APos: Integer): Boolean;
var
  LSavePos: Integer;
  LBracketEnd: Integer;
  LParenStart: Integer;
  LParenEnd: Integer;
  LAlt: string;
begin
  Result := False;
  // APos is at '!', APos+1 is '['
  LSavePos := APos;
  Inc(APos); // skip '!'

  LBracketEnd := APos + 1;
  while LBracketEnd <= AText.Length do
  begin
    if AText[LBracketEnd] = ']' then
      Break;
    Inc(LBracketEnd);
  end;
  if LBracketEnd > AText.Length then
  begin
    APos := LSavePos;
    Exit;
  end;

  LParenStart := LBracketEnd + 1;
  if (LParenStart > AText.Length) or (AText[LParenStart] <> '(') then
  begin
    APos := LSavePos;
    Exit;
  end;

  LParenEnd := LParenStart + 1;
  while LParenEnd <= AText.Length do
  begin
    if AText[LParenEnd] = ')' then
      Break;
    Inc(LParenEnd);
  end;
  if LParenEnd > AText.Length then
  begin
    APos := LSavePos;
    Exit;
  end;

  LAlt := AText.Substring(APos, LBracketEnd - APos - 1);

  DoFlushWordBuffer();
  DoEmitRaw(STYLE_DIM + '[IMG: ' + LAlt + ']' + COLOR_RESET);
  FColumn := FColumn + LAlt.Length + 7;

  APos := LParenEnd + 1;
  Result := True;
end;

// --- Inline HTML / LaTeX ---

procedure TConsoleAdapter.DoEmitHtmlTag(const ATag: string);
var
  LName: string;
  LRest: string;
  LClosing: Boolean;
  LIdx: Integer;
begin
  LName := ATag.Trim();
  LClosing := LName.StartsWith('/');
  if LClosing then
    LName := LName.Substring(1).Trim();

  // Split into tag name (up to first space or '/') and remainder
  LIdx := 1;
  while (LIdx <= LName.Length) and
        not CharInSet(LName[LIdx], [' ', '/']) do
    Inc(LIdx);
  LRest := LName.Substring(LIdx - 1).Trim();
  LName := LName.Substring(0, LIdx - 1).ToLower();

  // Validation (anti-text-loss): only a known tag name with an empty,
  // self-closing, or attribute remainder counts as a tag. Anything else
  // is prose -- re-emit raw, never strip.
  if not (LRest.IsEmpty() or (LRest = '/') or LRest.Contains('=')) then
  begin
    DoEmit('<' + ATag + '>');
    Exit;
  end;

  if (LName = 'b') or (LName = 'strong') then
    DoToggleStyle(isBold)
  else if (LName = 'i') or (LName = 'em') then
    DoToggleStyle(isItalic)
  else if LName = 'code' then
    DoToggleStyle(isCode)
  else if (LName = 's') or (LName = 'del') or (LName = 'strike') then
    DoToggleStyle(isStrikethrough)
  else if LName = 'br' then
  begin
    DoFlushWordBuffer();
    DoNewLine();
  end
  else if (LName = 'a') or (LName = 'span') or (LName = 'u') or
          (LName = 'small') or (LName = 'sub') or (LName = 'sup') or
          (LName = 'p') then
  begin
    // Presentation tags with no ANSI mapping -- consume silently,
    // the content itself still streams
  end
  else
    DoEmit('<' + ATag + '>');
end;

procedure TConsoleAdapter.DoEmitMath(const ARaw: string);
begin
  DoEmit(DoApplyLatexSubs(ARaw));
end;

function TConsoleAdapter.DoParseHtmlTag(const AText: string;
  var APos: Integer): Boolean;
var
  LIdx: Integer;
  LClose: Integer;
  LInner: string;
begin
  Result := False;
  // APos is at '<' -- find the closing '>' within the tag length cap
  LClose := 0;
  LIdx := APos + 1;
  while (LIdx <= AText.Length) and (LIdx - APos <= 65) do
  begin
    if AText[LIdx] = '>' then
    begin
      LClose := LIdx;
      Break;
    end;
    Inc(LIdx);
  end;
  if LClose = 0 then
    Exit;

  LInner := AText.Substring(APos, LClose - APos - 1);
  if LInner.IsEmpty() or
     not CharInSet(LInner[1], ['a'..'z', 'A'..'Z', '/']) then
    Exit;

  APos := LClose + 1;
  DoEmitHtmlTag(LInner);
  Result := True;
end;

function TConsoleAdapter.DoParseMath(const AText: string;
  var APos: Integer): Boolean;
var
  LDisplay: Boolean;
  LStart: Integer;
  LIdx: Integer;
  LEnd: Integer;
  LCap: Integer;
  LInner: string;
begin
  Result := False;
  // APos is at '$' -- a second '$' means display math
  LDisplay := (APos < AText.Length) and (AText[APos + 1] = '$');
  if LDisplay then
  begin
    LStart := APos + 2;
    LCap := 512;
  end
  else
  begin
    LStart := APos + 1;
    LCap := 256;
  end;

  // Currency/false-positive guard: '$' then space or digit is literal
  if not LDisplay then
  begin
    if (LStart > AText.Length) or
       CharInSet(AText[LStart], [' ', #9, '0'..'9']) then
      Exit;
  end;

  // Scan for the matching closing delimiter within the cap
  LEnd := 0;
  LIdx := LStart;
  while (LIdx <= AText.Length) and (LIdx - LStart < LCap) do
  begin
    if AText[LIdx] = '$' then
    begin
      if not LDisplay then
      begin
        LEnd := LIdx;
        Break;
      end;
      if (LIdx < AText.Length) and (AText[LIdx + 1] = '$') then
      begin
        LEnd := LIdx;
        Break;
      end;
    end;
    Inc(LIdx);
  end;
  if LEnd = 0 then
    Exit;

  LInner := AText.Substring(LStart - 1, LEnd - LStart);
  DoEmit(DoApplyLatexSubs(LInner));
  if LDisplay then
    APos := LEnd + 2
  else
    APos := LEnd + 1;
  Result := True;
end;

function TConsoleAdapter.DoApplyLatexSubs(const AText: string): string;
var
  LPos: Integer;
begin
  LPos := 1;
  Result := DoLatexParse(AText, LPos, #0);
end;

function TConsoleAdapter.DoRewriteInlineMath(const AText: string): string;
var
  LOut: TStringBuilder;
  LPos: Integer;
  LStart: Integer;
  LEnd: Integer;
  LIdx: Integer;
  LCap: Integer;
  LDisplay: Boolean;
begin
  // Fast path -- nothing to do without a delimiter
  if not AText.Contains('$') then
    Exit(AText);

  LOut := TStringBuilder.Create();
  try
    LPos := 1;
    while LPos <= AText.Length do
    begin
      if AText[LPos] = '$' then
      begin
        // Mirror DoParseMath: '$$' opens display math with a larger cap
        LDisplay := (LPos < AText.Length) and (AText[LPos + 1] = '$');
        if LDisplay then
        begin
          LStart := LPos + 2;
          LCap := 512;
        end
        else
        begin
          LStart := LPos + 1;
          LCap := 256;
        end;

        // Currency/false-positive guard: '$' then space or digit is
        // literal text, not math
        if (not LDisplay) and
           ((LStart > AText.Length) or
            CharInSet(AText[LStart], [' ', #9, '0'..'9'])) then
        begin
          LOut.Append(AText[LPos]);
          Inc(LPos);
          Continue;
        end;

        // Bounded scan for the matching closing delimiter
        LEnd := 0;
        LIdx := LStart;
        while (LIdx <= AText.Length) and (LIdx - LStart < LCap) do
        begin
          if AText[LIdx] = '$' then
          begin
            if not LDisplay then
            begin
              LEnd := LIdx;
              Break;
            end;
            if (LIdx < AText.Length) and (AText[LIdx + 1] = '$') then
            begin
              LEnd := LIdx;
              Break;
            end;
          end;
          Inc(LIdx);
        end;

        // Unclosed span -- the '$' is literal
        if LEnd = 0 then
        begin
          LOut.Append(AText[LPos]);
          Inc(LPos);
          Continue;
        end;

        LOut.Append(DoApplyLatexSubs(
          AText.Substring(LStart - 1, LEnd - LStart)));
        if LDisplay then
          LPos := LEnd + 2
        else
          LPos := LEnd + 1;
      end
      else
      begin
        LOut.Append(AText[LPos]);
        Inc(LPos);
      end;
    end;

    Result := LOut.ToString();
  finally
    LOut.Free();
  end;
end;

function TConsoleAdapter.DoLatexParse(const AText: string; var APos: Integer;
  const AStopChar: Char): string;
var
  LOut: TStringBuilder;
  LCh: Char;
  LBoundCh: Char;
  LCmd: string;
  LOperand: string;
  LNum: string;
  LDen: string;
  LArg: string;
  LLo: string;
  LHi: string;
  LEnv: string;
  LEndMark: string;
  LContent: string;
  LIdx: Integer;
  LBounds: Integer;
  LFound: Boolean;

  // Skip spaces between a command and its argument
  procedure SkipSpaces();
  begin
    while (APos <= Length(AText)) and (AText[APos] = ' ') do
      Inc(APos);
  end;

  // Parse one argument: a {..} group (recursive) or a single character
  function ParseGroup(): string;
  begin
    Result := '';
    SkipSpaces();
    if APos > Length(AText) then
      Exit;
    if AText[APos] = '{' then
    begin
      Inc(APos);
      Result := DoLatexParse(AText, APos, '}');
    end
    else
    begin
      Result := AText[APos];
      Inc(APos);
    end;
  end;

  // Wrap multi-character groups in parentheses for readability
  function WrapGroup(const AStr: string): string;
  begin
    if AStr.Length > 1 then
      Result := '(' + AStr + ')'
    else
      Result := AStr;
  end;

  function IsAllDigits(const AStr: string): Boolean;
  var
    LDigitIdx: Integer;
  begin
    Result := AStr.Length > 0;
    for LDigitIdx := 1 to AStr.Length do
    begin
      if not CharInSet(AStr[LDigitIdx], ['0'..'9']) then
      begin
        Result := False;
        Exit;
      end;
    end;
  end;

  function MapDigits(const AStr: string; const ASuper: Boolean): string;
  var
    LDigitIdx: Integer;
    LDigit: Integer;
  begin
    Result := '';
    for LDigitIdx := 1 to AStr.Length do
    begin
      LDigit := Ord(AStr[LDigitIdx]) - Ord('0');
      if ASuper then
        Result := Result + SUPERSCRIPT_DIGITS[LDigit]
      else
        Result := Result + SUBSCRIPT_DIGITS[LDigit];
    end;
  end;

begin
  LOut := TStringBuilder.Create();
  try
    while APos <= Length(AText) do
    begin
      LCh := AText[APos];

      // Stop character of the enclosing group: consume and return
      if (AStopChar <> #0) and (LCh = AStopChar) then
      begin
        Inc(APos);
        Break;
      end;

      // Brace group: recurse
      if LCh = '{' then
      begin
        Inc(APos);
        LOut.Append(DoLatexParse(AText, APos, '}'));
        Continue;
      end;

      // Unmatched closing brace: drop
      if LCh = '}' then
      begin
        Inc(APos);
        Continue;
      end;

      // Subscript / superscript
      if (LCh = '_') or (LCh = '^') then
      begin
        Inc(APos);
        LOperand := ParseGroup();
        if IsAllDigits(LOperand) then
          LOut.Append(MapDigits(LOperand, LCh = '^'))
        else
        begin
          // Non-numeric operand stays readable: x_max remains "x_max"
          LOut.Append(LCh);
          LOut.Append(LOperand);
        end;
        Continue;
      end;

      // Command
      if LCh = '\' then
      begin
        Inc(APos);
        if APos > Length(AText) then
        begin
          LOut.Append('\');
          Break;
        end;
        // Control symbol (non-letter): \\ \, \; map to space
        if not CharInSet(AText[APos], ['a'..'z', 'A'..'Z']) then
        begin
          if CharInSet(AText[APos], ['\', ',', ';']) then
            LOut.Append(' ')
          else
            LOut.Append(AText[APos]);
          Inc(APos);
          Continue;
        end;
        // Letter command: maximal run of letters
        LCmd := '';
        while (APos <= Length(AText)) and
              CharInSet(AText[APos], ['a'..'z', 'A'..'Z']) do
        begin
          LCmd := LCmd + AText[APos];
          Inc(APos);
        end;

        if LCmd = 'frac' then
        begin
          LNum := ParseGroup();
          LDen := ParseGroup();
          LOut.Append(WrapGroup(LNum) + '/' + WrapGroup(LDen));
        end
        else if LCmd = 'sqrt' then
        begin
          // Skip an optional [..] root index
          SkipSpaces();
          if (APos <= Length(AText)) and (AText[APos] = '[') then
          begin
            while (APos <= Length(AText)) and (AText[APos] <> ']') do
              Inc(APos);
            if APos <= Length(AText) then
              Inc(APos);
          end;
          LArg := ParseGroup();
          LOut.Append(#$221A + WrapGroup(LArg));
        end
        else if (LCmd = 'sum') or (LCmd = 'prod') or (LCmd = 'int') then
        begin
          if LCmd = 'sum' then
            LOut.Append(#$2211)
          else if LCmd = 'prod' then
            LOut.Append(#$220F)
          else
            LOut.Append(#$222B);
          // Optional _{lo} and ^{hi} bounds, in either order
          LLo := '';
          LHi := '';
          LBounds := 0;
          while (LBounds < 2) and (APos <= Length(AText)) and
                CharInSet(AText[APos], ['_', '^']) do
          begin
            LBoundCh := AText[APos];
            Inc(APos);
            if LBoundCh = '_' then
              LLo := ParseGroup()
            else
              LHi := ParseGroup();
            Inc(LBounds);
          end;
          if (LLo <> '') and (LHi <> '') then
            LOut.Append('(' + LLo + '..' + LHi + ')')
          else if LLo <> '' then
            LOut.Append('(' + LLo + ')')
          else if LHi <> '' then
            LOut.Append('(' + LHi + ')');
        end
        else if (LCmd = 'text') or (LCmd = 'mathrm') or (LCmd = 'mathbf') or
                (LCmd = 'mathit') or (LCmd = 'mathsf') or
                (LCmd = 'operatorname') then
          LOut.Append(ParseGroup())
        else if (LCmd = 'left') or (LCmd = 'right') then
        begin
          // The following delimiter char passes through on the next
          // iteration; the '.' invisible delimiter is dropped
          if (APos <= Length(AText)) and (AText[APos] = '.') then
            Inc(APos);
        end
        else if LCmd = 'begin' then
        begin
          LEnv := ParseGroup();
          // Collect raw content up to the matching \end{env}
          LEndMark := '\end{' + LEnv + '}';
          LIdx := AText.IndexOf(LEndMark, APos - 1);
          if LIdx >= 0 then
          begin
            LContent := AText.Substring(APos - 1, LIdx - (APos - 1));
            APos := LIdx + LEndMark.Length + 1;
          end
          else
          begin
            LContent := AText.Substring(APos - 1);
            APos := Length(AText) + 1;
          end;
          // Linearize rows and columns, then recurse on the content
          LContent := LContent.Replace('\\', '; ').Replace('&', ' ');
          LContent := DoApplyLatexSubs(LContent.Trim());
          if (LEnv = 'pmatrix') or (LEnv = 'bmatrix') or
             (LEnv = 'vmatrix') or (LEnv = 'matrix') then
            LOut.Append('[' + LContent + ']')
          else if LEnv = 'cases' then
            LOut.Append('{' + LContent)
          else
            LOut.Append(LContent);
        end
        else
        begin
          // Glyph table lookup; unknown commands degrade readably
          // (\foobar becomes "foobar")
          LFound := False;
          for LIdx := 0 to LATEX_SUB_COUNT - 1 do
          begin
            if LATEX_SUBS[LIdx].Tex = '\' + LCmd then
            begin
              LOut.Append(LATEX_SUBS[LIdx].Sub);
              LFound := True;
              Break;
            end;
          end;
          if not LFound then
            LOut.Append(LCmd);
        end;
        Continue;
      end;

      // Regular character
      LOut.Append(LCh);
      Inc(APos);
    end;
    Result := LOut.ToString();
  finally
    LOut.Free();
  end;
end;

function TConsoleAdapter.DoClassifyHtmlBlock(const ALine: string;
  out AContent: string; out ALevel: Integer): TLineKind;
var
  LName: string;
  LIdx: Integer;
  LInner: string;
  LCloseTag: string;
begin
  AContent := '';
  ALevel := 0;
  Result := lkParagraph;

  // Tag name: between '<' and the first '>', space, or '/'
  LName := '';
  LIdx := 2;
  while (LIdx <= ALine.Length) and
        not CharInSet(ALine[LIdx], ['>', ' ', '/']) do
  begin
    LName := LName + ALine[LIdx];
    Inc(LIdx);
  end;
  LName := LName.ToLower();

  // Inner text: everything after the opening tag's '>', with a matching
  // trailing close tag stripped when present
  LInner := '';
  while (LIdx <= ALine.Length) and (ALine[LIdx] <> '>') do
    Inc(LIdx);
  if LIdx <= ALine.Length then
    LInner := ALine.Substring(LIdx);
  LCloseTag := '</' + LName + '>';
  if LInner.EndsWith(LCloseTag, True) then
    LInner := LInner.Substring(0, LInner.Length - LCloseTag.Length);
  LInner := LInner.Trim();

  if (LName.Length = 2) and (LName[1] = 'h') and
     CharInSet(LName[2], ['1'..'6']) then
  begin
    ALevel := Ord(LName[2]) - Ord('0');
    AContent := LInner;
    Result := lkHeading;
  end
  else if LName = 'hr' then
    Result := lkHRule
  else if LName = 'pre' then
  begin
    AContent := '';
    Result := lkCodeFenceOpen;
  end
  else if LName = 'li' then
  begin
    AContent := LInner;
    ALevel := 0;
    Result := lkUnorderedList;
  end
  else if LName = 'blockquote' then
  begin
    AContent := LInner;
    ALevel := 1;
    Result := lkBlockquote;
  end
  else if LName = 'p' then
  begin
    AContent := LInner;
    Result := lkParagraph;
  end
  else if LName = 'br' then
    Result := lkBlank;
end;

procedure TConsoleAdapter.DoParseAsterisks(const AText: string;
  var APos: Integer);
var
  LCount: Integer;
begin
  LCount := 0;
  while (APos + LCount <= AText.Length) and
        (AText[APos + LCount] = '*') do
    Inc(LCount);

  if LCount >= 3 then
  begin
    // Bold + italic
    DoToggleStyle(isBold);
    DoToggleStyle(isItalic);
    Inc(APos, 3);
  end
  else if LCount = 2 then
  begin
    DoToggleStyle(isBold);
    Inc(APos, 2);
  end
  else
  begin
    DoToggleStyle(isItalic);
    Inc(APos, 1);
  end;
end;

procedure TConsoleAdapter.DoParseInline(const AText: string);
var
  LPos: Integer;
  LCh: Char;
begin
  LPos := 1;
  while LPos <= AText.Length do
  begin
    LCh := AText[LPos];

    // Backslash escape
    if (LCh = '\') and (LPos < AText.Length) then
    begin
      Inc(LPos);
      DoEmit(AText[LPos]);
      Inc(LPos);
      Continue;
    end;

    // Code span
    if LCh = '`' then
    begin
      if DoParseCodeSpan(AText, LPos) then
        Continue;
      DoEmit('`');
      Inc(LPos);
      Continue;
    end;

    // Image: ![alt](url)
    if (LCh = '!') and (LPos < AText.Length) and (AText[LPos + 1] = '[') then
    begin
      if DoParseImage(AText, LPos) then
        Continue;
    end;

    // Link: [text](url)
    if LCh = '[' then
    begin
      if DoParseLink(AText, LPos) then
        Continue;
    end;

    // Strikethrough: ~~
    if (LCh = '~') and (LPos < AText.Length) and (AText[LPos + 1] = '~') then
    begin
      DoToggleStyle(isStrikethrough);
      Inc(LPos, 2);
      Continue;
    end;

    // Asterisks: * ** ***
    if LCh = '*' then
    begin
      DoParseAsterisks(AText, LPos);
      Continue;
    end;

    // Inline HTML tag
    if LCh = '<' then
    begin
      if DoParseHtmlTag(AText, LPos) then
        Continue;
    end;

    // Inline math
    if LCh = '$' then
    begin
      if DoParseMath(AText, LPos) then
        Continue;
    end;

    // Regular character
    DoEmit(AText[LPos]);
    Inc(LPos);
  end;
end;

// --- Flush ---

procedure TConsoleAdapter.Flush();
var
  LIdx: Integer;
  LJoined: string;
  LContent: string;
begin
  // Finalize any in-progress line
  case FLineMode of
    LINE_MODE_DETECT:
    begin
      if not FLinePrefix.IsEmpty() then
        DoProcessBufferedLine(FLinePrefix);
    end;
    LINE_MODE_STREAM:
    begin
      // Resolve pending inline state
      if FPendingChar <> #0 then
      begin
        if FPendingChar = '*' then
          DoEmit('*')
        else if FPendingChar = '~' then
          DoEmit('~');
        FPendingChar := #0;
      end;
      if FLinkState > 0 then
      begin
        LContent := '[' + FLinkText;
        if FLinkState >= 2 then
          LContent := LContent + ']';
        if FLinkState >= 3 then
          LContent := LContent + '(' + FLinkUrl;
        DoEmit(LContent);
        FLinkText := '';
        FLinkUrl := '';
        FLinkState := 0;
      end;
      if FHtmlState > 0 then
      begin
        DoEmit('<' + FHtmlBuffer);
        FHtmlBuffer := '';
        FHtmlState := 0;
      end;
      if FMathState > 0 then
      begin
        // Reconstruct exactly what was consumed -- text loss is forbidden
        if FMathState = 1 then
          DoEmit('$' + FMathBuffer)
        else if FMathState = 2 then
          DoEmit('$$' + FMathBuffer)
        else // 3: '$$' + content + one '$' already consumed
          DoEmit('$$' + FMathBuffer + '$');
        FMathBuffer := '';
        FMathState := 0;
      end;
      FInCodeSpan := False;
    end;
    LINE_MODE_BUFFER:
    begin
      if not FLineBuffer.IsEmpty() then
        DoProcessBufferedLine(FLineBuffer);
    end;
  end;
  FLineMode := LINE_MODE_DETECT;
  FLinePrefix := '';
  FLineBuffer := '';
  FCodeLineStarted := False;

  // Flush word buffer
  DoFlushWordBuffer();

  // Close open styles
  if FStyles <> [] then
  begin
    DoEmitRaw(COLOR_RESET);
    FStyles := [];
  end;

  // Close open blocks
  case FBlockState of
    bsCodeBlock:
    begin
      DoEmitCodeBlockEnd();
      FBlockState := bsNone;
    end;
    bsTablePending:
    begin
      if FTableHeader <> nil then
      begin
        LJoined := '';
        for LIdx := 0 to High(FTableHeader) do
        begin
          if LIdx > 0 then
            LJoined := LJoined + ' | ';
          LJoined := LJoined + FTableHeader[LIdx];
        end;
        DoHandleParagraph(LJoined);
      end;
      FBlockState := bsNone;
      FTableHeader := nil;
    end;
    bsTable:
      DoEndTable();
  end;

  if FInList then
    DoEndList();

  FBlockquoteDepth := 0;
  FIndent := 0;

  DoFlushOutput();
end;

end.
