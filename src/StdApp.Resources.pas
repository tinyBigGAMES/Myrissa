{===============================================================================
  StdApp Components™

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  See LICENSE for license information

 -------------------------------------------------------------------------------

  StdApp.Resources - Shared resource strings

  Central repository of all user-facing message strings used across
  StdApp units. All error messages, warning text, and format strings
  are declared as resourcestring constants for localization readiness
  and clean separation from logic.

  Categories: severity names, error formats, fatal/IO messages,
  VFS messages, VirtualMemory messages.

  Dependencies: none
  Notes: Error code constants are defined in the unit of their concern,
    not here. This unit holds only the message text.
===============================================================================}

unit StdApp.Resources;

{$I StdApp.Defines.inc}

interface

resourcestring

  //--------------------------------------------------------------------------
  // Severity Names
  //--------------------------------------------------------------------------
  RSSeverityHint    = 'Hint';
  RSSeverityWarning = 'Warning';
  RSSeverityError   = 'Error';
  RSSeverityFatal   = 'Fatal';
  RSSeverityNote    = 'Note';
  RSSeverityUnknown = 'Unknown';

  //--------------------------------------------------------------------------
  // Error Format Strings
  //--------------------------------------------------------------------------
  RSErrorFormatSimple              = '%s %s: %s';
  RSErrorFormatWithLocation        = '%s: %s %s: %s';
  RSErrorFormatRelatedSimple       = '  %s: %s';
  RSErrorFormatRelatedWithLocation = '  %s: %s: %s';

  //--------------------------------------------------------------------------
  // Fatal / I/O Messages
  //--------------------------------------------------------------------------
  RSFatalFileNotFound  = 'File not found: ''%s''';
  RSFatalFileReadError = 'Cannot read file ''%s'': %s';
  RSFatalInternalError = 'Internal error: %s';

  //--------------------------------------------------------------------------
  // VFS Messages
  //--------------------------------------------------------------------------
  RSVFSOpenFileFailed      = 'Failed to open file: ''%s''';
  RSVFSInvalidMagic        = 'Invalid VFS archive magic signature';
  RSVFSInvalidVersion      = 'Unsupported VFS archive version: %d';
  RSVFSTruncated           = 'VFS archive is truncated or corrupt';
  RSVFSNotOpen             = 'VFS archive is not open';
  RSVFSEntryNotFound       = 'Entry not found in VFS: ''%s''';
  RSVFSScanDirFailed       = 'Failed to scan directory: ''%s''';
  RSVFSEmptyDirectory      = 'Source directory contains no files: ''%s''';
  RSVFSSourceOpenFailed    = 'Failed to open source file for packing: ''%s''';
  RSVFSException           = 'Unexpected exception in VFS: %s';

  //--------------------------------------------------------------------------
  // VirtualMemory Messages
  //--------------------------------------------------------------------------
  RSVMAllocSizeZero          = 'Cannot allocate a zero-size buffer';
  RSVMCreateMappingFailed    = 'CreateFileMapping failed (error %d)';
  RSVMMappingNameExists      = 'Mapping name "%s" already exists';
  RSVMMapViewFailed          = 'MapViewOfFile failed (error %d)';
  RSVMAllocException         = 'Allocate exception: %s';
  RSVMSharedNameEmpty        = 'OpenShared: mapping name must not be empty';
  RSVMOpenMappingFailed      = 'OpenFileMapping failed for "%s" (error %d)';
  RSVMMapViewNamedFailed     = 'MapViewOfFile failed for "%s" (error %d)';
  RSVMSharedException        = 'OpenShared exception for "%s": %s';
  RSVMUseAllocate            = 'Use Allocate() for anonymous buffers, not Open()';
  RSVMOpenFileFailed         = 'Cannot open file "%s" (error %d)';
  RSVMFileEmpty              = 'File "%s" is empty -- cannot memory-map';
  RSVMCreateMappingNamedFailed = 'CreateFileMapping failed for "%s" (error %d)';
  RSVMOpenException          = 'Open exception for "%s": %s';
  RSVMLoadAlignmentFailed    = 'File size (%d) is not aligned to element size (%d)';
  RSVMLoadException          = 'LoadFromFile exception for "%s": %s';
  RSVMFlushFailed            = 'FlushViewOfFile failed (error %d)';
  RSVMGrowNotAnonymous       = 'Grow is only valid for anonymous (vmAllocate) buffers';
  RSVMGrowNotShared          = 'Grow is not valid for shared consumer mappings';
  RSVMGrowMappingFailed      = 'Grow: CreateFileMapping failed (error %d)';
  RSVMGrowMapViewFailed      = 'Grow: MapViewOfFile failed (error %d)';
  RSVMGrowException          = 'Grow exception: %s';

  //--------------------------------------------------------------------------
  // Your Application
  //--------------------------------------------------------------------------
  // Add your application-specific resource strings below this line.
  // This section is reserved for custom messages, labels, and format
  // strings that are unique to your application. StdApp framework
  // resources are defined above and should not be modified.
  //--------------------------------------------------------------------------


  //--------------------------------------------------------------------------
  // CodeGen Messages
  //--------------------------------------------------------------------------
  RSBuilderAlreadyConsumed   = 'Struct builder for ''%s'' already consumed';
  RSStructAlreadyDefined     = 'Struct ''%s'' already defined';
  RSOffsetOfNotAggregate     = 'OffsetOf: type ''%s'' is not a struct or union';

  //--------------------------------------------------------------------------
  // Backend Messages
  //--------------------------------------------------------------------------
  RSBackendOutputPath   = 'Output path not specified';
  RSBackendBuildFailed  = 'Build failed - no output generated';
  RSBackendWriteFailed  = 'Error writing output: %s';
  RSBackendNoActiveFunc = 'No active function';

  //--------------------------------------------------------------------------
  // Codegen Messages
  //--------------------------------------------------------------------------
  RSCodegenNoCode    = 'No code generated';
  RSCodegenRunFailed = 'Run failed: %s';
  RSCodegenCOFFFailed = 'COFF generation failed, cannot create .lib';
  RSCodegenLinuxKind = 'linux64 supports exe, dll, obj, and lib output';

  //--------------------------------------------------------------------------
  // IR Messages
  //--------------------------------------------------------------------------
  RSIRNoActiveFunction      = 'No active function';
  RSIRUnknownType           = 'Unknown type: ''%s''';
  RSIRUnknownBaseType       = 'Unknown base type: ''%s''';
  RSIROverloadCLinkage      = 'Overloaded routine ''%s'' cannot use C linkage';
  RSIRVariadicOverload      = 'Variadic routine ''%s'' cannot be overloaded';
  RSIRSyscallTooManyArgs    = 'Syscall has %d arguments; maximum is %d';
  RSIRBitFieldNoRecord      = 'Bit field declared outside record';
  RSIRBitFieldWidth         = 'Bit field width exceeds type size (%d)';
  RSIRAlreadyBuildingRecord = 'Already building a record type';
  RSIRAlreadyBuildingUnion  = 'Already building a union type';
  RSIRAlreadyBuildingEnum   = 'Already building an enum type';
  RSIRAlreadyAnonRecord     = 'Already building an anonymous record';
  RSIRAlreadyAnonUnion      = 'Already building an anonymous union';
  RSIRNotBuildingRecord     = 'Not building a record type';
  RSIRNotBuildingUnion      = 'Not building a union type';
  RSIRNotBuildingEnum       = 'Not building an enum type';
  RSIRNotBuildingRecordUnion = 'Not building a record or union';
  RSIRNotBuildingRoutine    = 'Not building a routine type';
  RSIRBaseNotRecord         = 'Base type is not a record';
  RSIRBeginRecordNeedsUnion = 'BeginRecord requires active union context';
  RSIRBeginUnionNeedsRecord = 'BeginUnion requires active record context';
  RSIREnumNoValues          = 'Enum type has no values';
  RSIREnumRangeTooLarge     = 'Enum range too large';
  RSIRUnknownEnumType       = 'Unknown enum type: ''%s''';
  RSIRTypeNotEnum           = 'Type is not an enum: ''%s''';
  RSIRTypeNotSet            = 'Type is not a set: ''%s''';
  RSIRUnknownSetType        = 'Unknown set type: ''%s''';
  RSIRInvalidSetRange       = 'Invalid set range';
  RSIRSetRangeTooLarge      = 'Set range too large';
  RSIRSizeOfUnknown         = 'SizeOf: unknown type: ''%s''';
  RSIRAlignOfUnknown        = 'AlignOf: unknown type: ''%s''';
  RSIRLenNotApplicable      = 'Len not applicable to type: ''%s''';
  RSIRLenUnknown            = 'Len: unknown type: ''%s''';
  RSIRLowNotApplicable      = 'Low not applicable to type: ''%s''';
  RSIRLowUnknown            = 'Low: unknown type: ''%s''';
  RSIRHighNotApplicable     = 'High not applicable to type: ''%s''';
  RSIRHighUnknown           = 'High: unknown type: ''%s''';

  //--------------------------------------------------------------------------
  // Linker Messages
  //--------------------------------------------------------------------------
  RSLinkerCOFFTooSmall = 'COFF file too small: ''%s''';
  RSLinkerNotAMD64     = 'Not an AMD64 COFF object: ''%s'' (machine=$%.4x)';
  RSLinkerARTooSmall   = 'AR file too small: ''%s''';
  RSLinkerARBadSig     = 'Invalid AR signature: ''%s''';
  RSLinkerObjNotFound  = 'Object file not found: ''%s''';
  RSLinkerLibNotFound  = 'Library file not found: ''%s''';

  //--------------------------------------------------------------------------
  // SSA Messages
  //--------------------------------------------------------------------------
  RSSSAUnknownFunction = 'Unknown function: ''%s'' (in routine ''%s'')';
  RSASTChildIndexOutOfRange = 'Child index %d out of range (0..%d)';
  RSASTReplaceChildNotFound = 'Child node not found for replacement';
  RSASTNotAChild            = 'Referenced node is not a child of this node';

  //--------------------------------------------------------------------------
  // Lexer Messages
  //--------------------------------------------------------------------------
  RSLexUnexpectedChar      = 'Unexpected character: %s';
  RSLexUnterminatedString  = 'Unterminated string literal';
  RSLexInvalidNumber       = 'Invalid number format';
  RSLexUnterminatedComment = 'Unterminated block comment';
  RSLexInvalidEscape       = 'Invalid escape sequence: \%s';
  RSLexInvalidHexEscape    = 'Invalid hex escape sequence';
  RSLexInvalidHexLiteral   = 'Invalid hexadecimal literal';
  RSLexInvalidCharacter    = 'Invalid character: ''%s''';
  RSLexExpected            = 'Expected %s but found ''%s''';

  //--------------------------------------------------------------------------
  // Parser Messages
  //--------------------------------------------------------------------------
  RSParExpected      = 'Expected %s but found ''%s''';
  RSParUnexpected    = 'Unexpected token: ''%s''';
  RSParExpectedExpr  = 'Expected expression';
  RSParExpectedIdent = 'Expected identifier';
  RSParExpectedType  = 'Expected type expression';

  //--------------------------------------------------------------------------
  // Semantics Messages
  //--------------------------------------------------------------------------
  RSSemStatusStart           = 'Analyzing...';
  RSSemStatusComplete        = 'Analysis complete (%d errors)';
  RSSemInvalidModuleKind     = 'Invalid module kind: expected exe, dll, lib, or unit';
  RSSemExeMissingMain        = 'exe module must have a begin...end entry point';
  RSSemMainBodyForbidden     = '%s module must not have a begin...end block';
  RSSemInvalidTarget         = 'Invalid @target value ''%s''';
  RSSemCannotRunModule       = 'Cannot run a %s module -- only exe modules can be run';
  RSSemCannotRunTarget       = 'Cannot run target ''%s'' -- not a native executable target';
  RSScriptUndeclaredIdent    = 'Undeclared identifier: ''%s''';
  RSScriptDuplicateDecl      = 'Duplicate declaration: ''%s''';
  RSScriptConstAssign        = 'Cannot assign to constant ''%s''';
  RSScriptBreakOutsideLoop   = '''break'' used outside of a loop';
  RSScriptContinueOutsideLoop = '''continue'' used outside of a loop';
  RSScriptMatchLabelNotConst = 'Match label must be a constant integer expression';

  //--------------------------------------------------------------------------
  // Preprocessor Messages
  //--------------------------------------------------------------------------
  RSScriptCondMissingArg   = '@%s requires an identifier argument';
  RSScriptCondUnmatched    = 'Unmatched @%s without matching @ifdef/@ifndef';
  RSScriptCondDuplicate    = 'Duplicate @else in conditional block';
  RSScriptCondUnterminated = 'Unterminated conditional block (missing @endif)';

  //--------------------------------------------------------------------------
  // Native/Build Warning Messages
  //--------------------------------------------------------------------------
  RSWarnIconNotFound      = 'Icon file not found: ''%s''';
  RSWarnIconFailed        = 'Failed to load icon: ''%s''';
  RSWarnManifestFailed    = 'Failed to embed manifest';
  RSWarnVersionInfoFailed = 'Failed to embed version info: ''%s''';

  //--------------------------------------------------------------------------
  // SourceMap / Debug Messages
  //--------------------------------------------------------------------------
  RSSourceMapHeaderShort   = 'Invalid .mdbg file: header too short';
  RSSourceMapBadMagic      = 'Invalid .mdbg file: bad magic';
  RSSourceMapBadVersion    = 'Unsupported .mdbg version: %d';
  RSSourceMapStrTableTrunc = 'Invalid .mdbg file: string table truncated';
  RSSourceMapSrcFileTrunc  = 'Invalid .mdbg file: source file entry %d truncated';
  RSSourceMapFuncCountMiss = 'Invalid .mdbg file: function count missing';
  RSSourceMapFuncTrunc     = 'Invalid .mdbg file: function entry %d truncated';
  RSSourceMapOverlap       = 'Invalid .mdbg file: section overlap';
  RSSourceMapLineTrunc     = 'Invalid .mdbg file: line entry %d truncated';
  RSSourceMapVarTrunc      = 'Invalid .mdbg file: variable entry %d truncated';


implementation

end.
