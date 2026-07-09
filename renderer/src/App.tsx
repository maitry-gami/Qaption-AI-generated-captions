import { useRef, useState, useEffect, useCallback } from 'react';
import { Player } from '@remotion/player';
import type { PlayerRef } from '@remotion/player';
import { CaptionComposition } from './CaptionComposition';
import type { CaptionBox } from './CaptionComposition';

const getDefaultBoxW = (w: number) => w * 0.9;
const getDefaultBoxH = (h: number) => h * 0.17;
const getDefaultBoxL = (w: number, boxW: number) => (w - boxW) / 2;
const getStyleTop = (style: string, compH: number, boxH: number) => {
  const map: Record<string, number> = {
    'hormozi-style': 0.80,
    'ali-abdaal':    0.85,
    'mr-beast':      0.75,
  };
  const factor = map[style] ?? 0.85;
  return compH * factor - boxH;
};

function App() {
  const playerRef = useRef<PlayerRef>(null);
  const [style, setStyle] = useState('hormozi-style');
  const [captions, setCaptions] = useState<any>(null);
  const [videoAdjustments, setVideoAdjustments] = useState({
    brightness: 1.0, contrast: 1.0, saturation: 1.0, exposure: 0.0, shadows: 0.0,
  });
  const [customStyles, setCustomStyles] = useState<any>({
    color: '#ffffff',
    opacity: 1.0,
    fontFamily: 'Montserrat',
    textAlign: 'center',
  });
  const [compW, setCompW] = useState(720);
  const [compH, setCompH] = useState(1280);

  const [captionBox, setCaptionBox] = useState<CaptionBox>({
    left:   getDefaultBoxL(720, getDefaultBoxW(720)),
    top:    getStyleTop('hormozi-style', 1280, getDefaultBoxH(1280)),
    width:  getDefaultBoxW(720),
    height: getDefaultBoxH(1280),
  });
  const [isPlayerPlaying, setIsPlayerPlaying] = useState(false);
  const [captionsEditMode, setCaptionsEditMode] = useState(false);

  const fps = 30;
  const [durationInFrames, setDurationInFrames] = useState(10 * fps);
  const [isVideoLoaded, setIsVideoLoaded] = useState(false);

  // Keep refs accessible in closures
  const captionBoxRef = useRef(captionBox);
  captionBoxRef.current = captionBox;
  const customStylesRef = useRef(customStyles);
  customStylesRef.current = customStyles;

  // Update default box top when style or composition size changes
  useEffect(() => {
    if (compW === 0 || compH === 0) return;
    
    const bw = getDefaultBoxW(compW);
    const bh = getDefaultBoxH(compH);
    const bl = getDefaultBoxL(compW, bw);
    const top = getStyleTop(style, compH, bh);

    const cs = customStylesRef.current;
    
    // Only use default if the user hasn't set custom offsets
    const left = cs.xOffset ?? bl;
    const y = cs.yOffset ?? top;
    const s = cs.scale ?? 1.0;

    setCaptionBox({ left, top: y, width: bw * s, height: bh * s });
  }, [style, compW, compH]);

  const sendBoxToFlutter = useCallback((box: CaptionBox) => {
    if ((window as any).StylesChangedChannel) {
      (window as any).StylesChangedChannel.postMessage(
        JSON.stringify({
          xOffset: box.left,
          yOffset: box.top,
          scale: box.width / getDefaultBoxW(compW),
          boxLeft: box.left,
          boxTop: box.top,
          boxWidth: box.width,
          boxHeight: box.height,
        })
      );
    }
  }, [compW]);

  useEffect(() => {
    fetch('/captions.json')
      .then(r => r.json())
      .then(data => setCaptions(data))
      .catch(console.error);

    // ── Flutter → JS bridges ─────────────────────────────────────────────────

    (window as any).setStyle = (newStyle: string) => {
      setStyle(newStyle);
    };

    // Video adjustments bridge
    (window as any).setVideoAdjustments = (
      brightness: number, contrast: number, saturation: number,
      exposure: number, shadows: number
    ) => {
      setVideoAdjustments({ brightness, contrast, saturation, exposure, shadows });
    };

    (window as any).setCustomStyles = (
      color: string,
      opacity: number,
      fontFamily: string,
      textAlign: string,
      emphasisColor?: string,
      activeWordColor?: string,
      isActiveWordColorEnabled?: boolean,
      xOffset?: number,
      yOffset?: number,
      scaleVal?: number,
      wordsPerLine?: number,
      maxLinesPerFrame?: number,
    ) => {
      setCustomStyles((prev: any) => ({
        ...prev,
        color,
        opacity,
        fontFamily,
        textAlign,
        emphasisColor,
        activeWordColor,
        isActiveWordColorEnabled,
        xOffset: xOffset ?? prev.xOffset,
        yOffset: yOffset ?? prev.yOffset,
        scale: scaleVal ?? prev.scale,
        wordsPerLine: wordsPerLine ?? prev.wordsPerLine ?? 3,
        maxLinesPerFrame: maxLinesPerFrame ?? prev.maxLinesPerFrame ?? 2,
      }));

      // Also update box position/size from legacy xOffset/yOffset/scale
      if (xOffset != null || yOffset != null || scaleVal != null) {
        setCaptionBox(prev => {
          const bw = getDefaultBoxW(compW);
          const bh = getDefaultBoxH(compH);
          const s = scaleVal ?? (prev.width / bw);
          return {
            left:   xOffset != null ? xOffset : prev.left,
            top:    yOffset != null ? yOffset : prev.top,
            width:  bw * s,
            height: bh * s,
          };
        });
      }
    };

    // New bridge: full box rect (called by CaptionComposition on drag/resize)
    (window as any).updateCaptionBox = (
      left: number, top: number, width: number, height: number
    ) => {
      const box: CaptionBox = { left, top, width, height };
      setCaptionBox(box);
    };

    (window as any).commitCaptionBox = (
      left: number, top: number, width: number, height: number
    ) => {
      const box: CaptionBox = { left, top, width, height };
      const newScale = width / getDefaultBoxW(compW);
      
      // Update customStyles state so React remembers it if style changes
      setCustomStyles((prev: any) => ({
        ...prev,
        xOffset: left,
        yOffset: top,
        scale: newScale,
      }));
      
      sendBoxToFlutter(box);
    };

    // Legacy bridge for backward compat (Flutter may call this)
    (window as any).updateCaptionTransform = (newX: number, newY: number, newScale: number) => {
      const box: CaptionBox = {
        left:   newX,
        top:    newY,
        width:  getDefaultBoxW(compW) * newScale,
        height: getDefaultBoxH(compH) * newScale,
      };
      setCaptionBox(box);
      sendBoxToFlutter(box);
    };

    // New bridge: Flutter can directly set a full box rect
    (window as any).setCaptionBox = (
      left: number, top: number, width: number, height: number
    ) => {
      setCaptionBox({ left, top, width, height });
    };

    (window as any).updateCaptionScale = (newScale: number) => {
      setCaptionBox(prev => {
        const aspect = prev.height / prev.width;
        const newW = getDefaultBoxW(compW) * newScale;
        const newH = newW * aspect;
        // Keep center point the same
        const cx = prev.left + prev.width / 2;
        const cy = prev.top + prev.height / 2;
        const newL = cx - newW / 2;
        const newT = cy - newH / 2;
        
        const box: CaptionBox = { left: newL, top: newT, width: newW, height: newH };
        sendBoxToFlutter(box);
        return box;
      });
    };

    (window as any).togglePlay = () => {
      if (playerRef.current) {
        if (playerRef.current.isPlaying()) {
          playerRef.current.pause();
        } else {
          playerRef.current.setVolume(1);
          playerRef.current.play();
        }
      }
    };

    (window as any).toggleMute = () => {
      if (playerRef.current) {
        const vol = playerRef.current.getVolume();
        playerRef.current.setVolume(vol === 0 ? 1 : 0);
      }
    };

    let lastSeekTime = 0;
    let seekTimeout: number | null = null;
    (window as any).seekTo = (timeInSeconds: number) => {
      const targetFrame = Math.floor(timeInSeconds * fps);
      const now = performance.now();

      // Clear any pending final seek
      if (seekTimeout) clearTimeout(seekTimeout);

      if (now - lastSeekTime > 50) {
        // Execute immediately if enough time passed
        if (playerRef.current) {
          playerRef.current.seekTo(targetFrame);
          const v = document.querySelector('video');
          if (v && v.paused) v.style.opacity = v.style.opacity === '0.99' ? '1' : '0.99';
        }
        lastSeekTime = now;
      } else {
        // Schedule the final seek to ensure we land exactly where the drag ends
        seekTimeout = setTimeout(() => {
          if (playerRef.current) {
            playerRef.current.seekTo(targetFrame);
            const v = document.querySelector('video');
            if (v && v.paused) v.style.opacity = v.style.opacity === '0.99' ? '1' : '0.99';
          }
          lastSeekTime = performance.now();
        }, 50);
      }

      setIsPlayerPlaying(false);
      setCaptionsEditMode(false);
    };

    (window as any).updateCaptions = (captionJson: string) => {
      try {
        const data = JSON.parse(captionJson);
        setCaptions(data);
        if (data.segments && data.segments.length > 0) {
          const lastSeg = data.segments[data.segments.length - 1];
          const captionDuration = Math.floor((lastSeg.end + 1.0) * fps);
          if (captionDuration > durationInFrames) {
            setDurationInFrames(captionDuration);
          }
        }
      } catch (e) {
        console.error('Failed to parse injected captions:', e);
      }
    };

    const detectVideoDimensions = () => {
      const videoElement = document.createElement('video');
      videoElement.src = '/video.mp4';
      videoElement.crossOrigin = 'anonymous';
      videoElement.muted = true;
      videoElement.playsInline = true;
      videoElement.onloadedmetadata = async () => {
        setCompW(videoElement.videoWidth);
        setCompH(videoElement.videoHeight);
        if ((window as any).VideoDimensionsChannel) {
          (window as any).VideoDimensionsChannel.postMessage(
            JSON.stringify({
              videoWidth: videoElement.videoWidth,
              videoHeight: videoElement.videoHeight,
            })
          );
        }
        setIsVideoLoaded(true);
      };
    };

    (window as any).reloadVideo = () => {
      generateThumbnails();
      detectVideoDimensions();
    };

    (window as any).setCaptionsEditMode = (enabled: boolean) => {
      setCaptionsEditMode(enabled);
    };

    let animationFrame: number;
    let lastSentTime = -1;
    const updateTime = () => {
      if (playerRef.current) {
        const frame = playerRef.current.getCurrentFrame();
        const t = frame / fps;
        const playing = playerRef.current.isPlaying();
        setIsPlayerPlaying(playing);

        if ((window as any).TimeUpdateChannel) {
          const d = durationInFrames / fps;
          if (Math.abs(t - lastSentTime) > 0.033) {
            lastSentTime = t;
            (window as any).TimeUpdateChannel.postMessage(
              JSON.stringify({
                currentTime: t,
                duration: d,
                isPlaying: playing,
                isMuted: playerRef.current.getVolume() === 0,
              })
            );
          }
        }
      }
      animationFrame = requestAnimationFrame(updateTime);
    };
    updateTime();

    setTimeout(() => {
      generateThumbnails();
      detectVideoDimensions();
    }, 1000);

    return () => cancelAnimationFrame(animationFrame);
  }, [durationInFrames, fps, sendBoxToFlutter]);

  const generateThumbnails = () => {
    const hiddenVideo = document.createElement('video');
    hiddenVideo.src = '/video.mp4';
    hiddenVideo.crossOrigin = 'anonymous';
    hiddenVideo.muted = true;
    hiddenVideo.playsInline = true;

    hiddenVideo.onloadedmetadata = async () => {
      const duration =
        hiddenVideo.duration && hiddenVideo.duration !== Infinity
          ? hiddenVideo.duration
          : durationInFrames / fps;
      setDurationInFrames(Math.floor(duration * fps));

      const canvas = document.createElement('canvas');
      canvas.width = 100;
      canvas.height = Math.floor(
        100 * (hiddenVideo.videoHeight / hiddenVideo.videoWidth)
      );
      const ctx = canvas.getContext('2d');
      if (!ctx) return;

      const thumbs: string[] = [];
      const numFrames = 20;
      const interval = duration / numFrames;

      for (let i = 0; i < numFrames; i++) {
        hiddenVideo.currentTime = i * interval;
        await new Promise((resolve) => { hiddenVideo.onseeked = resolve; });
        await new Promise(r => setTimeout(r, 100));
        ctx.drawImage(hiddenVideo, 0, 0, canvas.width, canvas.height);
        thumbs.push(canvas.toDataURL('image/jpeg', 0.5));
      }

      if ((window as any).ThumbnailsChannel) {
        (window as any).ThumbnailsChannel.postMessage(JSON.stringify(thumbs));
      }
    };
  };

  return (
    <div style={{ width: '100%', height: '100%', position: 'relative', overflow: 'hidden', backgroundColor: 'black' }}>
      <style>{`
        video::-webkit-media-controls { display: none !important; }
        video::-webkit-media-controls-enclosure { display: none !important; }
        video::-webkit-media-controls-overlay-play-button { display: none !important; }
        video::-webkit-media-controls-start-playback-button { display: none !important; -webkit-appearance: none; }
        video::before, video::after { display: none !important; }
        video[poster] { object-fit: contain; background: black; }
        ::-webkit-media-controls-play-button { display: none !important; }
      `}</style>
      <Player
        ref={playerRef}
        component={CaptionComposition}
        inputProps={{
          style,
          captions,
          firstFrame: null, // Legacy prop, no longer needed
          isPlaying: isPlayerPlaying,
          videoAdjustments,
          customStyles: {
            ...customStyles,
            captionBox,
          },
          showBoundingBox: captionsEditMode && !isPlayerPlaying,
        }}
        durationInFrames={durationInFrames}
        compositionWidth={compW}
        compositionHeight={compH}
        fps={fps}
        style={{ width: '100%', height: '100%' }}
        controls={false}
        clickToPlay={false}
        renderPlayPauseButton={() => null}
        showPosterWhenUnplayed={true}
        renderPoster={() => (
          <video
            src="/video.mp4"
            muted
            playsInline
            style={{ width: '100%', height: '100%', objectFit: 'contain', backgroundColor: 'black' }}
            onLoadedMetadata={(e) => {
              e.currentTarget.currentTime = 0.001;
            }}
          />
        )}
      />
      {/* Black overlay blocks the grey Remotion/browser play button until the video is loaded */}
      {!isVideoLoaded && (
        <div style={{
          position: 'absolute',
          inset: 0,
          backgroundColor: 'black',
          zIndex: 9998,
          pointerEvents: 'none',
        }} />
      )}
    </div>
  );
}

export default App;
