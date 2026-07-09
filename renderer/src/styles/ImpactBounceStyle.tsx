import React from 'react';
import { useCurrentFrame, useVideoConfig, spring } from 'remotion';
import type { Segment } from '../CaptionEngine';
import { getPreciseRows, getAutoFitScale } from './captionUtils';
import { loadFont } from '@remotion/google-fonts/Anton';

const { fontFamily } = loadFont('normal');

interface ImpactBounceStyleProps {
  segment: Segment | null;
  customStyles?: any;
}

export const ImpactBounceStyle: React.FC<ImpactBounceStyleProps> = ({ segment, customStyles }) => {
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
  const highlightColor = customStyles?.emphasisColor ? hexToRgba(customStyles.emphasisColor, customStyles.opacity ?? 1) : '#ffe600';
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
      fontFamily: selectedFontFamily,
      fontSize: `${Math.round(16 * sf)}px`,
      textAlign: customStyles?.textAlign === 'random' ? 'center' : (customStyles?.textAlign || 'center'),
      padding: `0 ${Math.round(24 * sf)}px`,
      boxSizing: 'border-box',
    }}>
      {visibleRows.map((rowWords, rowIdx) => (
        <div key={rowIdx} style={{
          display: 'flex',
          justifyContent,
          flexWrap: 'nowrap',
          gap: `${8 * sf}px`,
        }}>
          {rowWords.map((wordObj, index) => {
            const isActive = currentTime >= wordObj.start && currentTime <= wordObj.end;
            const wordStartFrame = Math.floor(wordObj.start * fps);
            const framesSinceStart = frame - wordStartFrame;

            let bounce = 0;
            if (framesSinceStart >= 0 && framesSinceStart < 15) {
              bounce = spring({
                fps,
                frame: framesSinceStart,
                config: { damping: 10, stiffness: 200, mass: 0.8 },
              });
            }

            return (
              <span
                key={index}
                style={{
                  color: isActive ? highlightColor : baseColor,
                  WebkitTextStroke: `${2 * sf}px #000000`,
                  paintOrder: 'stroke fill',
                  textShadow: `${3 * sf}px ${3 * sf}px 0px #000000`,
                  transform: isActive
                    ? `scale(${1 + (bounce * 0.2)}) rotate(${(index % 2 === 0 ? 3 : -3)}deg)`
                    : 'scale(1) rotate(0deg)',
                  display: 'inline-block',
                  margin: `0 ${4 * sf}px`,
                  whiteSpace: 'nowrap',
                }}
              >
                {wordObj.word.toUpperCase()}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};
