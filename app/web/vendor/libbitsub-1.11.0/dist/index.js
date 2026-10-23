/**
 * libbitsub - High-performance WASM renderer for graphical subtitles
 *
 * @packageDocumentation
 */
// High-level video-integrated renderers (compatible with old libpgs-js API)
export { PgsRenderer, VobSubRenderer, createAutoSubtitleRenderer } from './wrapper';
// Low-level parsers for programmatic use
export { PgsParser, VobSubParserLowLevel, UnifiedSubtitleParser, openSubtitles } from './wrapper';
// Utility exports
export { initWasm, isWasmInitialized, isWebGPUSupported, isWorkerAvailable, isWorkerReady, warmup, ready, detectSubtitleFormat, fetchSubtitleAsset, fetchSubtitleText, probeRangeSupport, renderFrameData, toBlob, toCanvas, toImageBitmap, createSubtitleDiagnosticError, normalizeSubtitleError, SubtitleDiagnosticError } from './wrapper';
// Legacy aliases
export { PGSRenderer, VobsubRenderer, UnifiedSubtitleRenderer } from './wrapper';
//# sourceMappingURL=index.js.map