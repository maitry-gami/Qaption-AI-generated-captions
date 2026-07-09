import React from 'react';
import { useCurrentFrame, useVideoConfig, spring } from 'remotion';
import type { Segment } from '../CaptionEngine';
import { getPreciseRows, getAutoFitScale } from './captionUtils';

export const HormoziStyle: React.FC<{ segment: Segment | null; customStyles?: any }> = ({ segment, customStyles }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const currentTime = frame / fps;

  if (!segment) return null;

  const hexToRgba = (hex: string, opacity: number) => {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    if (!result) return `rgba(255, 255, 255, ${opacity})`;
    return `rgba(${parseInt(result[1], 16)}, ${parseInt(result[2], 16)}, ${parseInt(result[3], 16)}, ${opacity})`;
  };

  const selectedFontFamily = customStyles?.fontFamily ? `"${customStyles.fontFamily}", sans-serif` : '"Montserrat", sans-serif';
  const isDisplayFont = customStyles?.fontFamily === 'Bangers' || customStyles?.fontFamily === 'Bebas Neue';
  const resolvedFontWeight = isDisplayFont ? 400 : 900;

  const justifyContentMap: any = {
    'left': 'flex-start',
    'center': 'center',
    'right': 'flex-end',
    'random': 'space-around',
  };
  const justifyContent = customStyles?.textAlign ? justifyContentMap[customStyles.textAlign] : 'center';

  let sf = customStyles?.scaleFactor ?? 1;
  const wordsPerLine: number = customStyles?.wordsPerLine ?? 3;
  const maxLinesPerFrame: number = customStyles?.maxLinesPerFrame ?? 2;

  // Precise: exactly wordsPerLine words per row, exactly maxLinesPerFrame rows visible
  const visibleRows = getPreciseRows(segment, currentTime, wordsPerLine, maxLinesPerFrame);
  const boxWidth = customStyles?.boxWidth ?? 648;
  const autoFitScale = getAutoFitScale(visibleRows, 16 * sf, boxWidth);
  sf *= autoFitScale;
  

  const alignItems =
    justifyContent === 'flex-start' ? 'flex-start'
    : justifyContent === 'flex-end' ? 'flex-end'
    : 'center';

  return (
    <div style={{
      position: 'absolute',
      top: 0,
      height: '100%',
      width: '100%',
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'center',
      alignItems,
      gap: `${10 * sf}px`,
      padding: `0 ${Math.round(24 * sf)}px`,
    }}>
      {visibleRows.map((rowWords, rowIdx) => (
        <div key={rowIdx} style={{
          display: 'flex',
          justifyContent,
          flexWrap: 'nowrap',
          gap: `${15 * sf}px`,
        }}>
          {rowWords.map((wordObj, i) => {
            const isActive = currentTime >= wordObj.start && currentTime <= wordObj.end;
            const wordStartFrame = Math.floor(wordObj.start * fps);
            const framesSinceStart = frame - wordStartFrame;

            let scale = 1;
            if (framesSinceStart >= 0 && framesSinceStart < 15) {
              scale = spring({
                fps,
                frame: framesSinceStart,
                config: { damping: 12, mass: 0.5, stiffness: 200 },
              });
            }

            const baseColor = customStyles?.color ? hexToRgba(customStyles.color, customStyles.opacity) : '#FFFFFF';
            const emphasisColor = customStyles?.emphasisColor ? hexToRgba(customStyles.emphasisColor, customStyles.opacity) : '#FFD700';
            const activeWordColor = customStyles?.activeWordColor ? hexToRgba(customStyles.activeWordColor, customStyles.opacity) : emphasisColor;

            const activeColor = isActive
              ? (customStyles?.isActiveWordColorEnabled ? activeWordColor : emphasisColor)
              : baseColor;

            return (
              <span key={i} style={{
                fontFamily: selectedFontFamily,
                fontSize: `${Math.round(16 * sf)}px`,
                fontWeight: resolvedFontWeight,
                textTransform: 'uppercase',
                color: activeColor,
                WebkitTextStroke: `${2.5 * sf}px black`,
                paintOrder: 'stroke fill',
                textShadow: `${5 * sf}px ${5 * sf}px 0px rgba(0,0,0,1)`,
                transform: `scale(${scale}) rotate(${isActive ? -2 : 0}deg)`,
                display: 'inline-block',
                whiteSpace: 'nowrap',
              }}>
                {wordObj.word}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};
