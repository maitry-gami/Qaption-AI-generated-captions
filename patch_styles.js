const fs = require('fs');
const path = require('path');

const dir = 'd:/CAPTION AI APP/test-webview/renderer/src/styles';
const files = [
  'HormoziStyle.tsx',
  'AliAbdaalStyle.tsx',
  'MrBeastStyle.tsx',
  'NeonGlowStyle.tsx',
  'MinimalistBgStyle.tsx',
  'KaraokeFlow.tsx',
  'ImpactBounceStyle.tsx',
  'PulseWave.tsx',
  'TypewriterPro.tsx'
];

files.forEach(file => {
  const filepath = path.join(dir, file);
  let content = fs.readFileSync(filepath, 'utf8');

  // Add import
  if (!content.includes('getAutoFitScale')) {
    content = content.replace(/import \{ getPreciseRows \} from '\.\/captionUtils';/, "import { getPreciseRows, getAutoFitScale } from './captionUtils';");
  }

  // Change const sf to let sf
  content = content.replace(/const sf = customStyles\?\.scaleFactor \?\? 1;/, "let sf = customStyles?.scaleFactor ?? 1;");

  // Insert autoFit logic after visibleRows
  const visibleRowsLine = "const visibleRows = getPreciseRows(segment, currentTime, wordsPerLine, maxLinesPerFrame);";
  
  const insertLogic = `
  const boxWidth = customStyles?.boxWidth ?? 648;
  const autoFitScale = getAutoFitScale(visibleRows, 16 * sf, boxWidth);
  sf *= autoFitScale;
  `;

  if (!content.includes('autoFitScale')) {
    content = content.replace(visibleRowsLine, visibleRowsLine + insertLogic);
  }

  fs.writeFileSync(filepath, content);
});
console.log('Done');
