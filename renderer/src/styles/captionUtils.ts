import type { Segment, Word } from '../CaptionEngine';

/**
 * PRECISE row calculator — the canonical function for all templates.
 *
 * Algorithm:
 *   1. Split ALL segment words into fixed rows of exactly `wordsPerLine`.
 *   2. Find which row the currently active (or last-spoken) word lives in.
 *   3. Return exactly `maxLinesPerFrame` rows ending at that row.
 *
 * This gives pixel-perfect behaviour:
 *   - Every line always has exactly `wordsPerLine` words (last line may be shorter).
 *   - Exactly `maxLinesPerFrame` lines are on screen at once.
 *   - The display pages forward as speech crosses a row boundary.
 *   - Future (unspoken) words in the current page ARE shown so the viewer
 *     can read ahead — active word is highlighted by the calling component.
 */
export function getPreciseRows(
  segment: Segment,
  currentTime: number,
  wordsPerLine: number = 3,
  maxLinesPerFrame: number = 2
): Word[][] {
  if (!segment.words.length) return [];

  const wpl = Math.max(1, Math.round(wordsPerLine));
  const mlf = Math.max(1, Math.round(maxLinesPerFrame));

  // 1. Build all fixed-size rows from the entire segment
  const allRows: Word[][] = [];
  for (let i = 0; i < segment.words.length; i += wpl) {
    allRows.push(segment.words.slice(i, i + wpl));
  }

  // 2. Find the index of the active word (word being spoken right now)
  let activeWordIdx = segment.words.findIndex(
    (w) => currentTime >= w.start && currentTime <= w.end
  );

  // Between words or after the last word — find the last word that has started
  if (activeWordIdx === -1) {
    for (let i = segment.words.length - 1; i >= 0; i--) {
      if (currentTime >= segment.words[i].start) {
        activeWordIdx = i;
        break;
      }
    }
  }

  // Before the first word has been spoken — show nothing
  if (activeWordIdx === -1) return [];

  // 3. Which row contains the active word?
  const activeRowIdx = Math.floor(activeWordIdx / wpl);

  // 4. Return exactly mlf rows ending at (and including) activeRowIdx
  const endIdx = activeRowIdx + 1;           // exclusive slice end
  const startIdx = Math.max(0, endIdx - mlf);
  return allRows.slice(startIdx, endIdx);
}

// ─── Legacy helpers (kept for reference; prefer getPreciseRows) ────────────

/**
 * @deprecated Use getPreciseRows instead.
 * Filters to spoken words only, then groups into rows.
 * Imprecise: row count varies with time, not with wordsPerLine alone.
 */
export function getVisibleRows(
  segment: Segment,
  currentTime: number,
  wordsPerLine: number = 3,
  maxLinesPerFrame: number = 10,
  historySeconds?: number
): Word[][] {
  const visibleWords = segment.words.filter((w) => {
    if (currentTime < w.start) return false;
    if (historySeconds !== undefined && (currentTime - w.start) > historySeconds) return false;
    return true;
  });

  const rows: Word[][] = [];
  for (let i = 0; i < visibleWords.length; i += wordsPerLine) {
    rows.push(visibleWords.slice(i, i + wordsPerLine));
  }
  return rows.length > maxLinesPerFrame ? rows.slice(-maxLinesPerFrame) : rows;
}

/**
 * @deprecated Use getPreciseRows instead.
 * Returns the entire segment broken into rows.
 * Imprecise: always shows the LAST maxLinesPerFrame rows regardless of position.
 */
export function getSegmentRows(
  segment: Segment,
  wordsPerLine: number = 3,
  maxLinesPerFrame: number = 10
): Word[][] {
  const rows: Word[][] = [];
  for (let i = 0; i < segment.words.length; i += wordsPerLine) {
    rows.push(segment.words.slice(i, i + wordsPerLine));
  }
  return rows.length > maxLinesPerFrame ? rows.slice(-maxLinesPerFrame) : rows;
}

/**
 * Calculates a scale factor to prevent a set of rows from horizontally overflowing their container.
 * Assumes uppercase text with display weights.
 */
export function getAutoFitScale(
  visibleRows: Word[][],
  baseFontSizePx: number,
  containerWidthPx: number,
  paddingPx: number = 48
): number {
  if (visibleRows.length === 0 || !containerWidthPx) return 1;

  const safeWidth = containerWidthPx - paddingPx;
  let maxEstimatedWidth = 0;

  for (const row of visibleRows) {
    if (row.length === 0) continue;
    
    // Sum of all characters in the row
    const charCount = row.reduce((sum, w) => sum + w.word.length, 0);
    // Number of spaces/gaps
    const gapCount = row.length - 1;
    
    // Estimate: Display/Bold fonts are typically very wide. 
    // Plus text strokes/shadows. Let's use 1.2em to be extremely safe against overflow.
    const estimatedWidth = (charCount * baseFontSizePx * 1.2) + (gapCount * baseFontSizePx * 1.0);
    
    if (estimatedWidth > maxEstimatedWidth) {
      maxEstimatedWidth = estimatedWidth;
    }
  }

  if (maxEstimatedWidth > safeWidth && maxEstimatedWidth > 0) {
    return safeWidth / maxEstimatedWidth;
  }

  return 1;
}

export function getAutoFitScaleForTokens(
  chunks: any[][],
  baseFontSizePx: number,
  containerWidthPx: number,
  paddingPx: number = 48
): number {
  if (chunks.length === 0 || !containerWidthPx) return 1;
  const safeWidth = containerWidthPx - paddingPx;
  let maxEstimatedWidth = 0;
  for (const chunk of chunks) {
    if (chunk.length === 0) continue;
    const charCount = chunk.reduce((sum, token) => sum + (token.text || '').trim().length, 0);
    const gapCount = chunk.length - 1;
    // Base font size is large in Buzz/Medusa, use 1.2em per char to be ultra safe
    const estimatedWidth = (charCount * baseFontSizePx * 1.2) + (gapCount * baseFontSizePx * 0.8);
    if (estimatedWidth > maxEstimatedWidth) maxEstimatedWidth = estimatedWidth;
  }
  if (maxEstimatedWidth > safeWidth && maxEstimatedWidth > 0) {
    return safeWidth / maxEstimatedWidth;
  }
  return 1;
}
