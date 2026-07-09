import { bundle } from '@remotion/bundler';
import { renderMedia, selectComposition } from '@remotion/renderer';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const styles = [
  'hormozi-style',
  'ali-abdaal',
  'mr-beast',
  'karaoke-flow',
  'pulse-wave',
  'typewriter-pro',
  'neon-glow',
  'impact-bounce',
  'minimalist-bg'
];

const sampleCaptions = {
  segments: [
    {
      start: 0.0,
      end: 2.0,
      text: "Sample animation text",
      words: [
        { word: "Sample", start: 0.0, end: 0.5 },
        { word: "", start: 0.5, end: 0.5 },
        { word: "animation", start: 0.5, end: 1.2 },
        { word: "text", start: 1.2, end: 2.0 }
      ]
    }
  ]
};

async function main() {
  const outputDir = path.join(__dirname, '../caption_renderer_poc/assets/gifs');
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  console.log('Bundling Remotion project...');
  const bundled = await bundle({
    entryPoint: path.resolve(__dirname, 'src/index.ts'),
    webpackOverride: (config) => config,
  });

  for (const style of styles) {
    const outputFile = path.join(outputDir, `${style}.gif`);
    console.log(`\nRendering ${style} to ${outputFile}...`);

    const inputProps = {
      style: style,
      captions: sampleCaptions,
      customStyles: {
        wordsPerLine: 2,
        maxLinesPerFrame: 3,
        scale: 1.0, 
        previewScale: 1.5, // Force large text
        captionBox: {
          left: 720 * 0.05,
          top: 720 * 0.30, // Centered vertically in 720x720 square
          width: 720 * 0.9,
          height: 720 * 0.4
        }
      },
      hideVideo: true
    };

    const composition = await selectComposition({
      serveUrl: bundled,
      id: 'CaptionComposition',
      inputProps,
    });

    composition.height = 720; // Override to render a square GIF
    
    // We only need 2 seconds (assuming 30fps = 60 frames)
    const frames = 60; 

    await renderMedia({
      composition,
      serveUrl: bundled,
      codec: 'gif',
      outputLocation: outputFile,
      inputProps,
      frameRange: [0, frames - 1],
      imageFormat: 'jpeg', // Doesn't matter for gif, but good to have
      chromiumOptions: {
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
      },
      onProgress: ({ progress }) => {
        process.stdout.write(`\rRendering... ${Math.round(progress * 100)}%`);
      },
    });
    console.log(`\nDone rendering ${style}`);
  }
}

main().catch(console.error);
