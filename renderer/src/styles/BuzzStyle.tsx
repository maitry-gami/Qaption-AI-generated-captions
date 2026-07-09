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

export type CaptionsBuzzConfig = {
  switchCaptionsEveryMs: number;
  phraseBreakMs: number;
  fontFamily: string;
  fontSize: number;
  lineHeight: number;
  textTransform: "none" | "uppercase" | "lowercase" | "capitalize";
  textColor: string;
  highlightColor: string;
  shadowColor: string;
  shadowBlur: number;
  anchorX: number;
  anchorY: number;
  textAlign: "left" | "center" | "right";
  letterSpacingEm: number;
  layout: "auto" | "center-word" | "karaoke-left" | "karaoke-center" | "stack";
  centerWordFontSize: number;
  centerWordAnchorX: number;
  centerWordAnchorY: number;
  emphasisWords: string[];
  inactiveTextColor: string;
  dimTextColor: string;
  activeGlowColor: string;
  inactiveGlowColor: string;
  stackTopText: string | null;
  stackTopFontSize: number;
  stackBottomFontSize: number;
  wordsPerLine: number;
  maxLinesPerFrame: number;
  boxWidth: number;
};

type CaptionPhraseToken = {
  text: string;
  fromMs: number;
  toMs: number;
};

type CaptionPhrase = {
  startMs: number;
  endMs: number;
  tokens: CaptionPhraseToken[];
};

const createPhrasePages = ({
  tokens,
  maxPhraseDurationMs,
  phraseBreakMs,
  emphasisWords,
}: {
  tokens: CaptionPhraseToken[];
  maxPhraseDurationMs: number;
  phraseBreakMs: number;
  emphasisWords: string[];
}) => {
  const sorted = [...tokens].sort((a, b) => a.fromMs - b.fromMs);
  const pages: CaptionPhrase[] = [];
  const emphasisSet = new Set(
    emphasisWords.map((word) => word.trim().toUpperCase()).filter(Boolean),
  );

  for (const token of sorted) {
    const isEmphasis = emphasisSet.has(token.text.trim().toUpperCase());

    if (isEmphasis) {
      pages.push({
        startMs: token.fromMs,
        endMs: token.toMs,
        tokens: [token],
      });
      continue;
    }

    const current = pages[pages.length - 1];
    const previousToken = current?.tokens[current.tokens.length - 1];
    const currentIsEmphasis = previousToken
      ? emphasisSet.has(previousToken.text.trim().toUpperCase())
      : false;
    const gapMs = previousToken ? token.fromMs - previousToken.toMs : 0;
    const phraseDurationMs = current ? token.toMs - current.startMs : 0;
    const shouldStartNewPhrase =
      !current ||
      currentIsEmphasis ||
      gapMs > phraseBreakMs ||
      phraseDurationMs > maxPhraseDurationMs;

    if (shouldStartNewPhrase) {
      pages.push({
        startMs: token.fromMs,
        endMs: token.toMs,
        tokens: [token],
      });
    } else {
      current.tokens.push(token);
      current.endMs = token.toMs;
    }
  }

  return pages;
};

const textForToken = (text: string, index: number) => {
  const clean = text.trim();
  return index === 0 ? clean : ` ${clean}`;
};

const shadowFor = ({
  active,
  config,
}: {
  active: boolean;
  config: CaptionsBuzzConfig;
}) => {
  const base = `0 3px ${config.shadowBlur}px ${config.shadowColor}`;
  const activeOuterGlow = config.activeGlowColor.replace(/[\d.]+\)$/g, '0.4)');
  const glow = active
    ? `0 0 5px ${config.activeGlowColor}, 0 0 10px ${activeOuterGlow}`
    : `0 0 4px ${config.inactiveGlowColor}, 0 0 8px rgba(255,255,255,0.2)`;

  return `${base}, ${glow}`;
};

const usePageEntrance = () => {
  const frame = useCurrentFrame();

  const opacity = interpolate(frame, [0, 5], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const scale = interpolate(frame, [0, 7], [0.985, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return { opacity, scale };
};

const useActiveToken = (page: CaptionPhrase) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const currentTimeMs = (frame / fps) * 1000;
  const absoluteTimeMs = page.startMs + currentTimeMs;

  return page.tokens.findIndex(
    (t) => t.fromMs <= absoluteTimeMs && t.toMs > absoluteTimeMs,
  );
};

const baseTextStyle = ({
  config,
  fontSize,
  isDisplayFont,
}: {
  config: CaptionsBuzzConfig;
  fontSize: number;
  isDisplayFont: boolean;
}): React.CSSProperties => {
  return {
    fontFamily: `"${config.fontFamily}", sans-serif`,
    fontSize,
    lineHeight: config.lineHeight,
    fontWeight: isDisplayFont ? 400 : 900,
    letterSpacing: `${config.letterSpacingEm}em`,
    textTransform: config.textTransform,
    whiteSpace: "nowrap",
    textAlign: config.textAlign,
    filter: "blur(0.35px)",
  };
};

const TokenSpan: React.FC<{
  children: React.ReactNode;
  active: boolean;
  dim?: boolean;
  config: CaptionsBuzzConfig;
}> = ({ children, active, dim = false, config }) => {
  return (
    <span
      style={{
        color: dim
          ? config.dimTextColor
          : active
            ? config.highlightColor
            : config.inactiveTextColor,
        opacity: dim ? 0.5 : 1,
        textShadow: shadowFor({ active, config }),
        transition: 'color 0.1s ease, text-shadow 0.1s ease',
      }}
    >
      {children}
    </span>
  );
};

const CenterWordPage: React.FC<{
  page: CaptionPhrase;
  config: CaptionsBuzzConfig;
  isDisplayFont: boolean;
}> = ({ page, config, isDisplayFont }) => {
  const { width, height } = useVideoConfig();
  const activeIndex = useActiveToken(page);
  const currentToken = page.tokens[Math.max(activeIndex, 0)] ?? page.tokens[0];
  const { opacity, scale } = usePageEntrance();

  if (!currentToken) {
    return null;
  }

  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left: width * config.centerWordAnchorX,
          top: height * config.centerWordAnchorY,
          transform: `translate(-50%, -50%) scale(${scale})`,
          opacity,
          ...baseTextStyle({ config, fontSize: config.centerWordFontSize, isDisplayFont }),
        }}
      >
        <TokenSpan active={activeIndex >= 0} config={config}>
          {currentToken.text.trim()}
        </TokenSpan>
      </div>
    </AbsoluteFill>
  );
};

const KaraokePage: React.FC<{
  page: CaptionPhrase;
  config: CaptionsBuzzConfig;
  mode: "karaoke-left" | "karaoke-center";
  isDisplayFont: boolean;
}> = ({ page, config, mode, isDisplayFont }) => {
  const { width, height } = useVideoConfig();
  const activeIndex = useActiveToken(page);
  const { opacity, scale } = usePageEntrance();
  const isLeft = mode === "karaoke-left";
  const visibleTokens = page.tokens.filter((_, index) => {
    return activeIndex < 0 ? index === 0 : index <= activeIndex;
  });

  const chunks: CaptionPhraseToken[][] = [];
  for (let i = 0; i < visibleTokens.length; i += config.wordsPerLine) {
    chunks.push(visibleTokens.slice(i, i + config.wordsPerLine));
  }
  const visibleChunks = chunks.slice(-config.maxLinesPerFrame);

  const left = isLeft ? Math.round(width * config.anchorX) : width / 2;
  const top = Math.round(height * config.anchorY);
  const autoFitScale = getAutoFitScaleForTokens(visibleChunks, config.fontSize, config.boxWidth);

  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left,
          top,
          transform: isLeft
            ? `translate(0, -50%) scale(${scale * autoFitScale})`
            : `translate(-50%, -50%) scale(${scale * autoFitScale})`,
          transformOrigin: isLeft ? "left center" : "center center",
          opacity,
          ...baseTextStyle({ config, fontSize: config.fontSize, isDisplayFont }),
          display: 'flex',
          flexDirection: 'column',
          alignItems: isLeft ? 'flex-start' : 'center',
          gap: `${10}px`,
        }}
      >
        {visibleChunks.map((chunk, chunkIdx) => (
          <div key={chunkIdx} style={{ display: 'flex', gap: '8px', flexWrap: 'nowrap' }}>
            {chunk.map((token) => (
              <TokenSpan
                key={`${token.fromMs}-${token.toMs}-${token.text}`}
                active={page.tokens.indexOf(token) === activeIndex}
                config={config}
              >
                {token.text.trim()}
              </TokenSpan>
            ))}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};

const StackPage: React.FC<{
  page: CaptionPhrase;
  config: CaptionsBuzzConfig;
  isDisplayFont: boolean;
}> = ({ page, config, isDisplayFont }) => {
  const { height } = useVideoConfig();
  const activeIndex = useActiveToken(page);
  const activeToken = page.tokens[Math.max(activeIndex, 0)] ?? page.tokens[0];
  const topText =
    config.stackTopText ??
    page.tokens
      .slice(0, Math.max(activeIndex, 0))
      .map((token) => token.text.trim())
      .join(" ");
  const { opacity, scale } = usePageEntrance();

  if (!activeToken) {
    return null;
  }

  return (
    <AbsoluteFill
      style={{
        justifyContent: "center",
        alignItems: "center",
      }}
    >
      <div
        style={{
          transform: `scale(${scale}) translateY(150px)`,
          opacity,
          textAlign: "center",
        }}
      >
        {topText ? (
          <div
            style={{
              ...baseTextStyle({ config, fontSize: config.stackTopFontSize, isDisplayFont }),
              color: config.inactiveTextColor,
              textShadow: shadowFor({ active: false, config }),
              marginBottom: height * 0.02,
            }}
          >
            {topText}
          </div>
        ) : null}
        <div
          style={baseTextStyle({
            config,
            fontSize: config.stackBottomFontSize,
            isDisplayFont,
          })}
        >
          <TokenSpan active config={config}>
            {activeToken.text.trim()}
          </TokenSpan>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const CaptionPage: React.FC<{ page: CaptionPhrase; config: CaptionsBuzzConfig; isDisplayFont: boolean }> = ({
  page,
  config,
  isDisplayFont,
}) => {
  const resolvedLayout =
    config.layout === "auto"
      ? page.tokens.length === 1
        ? "center-word"
        : "karaoke-left"
      : config.layout;

  return (
    <>
      {resolvedLayout === "center-word" ? (
        <CenterWordPage page={page} config={config} isDisplayFont={isDisplayFont} />
      ) : null}
      {resolvedLayout === "karaoke-left" || resolvedLayout === "karaoke-center" ? (
        <KaraokePage page={page} config={config} mode={resolvedLayout} isDisplayFont={isDisplayFont} />
      ) : null}
      {resolvedLayout === "stack" ? (
        <StackPage page={page} config={config} isDisplayFont={isDisplayFont} />
      ) : null}
    </>
  );
};

export const BuzzStyle: React.FC<{
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

  const activeColorHex = (customStyles?.activeWordColor && customStyles?.isActiveWordColorEnabled)
    ? customStyles.activeWordColor
    : (customStyles?.emphasisColor || "#00FFFF");

  const config: CaptionsBuzzConfig = {
    switchCaptionsEveryMs: 1500,
    phraseBreakMs: 400,
    fontFamily: fontFamily,
    fontSize: 35,
    lineHeight: 1.1,
    textTransform: "uppercase",
    textColor: customStyles?.color ? hexToRgba(customStyles.color, customStyles.opacity || 1) : "#FFFFFF",
    highlightColor: hexToRgba(activeColorHex, customStyles?.opacity || 1),
    shadowColor: "black",
    shadowBlur: 2,
    anchorX: 0.1,
    anchorY: 0.65,
    textAlign: "center",
    letterSpacingEm: 0,
    layout: "auto",
    centerWordFontSize: 50,
    centerWordAnchorX: 0.5,
    centerWordAnchorY: 0.65,
    emphasisWords: ["WAIT", "LOOK", "NOW", "YES", "NO"],
    inactiveTextColor: "rgba(255, 255, 255, 0.7)",
    dimTextColor: "rgba(255, 255, 255, 0.3)",
    activeGlowColor: hexToRgba(activeColorHex, 0.6),
    inactiveGlowColor: "rgba(255, 255, 255, 0.1)",
    stackTopText: null,
    stackTopFontSize: 30,
    stackBottomFontSize: 45,
    wordsPerLine: customStyles?.wordsPerLine ?? 3,
    maxLinesPerFrame: customStyles?.maxLinesPerFrame ?? 2,
    boxWidth: customStyles?.boxWidth ?? 720,
  };

  const pages = useMemo(() => {
    if (!captions) return [];
    
    // Flatten all words into tokens
    const tokens: CaptionPhraseToken[] = [];
    for (const segment of captions.segments) {
      for (const word of segment.words) {
        tokens.push({
          text: word.word,
          fromMs: word.start * 1000,
          toMs: word.end * 1000,
        });
      }
    }

    return createPhrasePages({
      tokens,
      maxPhraseDurationMs: config.switchCaptionsEveryMs,
      phraseBreakMs: config.phraseBreakMs,
      emphasisWords: config.emphasisWords,
    });
  }, [captions, config]);

  return (
    <AbsoluteFill>
      {pages.map((page, index) => {
        const nextPage = pages[index + 1] ?? null;
        const startFrame = (page.startMs / 1000) * fps;
        const endFrame = Math.min(
          nextPage ? (nextPage.startMs / 1000) * fps : Number.POSITIVE_INFINITY,
          startFrame + (config.switchCaptionsEveryMs / 1000) * fps,
        );
        const durationInFrames = Math.max(1, Math.floor(endFrame - startFrame));
        if (durationInFrames <= 0) return null;

        return (
          <Sequence
            key={index}
            from={Math.floor(startFrame)}
            durationInFrames={durationInFrames}
          >
            <CaptionPage page={page} config={config} isDisplayFont={isDisplayFont} />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
