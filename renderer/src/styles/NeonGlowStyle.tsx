import React from 'react';
import { useCurrentFrame, useVideoConfig, spring } from 'remotion';
import type { Segment } from '../CaptionEngine';
import { getPreciseRows, getAutoFitScale } from './captionUtils';
import { loadFont } from '@remotion/google-fonts/Orbitron';

const { fontFamily } = loadFont('normal', { weights: ['900'] });

interface NeonGlowStyleProps {
  segment: Segment | null;
  customStyles?: any;
}

export const NeonGlowStyle: React.FC<NeonGlowStyleProps> = ({ segment, customStyles }) => {
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
  const glowColor = customStyles?.emphasisColor ? hexToRgba(customStyles.emphasisColor, customStyles.opacity ?? 1) : '#00ffcc';
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
      gap: `${10 * sf}px`,
      fontFamily: selectedFontFamily,
      fontSize: `${Math.round(16 * sf)}px`,
      fontWeight: '900',
      textAlign: customStyles?.textAlign === 'random' ? 'center' : (customStyles?.textAlign || 'center'),
      padding: `0 ${Math.round(24 * sf)}px`,
      boxSizing: 'border-box',
    }}>
      {visibleRows.map((rowWords, rowIdx) => (
        <div key={rowIdx} style={{
          display: 'flex',
          justifyContent,
          flexWrap: 'nowrap',
          gap: `${10 * sf}px`,
        }}>
          {rowWords.map((wordObj, index) => {
            const isActive = currentTime >= wordObj.start && currentTime <= wordObj.end;
            const wordStartFrame = wordObj.start * fps;

            const scale = spring({
              frame: frame - wordStartFrame,
              fps,
              config: { damping: 8, stiffness: 220, mass: 0.4 },
            });

            return (
              <span
                key={index}
                style={{
                  color: isActive ? glowColor : baseColor,
                  textShadow: isActive
                    ? `0 0 ${5 * sf}px ${glowColor}, 0 0 ${10 * sf}px ${glowColor}, 0 0 ${20 * sf}px ${glowColor}`
                    : `${2 * sf}px ${2 * sf}px ${4 * sf}px rgba(0,0,0,0.8)`,
                  transform: isActive ? `scale(${1 + (scale * 0.15)})` : 'scale(1)',
                  display: 'inline-block',
                  transition: 'color 0.1s ease-in-out',
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
