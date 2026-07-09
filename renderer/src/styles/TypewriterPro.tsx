import React from 'react';
import { useCurrentFrame, useVideoConfig } from 'remotion';
import type { Segment } from '../CaptionEngine';
import { getPreciseRows, getAutoFitScale } from './captionUtils';
import { loadFont } from '@remotion/google-fonts/Inter';

const { fontFamily: defaultFontFamily } = loadFont('normal', { weights: ['700'] });

interface TypewriterProProps {
  segment: Segment | null;
  customStyles?: any;
}

export const TypewriterPro: React.FC<TypewriterProProps> = ({ segment, customStyles }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  if (!segment) return null;

  const hexToRgba = (hex: string, opacity: number) => {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    if (!result) return `rgba(255, 255, 255, ${opacity})`;
    return `rgba(${parseInt(result[1], 16)}, ${parseInt(result[2], 16)}, ${parseInt(result[3], 16)}, ${opacity})`;
  };

  const currentTime = frame / fps;
  let sf = customStyles?.scaleFactor ?? 1;

  // Break tab settings
  const wordsPerLine: number = customStyles?.wordsPerLine ?? 3;
  const maxLinesPerFrame: number = customStyles?.maxLinesPerFrame ?? 2;

  // Style tab settings
  const baseColor = customStyles?.color ? hexToRgba(customStyles.color, customStyles.opacity ?? 1) : '#FFFFFF';
  const cursorColor = customStyles?.emphasisColor ? hexToRgba(customStyles.emphasisColor, customStyles.opacity ?? 1) : '#FFFFFF';
  const selectedFontFamily = customStyles?.fontFamily ? `"${customStyles.fontFamily}", sans-serif` : defaultFontFamily;
  const isDisplayFont = customStyles?.fontFamily === 'Bangers' || customStyles?.fontFamily === 'Bebas Neue';
  const resolvedFontWeight = isDisplayFont ? 400 : 700;
  const justifyContentMap: any = { 'left': 'flex-start', 'center': 'center', 'right': 'flex-end', 'random': 'space-around' };
  const justifyContent = customStyles?.textAlign ? justifyContentMap[customStyles.textAlign] : 'center';
  const textAlign: any = customStyles?.textAlign === 'random' ? 'center' : (customStyles?.textAlign || 'center');

  // Precise rows from the full segment — getPreciseRows pages based on the active word
  const visibleRows = getPreciseRows(segment, currentTime, wordsPerLine, maxLinesPerFrame);
  const boxWidth = customStyles?.boxWidth ?? 648;
  const autoFitScale = getAutoFitScale(visibleRows, 16 * sf, boxWidth);
  sf *= autoFitScale;
  

  // Find the active word to determine where the "type cursor" is
  const activeWordIdx = segment.words.findIndex(
    w => currentTime >= w.start && currentTime <= w.end
  );

  // For the typewriter effect: within the active word, calculate character progress
  const activeWord = activeWordIdx !== -1 ? segment.words[activeWordIdx] : null;
  let charProgress = 1; // 0..1 within the active word
  if (activeWord) {
    const wordDuration = activeWord.end - activeWord.start;
    charProgress = wordDuration > 0
      ? Math.min(1, (currentTime - activeWord.start) / wordDuration)
      : 1;
  }

  if (visibleRows.length === 0) return null;

  return (
    <div style={{
      position: 'absolute',
      bottom: '10%',
      width: '100%',
      display: 'flex',
      flexDirection: 'column',
      justifyContent,
      alignItems: justifyContent === 'flex-start' ? 'flex-start' : justifyContent === 'flex-end' ? 'flex-end' : 'center',
      fontFamily: selectedFontFamily,
      fontSize: `${Math.round(16 * sf)}px`,
      fontWeight: resolvedFontWeight,
      color: baseColor,
      textShadow: '2px 2px 4px rgba(0,0,0,0.4)',
      textAlign,
      padding: `0 ${Math.round(40 * sf)}px`,
      boxSizing: 'border-box',
      gap: `${4 * sf}px`,
    }}>
      {visibleRows.map((rowWords, rowIdx) => {
        const isLastRow = rowIdx === visibleRows.length - 1;
        return (
          <div key={rowIdx} style={{ display: 'flex', alignItems: 'center', justifyContent, flexWrap: 'nowrap', gap: `${8 * sf}px` }}>
            {rowWords.map((wordObj, wIdx) => {
              const isActiveWord = activeWord === wordObj;
              const isSpoken = currentTime >= wordObj.start;
              const isLastWordInRow = wIdx === rowWords.length - 1;

              // Typewriter: partially reveal active word
              let displayWord = wordObj.word;
              if (isActiveWord) {
                const charsToShow = Math.max(1, Math.ceil(charProgress * wordObj.word.length));
                displayWord = wordObj.word.substring(0, charsToShow);
              } else if (!isSpoken) {
                // Future word — show faded
                displayWord = wordObj.word;
              }

              return (
                <span key={wIdx} style={{ position: 'relative', display: 'inline-flex', alignItems: 'center', whiteSpace: 'nowrap' }}>
                  <span style={{
                    color: isSpoken ? baseColor : `${baseColor.replace(/[\d.]+\)$/, '0.3)')}`,
                    transition: 'color 0.1s ease',
                  }}>
                    {displayWord}
                    {/* Partial char ghost for active word */}
                    {isActiveWord && displayWord.length < wordObj.word.length && (
                      <span style={{ opacity: 0.2 }}>
                        {wordObj.word.substring(displayWord.length)}
                      </span>
                    )}
                  </span>
                  {/* Blinking cursor after the last word of the last row */}
                  {isLastRow && isLastWordInRow && (
                    <span style={{
                      animation: 'tw-blink 1s step-end infinite',
                      borderRight: `3px solid ${cursorColor}`,
                      marginLeft: '2px',
                      height: `${Math.round(22 * sf)}px`,
                      display: 'inline-block',
                    }} />
                  )}
                </span>
              );
            })}
          </div>
        );
      })}
      <style>{`
        @keyframes tw-blink {
          0%, 100% { opacity: 1; }
          50% { opacity: 0; }
        }
      `}</style>
    </div>
  );
};
