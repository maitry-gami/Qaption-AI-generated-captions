import React from 'react';
import { useCurrentFrame, useVideoConfig } from 'remotion';
import type { Segment } from '../CaptionEngine';
import { getPreciseRows, getAutoFitScale } from './captionUtils';
import { loadFont } from '@remotion/google-fonts/Inter';

const { fontFamily } = loadFont('normal', { weights: ['500'] });

interface MinimalistBgStyleProps {
  segment: Segment | null;
  customStyles?: any;
}

export const MinimalistBgStyle: React.FC<MinimalistBgStyleProps> = ({ segment, customStyles }) => {
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
  const baseColor = customStyles?.color ? hexToRgba(customStyles.color, customStyles.opacity ?? 1) : '#ffffff';
  const highlightColor = customStyles?.emphasisColor ? hexToRgba(customStyles.emphasisColor, customStyles.opacity ?? 1) : '#a78bfa';
  const bgColor = customStyles?.activeWordColor ? hexToRgba(customStyles.activeWordColor, 0.75) : 'rgba(0, 0, 0, 0.75)';

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
      gap: `${8 * sf}px`,
      padding: `0 ${Math.round(24 * sf)}px`,
      boxSizing: 'border-box',
    }}>
      {visibleRows.map((rowWords, rowIdx) => (
        <div key={rowIdx} style={{
          fontFamily: selectedFontFamily,
          fontSize: `${Math.round(16 * sf)}px`,
          fontWeight: '500',
          color: baseColor,
          backgroundColor: bgColor,
          padding: `${12 * sf}px ${24 * sf}px`,
          borderRadius: `${8 * sf}px`,
          textAlign: customStyles?.textAlign === 'random' ? 'center' : (customStyles?.textAlign || 'center'),
          maxWidth: '100%',
          lineHeight: '1.4',
          boxShadow: `0 ${4 * sf}px ${15 * sf}px rgba(0, 0, 0, 0.3)`,
          display: 'flex',
          flexWrap: 'nowrap',
          alignItems: 'center',
          justifyContent,
          gap: `${8 * sf}px`,
        }}>
          {rowWords.map((wordObj, index) => {
            const isActive = currentTime >= wordObj.start && currentTime <= wordObj.end;
            return (
              <span
                key={index}
                style={{
                  color: isActive ? highlightColor : baseColor,
                  fontWeight: isActive ? 'bold' : 'normal',
                  display: 'inline-block',
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
