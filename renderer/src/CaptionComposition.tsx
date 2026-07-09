import React, { useRef } from 'react';
import {
  AbsoluteFill,
  OffthreadVideo,
  Video,
  Img,
  useCurrentFrame,
  useVideoConfig,
  staticFile,
} from 'remotion';
import { HormoziStyle } from './styles/HormoziStyle';
import { AliAbdaalStyle } from './styles/AliAbdaalStyle';
import { MrBeastStyle } from './styles/MrBeastStyle';
import { MedusaStyle } from './styles/MedusaStyle';
import { BuzzStyle } from './styles/BuzzStyle';
import { KaraokeFlow } from './styles/KaraokeFlow';
import { PulseWave } from './styles/PulseWave';
import { TypewriterPro } from './styles/TypewriterPro';
import { NeonGlowStyle } from './styles/NeonGlowStyle';
import { ImpactBounceStyle } from './styles/ImpactBounceStyle';
import { MinimalistBgStyle } from './styles/MinimalistBgStyle';
import type { CaptionData, Segment } from './CaptionEngine';

// ─── Types ────────────────────────────────────────────────────────────────────
export interface CaptionBox {
  left: number;
  top: number;
  width: number;
  height: number;
}

interface CaptionCompositionProps {
  style?: string;
  captions?: CaptionData;
  customStyles?: {
    color: string;
    opacity: number;
    fontFamily: string;
    textAlign: string;
    xOffset?: number;
    yOffset?: number;
    scale?: number;
    previewScale?: number;
    captionBox?: CaptionBox;
    emphasisColor?: string;
    activeWordColor?: string;
    isActiveWordColorEnabled?: boolean;
    wordsPerLine?: number;
    maxLinesPerFrame?: number;
  };
  videoAdjustments?: {
    brightness: number;
    contrast: number;
    saturation: number;
    exposure: number;
    shadows: number;
  };
  showBoundingBox?: boolean;
  firstFrame?: string;
  isPlaying?: boolean;
  hideVideo?: boolean;
  isExport?: boolean;
}

// ─── Component ────────────────────────────────────────────────────────────────
export const CaptionComposition: React.FC<CaptionCompositionProps> = ({
  style = 'hormozi-style',
  captions,
  customStyles,
  videoAdjustments,
  showBoundingBox = false,
  firstFrame,
  isPlaying = false,
  hideVideo = false,
  isExport = false,
}) => {
  const frame = useCurrentFrame();
  const { fps, width: COMP_W, height: COMP_H } = useVideoConfig();

  const DEFAULT_BOX_W = COMP_W * 0.9;
  const DEFAULT_BOX_H = COMP_H * 0.17;
  const DEFAULT_BOX_L = (COMP_W - DEFAULT_BOX_W) / 2;

  // ── Video CSS filter from adjustments ─────────────────────────────────────
  const vAdj = videoAdjustments ?? { brightness: 1, contrast: 1, saturation: 1, exposure: 0, shadows: 0 };
  // Exposure is an extra brightness multiplier: (1 + exposure)
  const exposureMult = 1.0 + vAdj.exposure;
  // Shadows: lift blacks via a subtle brightness layer (CSS has no direct shadows lift)
  const shadowsBrightness = 1.0 + vAdj.shadows * 0.3;
  const videoFilter = `brightness(${vAdj.brightness * exposureMult * shadowsBrightness}) contrast(${vAdj.contrast}) saturate(${vAdj.saturation})`.trim();
  const MIN_BOX_W = COMP_W * 0.25;
  const MIN_BOX_H = COMP_H * 0.06;

  const getStyleTop = (s: string) => {
    const map: Record<string, number> = {
      'hormozi-style': 0.77,
      'ali-abdaal':    0.82,
      'mr-beast':      0.72,
    };
    return COMP_H * (map[s] ?? 0.82) - DEFAULT_BOX_H;
  };

  const currentTime = frame / fps;
  const boxRef = useRef<HTMLDivElement>(null);

  // ── Active caption segment ──────────────────────────────────────────────────
  let currentSegment: Segment | null = null;
  if (captions) {
    currentSegment =
      captions.segments.find(
        (seg) => currentTime >= seg.start && currentTime <= seg.end
      ) || null;
  }

  // ── Caption box rect ────────────────────────────────────────────────────────
  // Priority: explicitly passed captionBox > xOffset/yOffset/scale legacy > defaults
  const defaultTop = getStyleTop(style);

  const box: CaptionBox = customStyles?.captionBox ?? (() => {
    const s = customStyles?.scale ?? 1.0;
    return {
      left: customStyles?.xOffset ?? DEFAULT_BOX_L,
      top:  customStyles?.yOffset ?? defaultTop,
      width:  DEFAULT_BOX_W * s,
      height: DEFAULT_BOX_H * s,
    };
  })();

  // ── Scale factor passed to caption styles ───────────────────────────────────
  const scaleFactor = customStyles?.previewScale ?? (box.width / DEFAULT_BOX_W);

  // ── Clamp helper ────────────────────────────────────────────────────────────
  const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));

  // ── Clamp box to composition ────────────────────────────────────────────────
  const safeBox: CaptionBox = {
    left:   clamp(box.left,   0, COMP_W - MIN_BOX_W),
    top:    clamp(box.top,    0, COMP_H - MIN_BOX_H),
    width:  clamp(box.width,  MIN_BOX_W, COMP_W - clamp(box.left, 0, COMP_W - MIN_BOX_W)),
    height: clamp(box.height, MIN_BOX_H, COMP_H - clamp(box.top,  0, COMP_H - MIN_BOX_H)),
  };

  // ── Emit box update to App-level state ─────────────────────────────────────
  const emitBox = (b: CaptionBox) => {
    if ((window as any).updateCaptionBox) {
      (window as any).updateCaptionBox(b.left, b.top, b.width, b.height);
    }
  };

  const commitBox = (b: CaptionBox) => {
    if ((window as any).commitCaptionBox) {
      (window as any).commitCaptionBox(b.left, b.top, b.width, b.height);
    }
  };

  // ── Screen-px → composition-px conversion ──────────────────────────────────
  // Remotion scales the 720×1280 composition to fit the container using
  const getRenderScale = (): number => {
    const scaleW = window.innerWidth  / COMP_W;
    const scaleH = window.innerHeight / COMP_H;
    return Math.min(scaleW, scaleH);
  };

  const screenToComp = (px: number): number => px / getRenderScale();

  // ── Drag & Pinch handler ───────────────────────────────────────────────────
  const gestureState = useRef<{
    activePointers: Map<number, { x: number; y: number }>;
    mode: 'none' | 'drag' | 'pinch';
    initialSafeBox: CaptionBox;
    dragStartX: number;
    dragStartY: number;
    pinchStartDist: number;
    currentBox: CaptionBox;
  }>({
    activePointers: new Map(),
    mode: 'none',
    initialSafeBox: safeBox,
    dragStartX: 0,
    dragStartY: 0,
    pinchStartDist: 0,
    currentBox: safeBox,
  });

  const getPinchDistance = (pointers: Map<number, { x: number; y: number }>) => {
    const pts = Array.from(pointers.values());
    if (pts.length < 2) return 0;
    return Math.hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y);
  };

  const onPointerDown = (e: React.PointerEvent) => {
    if (!showBoundingBox) return;
    
    e.stopPropagation();
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);

    const state = gestureState.current;
    state.activePointers.set(e.pointerId, { x: e.clientX, y: e.clientY });

    if (state.mode !== 'none') {
      emitBox(state.currentBox);
      commitBox(state.currentBox);
      state.initialSafeBox = { ...state.currentBox };
    } else {
      state.initialSafeBox = { ...safeBox };
      state.currentBox = { ...safeBox };
    }

    if (state.activePointers.size === 1) {
      state.mode = 'drag';
      state.dragStartX = e.clientX;
      state.dragStartY = e.clientY;
    } else if (state.activePointers.size >= 2) {
      state.mode = 'pinch';
      state.pinchStartDist = getPinchDistance(state.activePointers);
    }
  };

  const onWheel = (e: React.WheelEvent) => {
    if (!showBoundingBox) return;
    e.preventDefault();
    
    const scaleDelta = e.deltaY > 0 ? 0.95 : 1.05; // 5% zoom per scroll notch
    const state = gestureState.current;
    
    const aspect = DEFAULT_BOX_H / DEFAULT_BOX_W;
    const newW = state.currentBox.width * scaleDelta;
    const newH = newW * aspect;
    
    // Zoom relative to the center of the current box
    const cx = state.currentBox.left + state.currentBox.width / 2;
    const cy = state.currentBox.top + state.currentBox.height / 2;
    const newL = cx - newW / 2;
    const newT = cy - newH / 2;

    state.currentBox = { left: newL, top: newT, width: newW, height: newH };
    state.initialSafeBox = { ...state.currentBox };
    emitBox(state.currentBox);
    commitBox(state.currentBox);
  };

  const onPointerMove = (e: React.PointerEvent) => {
    const state = gestureState.current;
    if (!state.activePointers.has(e.pointerId)) return;
    
    e.stopPropagation();
    e.preventDefault();
    state.activePointers.set(e.pointerId, { x: e.clientX, y: e.clientY });

    if (state.mode === 'drag' && state.activePointers.size === 1) {
      const dx = screenToComp(e.clientX - state.dragStartX);
      const dy = screenToComp(e.clientY - state.dragStartY);
      
      const newL = state.initialSafeBox.left + dx;
      const newT = state.initialSafeBox.top + dy;
      
      state.currentBox = { ...state.initialSafeBox, left: newL, top: newT };
      emitBox(state.currentBox);
    } else if (state.mode === 'pinch' && state.activePointers.size >= 2) {
      const dist = getPinchDistance(state.activePointers);
      if (state.pinchStartDist > 0) {
        const scale = dist / state.pinchStartDist;
        const aspect = DEFAULT_BOX_H / DEFAULT_BOX_W;
        
        // Remove max limit for zoom
        const newW = Math.max(10, state.initialSafeBox.width * scale);
        const newH = newW * aspect;
        
        const cx = state.initialSafeBox.left + state.initialSafeBox.width / 2;
        const cy = state.initialSafeBox.top + state.initialSafeBox.height / 2;
        
        // Allow the box to expand out of the frame as well
        const newL = cx - newW / 2;
        const newT = cy - newH / 2;

        state.currentBox = { left: newL, top: newT, width: newW, height: newH };
        emitBox(state.currentBox);
      }
    }
  };

  const onPointerUp = (e: React.PointerEvent) => {
    const state = gestureState.current;
    if (!state.activePointers.has(e.pointerId)) return;

    e.stopPropagation();
    e.preventDefault();
    e.currentTarget.releasePointerCapture(e.pointerId);
    state.activePointers.delete(e.pointerId);

    if (state.activePointers.size === 0) {
      state.mode = 'none';
      emitBox(state.currentBox);
      commitBox(state.currentBox);
    } else if (state.activePointers.size === 1) {
      state.mode = 'drag';
      state.initialSafeBox = { ...state.currentBox };
      
      const ptr = Array.from(state.activePointers.values())[0];
      state.dragStartX = ptr.x;
      state.dragStartY = ptr.y;
      
      if (boxRef.current) {
        boxRef.current.style.transform = '';
        boxRef.current.style.transformOrigin = 'center';
      }
      emitBox(state.currentBox);
      commitBox(state.currentBox);
    }
  };

  // (Resize handler removed in favor of pinch-to-zoom)

  // ── Styles with scale factor injected ──────────────────────────────────────
  const scaledStyles = { ...customStyles, scaleFactor, boxWidth: safeBox.width };

  // ── Caption content (for styles that use AbsoluteFill internally) ───────────
  // MedusaStyle and BuzzStyle render their own AbsoluteFill. We wrap them in a
  // clipped container sized to the box and scale the inner 720×1280 content.
  const isFullCompStyle = style === 'medusa-style' || style === 'buzz-style';

  return (
    <AbsoluteFill style={{ backgroundColor: 'black' }}>
      {/* CSS resets for video element */}
      <style>{`
        video { background: transparent !important; }
        video::-webkit-media-controls { display: none !important; }
        video::-webkit-media-controls-start-playback-button { display: none !important; -webkit-appearance: none; }
        video::-webkit-media-controls-overlay-play-button { display: none !important; -webkit-appearance: none; }
        video::before, video::after { display: none !important; }
        ::-webkit-media-controls-play-button { display: none !important; }
      `}</style>

      {/* ── Video layer ─────────────────────────────────────────────────────── */}
      {!hideVideo && (
        isExport ? (
          <OffthreadVideo
            src={staticFile('video.mp4')}
            style={{ width: '100%', height: '100%', objectFit: 'contain', backgroundColor: 'black', filter: videoFilter }}
          />
        ) : (
          <div style={{ width: '100%', height: '100%', filter: videoFilter }}>
            <Video
              src={staticFile('video.mp4')}
              style={{ width: '100%', height: '100%', objectFit: 'contain', backgroundColor: 'black' }}
            />
          </div>
        )
      )}
      {hideVideo && firstFrame && (
        <Img
          src={firstFrame}
          style={{ width: '100%', height: '100%', objectFit: 'contain', backgroundColor: 'black', filter: videoFilter }}
        />
      )}
      
      {/* ── First frame poster overlay (when not playing and at frame 0) ─── */}
      {(!isPlaying && frame === 0 && firstFrame) && (
        <div style={{
          position: 'absolute',
          inset: 0,
          backgroundImage: `url(${firstFrame})`,
          backgroundSize: 'contain',
          backgroundPosition: 'center',
          backgroundRepeat: 'no-repeat',
          pointerEvents: 'none',
          filter: videoFilter,
        }} />
      )}

      {/* ── Caption box ─────────────────────────────────────────────────────── */}
      <div
        ref={boxRef}
        style={{
          position: 'absolute',
          left: safeBox.left,
          top: safeBox.top,
          width: safeBox.width,
          height: safeBox.height,
          boxSizing: 'border-box',
          border: 'none',
          borderRadius: 0,
          backgroundColor: 'transparent',
          cursor: showBoundingBox ? 'move' : 'default',
          // Captions must be clickable in edit mode
          pointerEvents: showBoundingBox ? 'auto' : 'none',
          touchAction: 'none',
        }}
      >
        {/* ── Inner caption renderer ────────────────────────────────────────── */}
        {(!isPlaying && frame === 0) ? null : isFullCompStyle ? (
          // MedusaStyle / BuzzStyle internally use AbsoluteFill at full 720×1280
          // We scale their output to fit inside the box.
          <div style={{
            position: 'absolute',
            left: 0, top: 0,
            width: COMP_W,
            height: COMP_H,
            transformOrigin: 'top left',
            transform: `scale(${scaleFactor})`,
            pointerEvents: 'none',
          }}>
            {style === 'medusa-style' && <MedusaStyle captions={captions} customStyles={scaledStyles} />}
            {style === 'buzz-style'   && <BuzzStyle   captions={captions} customStyles={scaledStyles} />}
          </div>
        ) : (
          // Simple styles: render directly inside the box.
          // Their `position:absolute; bottom:X%` is now relative to the box height.
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            {style === 'hormozi-style'  && <HormoziStyle     segment={currentSegment} customStyles={scaledStyles} />}
            {style === 'ali-abdaal'     && <AliAbdaalStyle   segment={currentSegment} customStyles={scaledStyles} />}
            {style === 'mr-beast'       && <MrBeastStyle     segment={currentSegment} customStyles={scaledStyles} />}
            {style === 'karaoke-flow'   && <KaraokeFlow       segment={currentSegment} customStyles={scaledStyles} />}
            {style === 'pulse-wave'     && <PulseWave         segment={currentSegment} customStyles={scaledStyles} />}
            {style === 'typewriter-pro' && <TypewriterPro     segment={currentSegment} customStyles={scaledStyles} />}
            {style === 'neon-glow'      && <NeonGlowStyle     segment={currentSegment} customStyles={scaledStyles} />}
            {style === 'impact-bounce'  && <ImpactBounceStyle segment={currentSegment} customStyles={scaledStyles} />}
            {style === 'minimalist-bg'  && <MinimalistBgStyle segment={currentSegment} customStyles={scaledStyles} />}
          </div>
        )}

        {/* ── Edit-mode overlay ─────────────────────────────────────────────── */}
        {/* Visual bounding box overlay and resize handles removed in favor of pinch-to-zoom and invisible drag area */}
      </div>

      {/* ── Full screen gesture overlay (Transform mode only) ─────────────── */}
      {showBoundingBox && (
        <div
          style={{
            position: 'absolute',
            left: 0, right: 0, top: 0, bottom: 0,
            zIndex: 9999,
            cursor: 'move',
            touchAction: 'none'
          }}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
          onWheel={onWheel}
        />
      )}
    </AbsoluteFill>
  );
};
