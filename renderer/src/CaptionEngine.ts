import { useState, useEffect } from 'react';

export interface Word {
  word: string;
  start: number;
  end: number;
}

export interface Segment {
  start: number;
  end: number;
  text: string;
  words: Word[];
}

export interface CaptionData {
  segments: Segment[];
}

export function useCaptionEngine(currentTime: number) {
  const [data, setData] = useState<CaptionData | null>(null);

  useEffect(() => {
    fetch('/captions.json')
      .then((res) => res.json())
      .then((json) => setData(json))
      .catch((err) => console.error('Error fetching captions:', err));
  }, []);

  if (!data) return { currentSegment: null, activeWordIndex: -1 };

  const currentSegment = data.segments.find(
    (seg) => currentTime >= seg.start && currentTime <= seg.end
  ) || null;

  let activeWordIndex = -1;
  if (currentSegment) {
    activeWordIndex = currentSegment.words.findIndex(
      (w) => currentTime >= w.start && currentTime <= w.end
    );
  }

  return { currentSegment, activeWordIndex };
}
