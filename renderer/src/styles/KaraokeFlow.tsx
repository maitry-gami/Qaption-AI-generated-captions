import React from 'react';
import { useCurrentFrame, useVideoConfig } from 'remotion';
import type { Segment } from '../CaptionEngine';
import { getPreciseRows, getAutoFitScale } from './captionUtils';
import { loadFont } from '@remotion/google-fonts/Roboto';

const { fontFamily } = loadFont('normal', { weights: ['700'] });

interface KaraokeFlowProps {
  segment: Segment | null;
  customStyles?: any;
}

export const KaraokeFlow: React.FC<KaraokeFlowProps> = ({ segment, customStyles }) => {
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
  const baseColor = customStyles?.color ? hexToRgba(customStyles.color, customStyles.opacity ?? 1) : '#aaaaaa';
  const highlightColor = customStyles?.emphasisColor ? hexToRgba(customStyles.emphasisColor, customStyles.opacity ?? 1) : '#3b82f6';

  const selectedFontFamily = customStyles?.fontFamily ? `"${customStyles.fontFamily}", sans-serif` : fontFamily;
  const justifyContentMap: any = { 'left': 'flex-start', 'center': 'center', 'right': 'flex-end', 'random': 'space-around' };
  const justifyContent = customStyles?.textAlign ? justifyContentMap[customStyles.textAlign] : 'center';

  const wordsPerLine: number = customStyles?.wordsPerLine ?? 3;
  const maxLinesPerFrame: number = customStyles?.maxLinesPerFrame ?? 2;

  // Precise: exactly wordsPerLine words per row, exactly maxLinesPerFrame rows visible
  const visibleRows = getPreciseRows(segment, currentTime, wordsPerLine, maxLinesPerFrame);
  const boxWidth = customStyles?.boxWidth ?? 648;
  const autoFitScale = getAutoFitScale(visibleRows, 16 * sf, boxWidth);
  sf *= autoFitScale;
  

  return (
    <div style={{
      position: 'absolute',
      top: 0,
      height: '100%',
      width: '100%',
      display: 'flex',
      flexDirection: 'column',
      justifyContent,
      alignItems: 'center',
      gap: `${12 * sf}px`,
      fontFamily: selectedFontFamily,
      fontSize: `${Math.round(16 * sf)}px`,
      fontWeight: 'bold',
      textAlign: customStyles?.textAlign === 'random' ? 'center' : (customStyles?.textAlign || 'center'),
      padding: `0 ${Math.round(24 * sf)}px`,
      boxSizing: 'border-box',
      textShadow: `${3 * sf}px ${3 * sf}px 0 #000, -${1 * sf}px -${1 * sf}px 0 #000, ${1 * sf}px -${1 * sf}px 0 #000, -${1 * sf}px ${1 * sf}px 0 #000, ${1 * sf}px ${1 * sf}px 0 #000`,
    }}>
      {visibleRows.map((rowWords, rowIdx) => (
        <div key={rowIdx} style={{
          display: 'flex',
          justifyContent,
          flexWrap: 'nowrap',
          gap: `${12 * sf}px`,
        }}>
          {rowWords.map((wordObj, index) => {
            // Karaoke: highlight words that have already started (been spoken)
            const isHighlighted = currentTime >= wordObj.start;
            return (
              <span
                key={index}
                style={{
                  color: isHighlighted ? highlightColor : baseColor,
                  transition: 'color 0.1s ease-in-out',
                  whiteSpace: 'nowrap',
                }}
              >
                {wordObj.word}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};
