import { Composition, staticFile } from 'remotion';
import { CaptionComposition } from './CaptionComposition';
import { getVideoMetadata } from '@remotion/media-utils';

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="CaptionComposition"
        component={CaptionComposition}
        durationInFrames={800} // fallback
        fps={30}
        width={720}
        height={1280}
        defaultProps={{
          style: 'hormozi-style',
          captions: undefined as any,
        }}
        calculateMetadata={async ({ props }) => {
          let durationInFrames = 800; // default fallback
          let width = 720;
          let height = 1280;
          
          try {
            // Get exact duration and dimensions of the video file itself
            const metadata = await getVideoMetadata(staticFile('video.mp4'));
            durationInFrames = Math.floor(metadata.durationInSeconds * 30);
            width = metadata.width;
            height = metadata.height;
          } catch (err) {
            console.error("Failed to fetch video metadata:", err);
            // Fallback to captions logic if video fetch fails
            const caps = props.captions as any;
            if (caps && caps.segments && caps.segments.length > 0) {
              const lastSegment = caps.segments[caps.segments.length - 1];
              const durationSec = lastSegment.end + 1.0;
              durationInFrames = Math.floor(durationSec * 30);
            }
          }
          
          return {
            durationInFrames,
            width,
            height,
            props,
          };
        }}
      />
    </>
  );
};
