import React, { useMemo } from "react";
import {
  AbsoluteFill,
  Sequence,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { getAutoFitScaleForTokens } from './captionUtils';
import type { CaptionData } from "../CaptionEngine";

type MedusaToken = {
  text: string;
  fromMs: number;
  toMs: number;
};

type MedusaPage =
  | {
      kind: "big";
      startMs: number;
      endMs: number;
      token: MedusaToken;
    }
  | {
      kind: "phrase";
      startMs: number;
      endMs: number;
      tokens: MedusaToken[];
      splitAfter: number | null;
    };

type CaptionsMedusaConfig = {
  switchCaptionsEveryMs: number;
  phraseBreakMs: number;
  fontFamily: string;
  textTransform: "none" | "uppercase" | "lowercase" | "capitalize";
  textColor: string;
  highlightColor: string;
  shadowColor: string;
  shadowBlur: number;
  letterSpacingEm: number;
  emphasisWords: string[];
  phraseHighlightWords: string[];
  wordsPerLine: number;
  maxLinesPerFrame: number;
  boxWidth: number;
  scaleFactor: number;
};

const createMedusaPages = (
  words: MedusaToken[],
  config: CaptionsMedusaConfig,
): MedusaPage[] => {
  const sorted = [...words].sort((a, b) => a.fromMs - b.fromMs);
  const emphasis = new Set(
    config.emphasisWords.map((word) => word.trim().toUpperCase()).filter(Boolean),
  );
  const pages: MedusaPage[] = [];

  let phraseTokens: MedusaToken[] = [];
  const flushPhrase = () => {
    if (phraseTokens.length === 0) {
      return;
    }

    pages.push({
      kind: "phrase",
      startMs: phraseTokens[0].fromMs,
      endMs: phraseTokens[phraseTokens.length - 1].toMs,
      tokens: phraseTokens,
      splitAfter: null, // We'll handle chunking during render instead
    });
    phraseTokens = [];
  };

  // Random emphasis every 3, 5 or 7 words
  const gaps = [3, 5, 7];
  let wordsSinceEmphasis = 0;
  let nextGap = gaps[Math.floor(Math.random() * gaps.length)];

  for (const token of sorted) {
    wordsSinceEmphasis++;

    const isManualEmphasis = emphasis.has(token.text.toUpperCase());
    const isRandomEmphasis = wordsSinceEmphasis >= nextGap;
    const isEmphasis = isManualEmphasis || isRandomEmphasis;

    if (isRandomEmphasis) {
      wordsSinceEmphasis = 0;
      nextGap = gaps[Math.floor(Math.random() * gaps.length)];
    }

    if (isEmphasis) {
      flushPhrase();
      pages.push({
        kind: "big",
        startMs: token.fromMs,
        endMs: token.toMs,
        token,
      });
      continue;
    }

    const previous = phraseTokens[phraseTokens.length - 1];
    const gapMs = previous ? token.fromMs - previous.toMs : 0;
    const durationMs =
      phraseTokens.length > 0
        ? token.toMs - phraseTokens[0].fromMs
        : token.toMs - token.fromMs;

    if (
      phraseTokens.length > 0 &&
      (gapMs > config.phraseBreakMs || durationMs > config.switchCaptionsEveryMs)
    ) {
      flushPhrase();
    }

    phraseTokens.push(token);
  }

  flushPhrase();
  return pages;
};

const usePagePop = (fadeFrames = 4) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, fadeFrames], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const scale = interpolate(frame, [0, 6], [0.985, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return { opacity, scale };
};

const medusaTextStyle = ({
  config,
  fontSize,
  isDisplayFont
}: {
  config: CaptionsMedusaConfig;
  fontSize: number;
  isDisplayFont: boolean;
}): React.CSSProperties => ({
  fontFamily: `"${config.fontFamily}", sans-serif`,
  fontSize,
  fontWeight: isDisplayFont ? 400 : 900,
  lineHeight: 0.9,
  letterSpacing: `${config.letterSpacingEm}em`,
  textTransform: config.textTransform,
  WebkitTextStroke: `4px ${config.shadowColor}`,
  paintOrder: "stroke fill",
  textShadow: `4.5px 5px ${config.shadowBlur}px ${config.shadowColor}`,
  filter: "blur(0.1px)",
  whiteSpace: "nowrap",
});

const PhraseWord: React.FC<{
  active: boolean;
  children: React.ReactNode;
  config: CaptionsMedusaConfig;
}> = ({ active, children, config }) => {
  return (
    <span
      style={{
        color: active ? config.highlightColor : config.textColor,
      }}
    >
      {children}
    </span>
  );
};

const PhrasePage: React.FC<{
  page: Extract<MedusaPage, { kind: "phrase" }>;
  config: CaptionsMedusaConfig;
  isDisplayFont: boolean;
}> = ({ page, config, isDisplayFont }) => {
  const { opacity, scale } = usePagePop();
  const phraseHighlightSet = new Set(
    config.phraseHighlightWords
      .map((word) => word.trim().toUpperCase())
      .filter(Boolean),
  );
  
  // Highlighting specific words can be dynamic; here we just use what was passed or highlight everything
  // In the original, it checks against phraseHighlightSet. We will highlight the currently active word based on time.
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const currentTimeMs = (frame / fps) * 1000;
  const absoluteTimeMs = page.startMs + currentTimeMs;

  const chunks: MedusaToken[][] = [];
  for (let i = 0; i < page.tokens.length; i += config.wordsPerLine) {
    chunks.push(page.tokens.slice(i, i + config.wordsPerLine));
  }
  const visibleChunks = chunks.slice(-config.maxLinesPerFrame);

  const renderTokens = (tokens: MedusaToken[]) => {
    return tokens.map((token, index) => {
      // Dynamic highlighting based on absolute video time:
      const isActive = absoluteTimeMs >= token.fromMs && absoluteTimeMs <= token.toMs;
      const isHighlighted = isActive || phraseHighlightSet.has(token.text.toUpperCase());
      return (
        <PhraseWord
          key={`${token.fromMs}-${token.toMs}-${token.text}-${index}`}
          active={isHighlighted}
          config={config}
        >
          {index === 0 ? token.text : ` ${token.text}`}
        </PhraseWord>
      );
    });
  };

  const autoFitScale = getAutoFitScaleForTokens(visibleChunks, 50, config.boxWidth);

  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: page.splitAfter === null ? '65%' : '55%',
          transform: `scale(${scale * autoFitScale})`,
          transformOrigin: "center center",
          opacity,
          textAlign: "center",
          width: '90%',
        }}
      >
        {visibleChunks.map((chunk, idx) => (
          <div
            key={idx}
            style={{
              ...medusaTextStyle({ 
                config, 
                fontSize: (chunks.length === 1 ? 45 : (idx === 0 ? 38 : 50)), 
                isDisplayFont 
              }),
              marginTop: idx > 0 ? 10 : 0,
            }}
          >
            {renderTokens(chunk)}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

const BigWordPage: React.FC<{
  page: Extract<MedusaPage, { kind: "big" }>;
  config: CaptionsMedusaConfig;
  isDisplayFont: boolean;
}> = ({ page, config, isDisplayFont }) => {
  const { opacity, scale } = usePagePop(2);

  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
      }}
    >
      <div
        style={{
          position: "absolute",
          top: '60%',
          transform: `scale(${scale})`,
          transformOrigin: "center center",
          opacity,
          color: config.highlightColor,
          ...medusaTextStyle({ config, fontSize: 65, isDisplayFont }),
        }}
      >
        {page.token.text}
      </div>
    </AbsoluteFill>
  );
};

export const MedusaStyle: React.FC<{
  captions: CaptionData | undefined;
  customStyles?: any;
}> = ({ captions, customStyles }) => {
  const { fps } = useVideoConfig();

  const hexToRgba = (hex: string, opacity: number) => {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
    if (!result) return `rgba(255, 255, 255, ${opacity})`;
    return `rgba(${parseInt(result[1], 16)}, ${parseInt(result[2], 16)}, ${parseInt(result[3], 16)}, ${opacity})`;
  };

  const fontFamily = customStyles?.fontFamily || 'Montserrat';
  const isDisplayFont = fontFamily === 'Bangers' || fontFamily === 'Bebas Neue';

  const config: CaptionsMedusaConfig = {
    switchCaptionsEveryMs: 1500,
    phraseBreakMs: 400,
    fontFamily: fontFamily,
    textTransform: "uppercase",
    textColor: customStyles?.color ? hexToRgba(customStyles.color, customStyles.opacity || 1) : "#FFFFFF",
    highlightColor: customStyles?.activeWordColor && customStyles?.isActiveWordColorEnabled
      ? hexToRgba(customStyles.activeWordColor, customStyles.opacity || 1)
      : customStyles?.emphasisColor 
        ? hexToRgba(customStyles.emphasisColor, customStyles.opacity || 1) 
        : "#00FF00",
    shadowColor: "black",
    shadowBlur: 0,
    letterSpacingEm: 0.02,
    emphasisWords: ["Wait", "Look", "Now"], 
    phraseHighlightWords: [], 
    wordsPerLine: customStyles?.wordsPerLine ?? 3,
    maxLinesPerFrame: customStyles?.maxLinesPerFrame ?? 2,
    boxWidth: customStyles?.boxWidth ?? 720,
    scaleFactor: customStyles?.scaleFactor ?? 1,
  };

  const pages = useMemo(() => {
    if (!captions) return [];
    
    // Flatten all words into MedusaTokens
    const tokens: MedusaToken[] = [];
    for (const segment of captions.segments) {
      for (const word of segment.words) {
        tokens.push({
          text: word.word,
          fromMs: word.start * 1000,
          toMs: word.end * 1000,
        });
      }
    }

    return createMedusaPages(tokens, config);
  }, [captions, config]);

  return (
    <AbsoluteFill>
      {pages.map((page, index) => {
        const nextPage = pages[index + 1] ?? null;
        const startFrame = (page.startMs / 1000) * fps;
        const endFrame = nextPage
          ? (nextPage.startMs / 1000) * fps
          : (page.endMs / 1000) * fps;
        const durationInFrames = Math.max(1, Math.floor(endFrame - startFrame));

        if (durationInFrames <= 0) {
          return null;
        }

        return (
          <Sequence
            key={`${page.kind}-${page.startMs}-${index}`}
            from={Math.floor(startFrame)}
            durationInFrames={durationInFrames}
          >
            {page.kind === "big" ? (
              <BigWordPage page={page} config={config} isDisplayFont={isDisplayFont} />
            ) : (
              <PhrasePage page={page} config={config} isDisplayFont={isDisplayFont} />
            )}
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
