import express from 'express';
import cors from 'cors';
import { bundle } from '@remotion/bundler';
import { renderMedia, selectComposition } from '@remotion/renderer';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';
import multer from 'multer';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
app.use(cors());
app.use(express.json());

// Setup multer to store the uploaded video directly in the public directory
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, path.join(__dirname, 'public'));
  },
  filename: (req, file, cb) => {
    cb(null, 'video.mp4'); // Overwrite the existing video.mp4
  }
});
const upload = multer({ storage });

// Serve the static MP4 file for download
app.use('/output', express.static(path.join(__dirname, 'output')));

app.post('/render', upload.single('video'), async (req, res) => {
  try {
    const style = req.body.style || 'hormozi-style';
    const captionsJson = req.body.captions;
    let customStyles = null;
    if (req.body.customStyles) {
      try {
        customStyles = JSON.parse(req.body.customStyles);
      } catch (e) {
        console.error('Failed to parse custom styles', e);
      }
    }
    let videoAdjustments = null;
    if (req.body.videoAdjustments) {
      try {
        videoAdjustments = JSON.parse(req.body.videoAdjustments);
      } catch (e) {
        console.error('Failed to parse video adjustments', e);
      }
    }
    
    console.log(`Received render request for style: ${style}`);
    
    // Save the new captions to public/captions.json
    if (captionsJson) {
      fs.writeFileSync(path.join(__dirname, 'public/captions.json'), captionsJson, 'utf8');
      console.log('Saved new captions to public/captions.json');
    }

    // Create output directory if it doesn't exist
    const outputDir = path.join(__dirname, 'output');
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir);
    }

    const outputFile = path.join(outputDir, `export-${Date.now()}.mp4`);

    console.log('Bundling Remotion project...');
    const bundled = await bundle({
      entryPoint: path.resolve(__dirname, 'src/index.ts'),
      webpackOverride: (config) => config,
    });

    console.log('Selecting composition...');
    const composition = await selectComposition({
      serveUrl: bundled,
      id: 'CaptionComposition',
      inputProps: {
        style: style,
        captions: JSON.parse(fs.readFileSync(path.join(__dirname, 'public/captions.json'), 'utf8')),
        customStyles: customStyles,
        videoAdjustments: videoAdjustments,
        isExport: true
      },
    });

    // Ensure high quality captions by guaranteeing the output video is at least 1080p
    const longestSide = Math.max(composition.width, composition.height);
    let renderScale = 1;
    if (longestSide > 0 && longestSide < 1920) {
      renderScale = 1920 / longestSide;
      console.log(`Upscaling export by ${renderScale.toFixed(2)}x to ensure high quality captions.`);
    }

    console.log('Rendering media...');
    await renderMedia({
      composition,
      serveUrl: bundled,
      codec: 'h264',
      scale: renderScale,
      outputLocation: outputFile,
      crf: 18,
      pixelFormat: 'yuv420p',
      imageFormat: 'png',
      inputProps: {
        style: style,
        captions: JSON.parse(fs.readFileSync(path.join(__dirname, 'public/captions.json'), 'utf8')),
        customStyles: customStyles,
        videoAdjustments: videoAdjustments,
        isExport: true
      },
      chromiumOptions: {
        args: ['--no-sandbox', '--disable-setuid-sandbox'],
      },
      onProgress: ({ progress }) => {
        console.log(`Rendering... ${Math.round(progress * 100)}%`);
      },
    });

    console.log('Render complete!');
    
    // Return the URL where the Flutter app can download the file
    const fileName = path.basename(outputFile);
    const host = req.get('host');
    const protocol = req.headers['x-forwarded-proto'] || req.protocol;
    res.json({ success: true, url: `${protocol}://${host}/output/${fileName}` });
  } catch (error) {
    console.error('Render failed:', error);
    res.status(500).json({ success: false, error: String(error) });
  }
});

const PORT = process.env.PORT || 8000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Remotion Render Server running on http://0.0.0.0:${PORT}`);
});

