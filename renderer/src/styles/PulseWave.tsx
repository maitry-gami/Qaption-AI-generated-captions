import React from 'react';
import { useCurrentFrame, useVideoConfig, spring } from 'remotion';
import type { Segment } from '../CaptionEngine';
import { loadFont } from '@remotion/google-fonts/Outfit';
import { getPreciseRows, getAutoFitScale } from './captionUtils';

const { fontFamily } = loadFont('normal', { weights: ['900'] });

interface PulseWaveProps {
  segment: Segment | null;
  customStyles?: any;
}

export const PulseWave: React.FC<PulseWaveProps> = ({ segment, customStyles }) => {
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
  const baseColor = customStyles?.color ? hexToRgba(customStyles.color, customStyles.opacity ?? 1) : '#FFFFFF';
  const bgColor = customStyles?.emphasisColor ? hexToRgba(customStyles.emphasisColor, customStyles.opacity ?? 1) : '#8B5CF6';
  const selectedFontFamily = customStyles?.fontFamily ? `"${customStyles.fontFamily}", sans-serif` : fontFamily;
  const justifyContentMap: any = { 'left': 'flex-start', 'center': 'center', 'right': 'flex-end', 'random': 'space-around' };
  const justifyContent = customStyles?.textAlign ? justifyContentMap[customStyles.textAlign] : 'center';

  // Break tab settings
  const wordsPerLine: number = customStyles?.wordsPerLine ?? 1;
  const maxLinesPerFrame: number = customStyles?.maxLinesPerFrame ?? 1;

  // Precise: exactly wordsPerLine words per row, exactly maxLinesPerFrame rows visible
  const visibleRows = getPreciseRows(segment, currentTime, wordsPerLine, maxLinesPerFrame);
  const boxWidth = customStyles?.boxWidth ?? 648;
  const autoFitScale = getAutoFitScale(visibleRows, 16 * sf, boxWidth);
  sf *= autoFitScale;
  

  if (visibleRows.length === 0) return null;

  const activeWord = segment.words.find(w => currentTime >= w.start && currentTime <= w.end);
  const wordStartFrame = activeWord ? activeWord.start * fps : 0;

  const scale = spring({
    frame: frame - wordStartFrame,
    fps,
    config: { damping: 10, stiffness: 200, mass: 0.5 },
  });

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
    }}>
      {visibleRows.map((rowWords, rowIdx) => (
        <div key={rowIdx} style={{
          display: 'flex',
          gap: `${8 * sf}px`,
          justifyContent,
        }}>
          {rowWords.map((wordObj, wIdx) => {
            const isActive = currentTime >= wordObj.start && currentTime <= wordObj.end;
            return (
              <div key={wIdx} style={{
                fontFamily: selectedFontFamily,
                fontSize: `${Math.round(16 * sf)}px`,
                fontWeight: '900',
                color: baseColor,
                textTransform: 'uppercase',
                backgroundColor: isActive ? bgColor : bgColor.replace(/[\d.]+\)$/, '0.35)'),
                padding: `${10 * sf}px ${20 * sf}px`,
                borderRadius: `${12 * sf}px`,
                transform: isActive ? `scale(${1 + (scale * 0.2)}) rotate(-2deg)` : 'scale(1)',
                display: 'inline-block',
                boxShadow: isActive
                  ? `0 ${10 * sf}px ${25 * sf}px ${bgColor.replace(/[^,]+(?=\))/, '0.5')}`
                  : 'none',
                whiteSpace: 'nowrap',
              }}>
                {wordObj.word}
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
};
