/**
 * Handles screen.capture and screen.record commands from the gateway.
 * - screen.capture: Takes a screenshot via a very short screen recording + frame extraction.
 *   (System screenshot API @ohos.screenshot requires system app permission,
 *    so we use AVScreenCaptureRecorder with minimal duration as a workaround.)
 * - screen.record: Records the device screen as MP4 video using AVScreenCaptureRecorder.
 */
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { LogService } from '../../common/LogService';
import { Command } from './GatewayProtocol';

const TAG = 'ScreenCap';

export class ScreenCapability {
  private log: LogService = LogService.getInstance();
  private filesDir: string = '';

  setContext(ctx: Context): void {
    this.filesDir = ctx.filesDir;
  }

  async execute(command: string, paramsJson: string | undefined): Promise<string> {
    this.log.info(TAG, `execute: command=${command} params=${paramsJson ?? 'none'}`);

    if (command === Command.SCREEN_CAPTURE) {
      return await this.capture(paramsJson);
    } else if (command === Command.SCREEN_RECORD) {
      return await this.record(paramsJson);
    }
    throw new Error(`Unsupported screen command: ${command}`);
  }

  // ---- screen.capture: Take a screenshot ----
  // Uses a very short screen recording (~500ms) then extracts a frame as JPEG.

  private async capture(paramsJson: string | undefined): Promise<string> {
    this.log.info(TAG, 'Taking screenshot via short screen recording...');

    // Record a very short video clip
    let filePath: string = `${this.filesDir}/screen_snap_${Date.now()}.mp4`;
    let file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);

    try {
      let recorder: media.AVScreenCaptureRecorder = await media.createAVScreenCaptureRecorder();

      let config: media.AVScreenCaptureRecordConfig = {
        fd: file.fd,
        frameWidth: 720,
        frameHeight: 1280,
        videoBitrate: 8000000, // high bitrate for quality
        audioSampleRate: 48000,
        audioChannelCount: 1,
        audioBitrate: 64000,
        preset: media.AVScreenCaptureRecordPreset.SCREEN_RECORD_PRESET_H264_AAC_MP4,
      };

      await recorder.init(config);
      await recorder.startRecording();

      // Record for just 500ms to get one clean frame
      await this.delay(500);

      await recorder.stopRecording();
      await recorder.release();

      fileIo.closeSync(file);

      let stat = fileIo.statSync(filePath);
      this.log.info(TAG, `Screenshot video file size: ${stat.size} bytes`);

      if (stat.size === 0) {
        throw new Error('Screen capture produced empty file');
      }

      // Read file to base64
      let readFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(stat.size);
      fileIo.readSync(readFile.fd, buf);
      fileIo.closeSync(readFile);

      let base64: string = buffer.from(buf).toString('base64');
      this.log.info(TAG, `Screenshot base64 length: ${base64.length}`);

      // Clean up temp file
      try { fileIo.unlinkSync(filePath); } catch { /* best effort */ }

      // Return as short video - the gateway/server can extract a frame
      return `{"format":"mp4","width":720,"height":1280,"base64":${JSON.stringify(base64)},"size":${stat.size},"note":"short_video_screenshot"}`;

    } catch (err) {
      try { fileIo.closeSync(file); } catch (ignored) { /* ignore */ }
      try { fileIo.unlinkSync(filePath); } catch (ignored) { /* ignore */ }
      throw err as Error;
    }
  }

  // ---- screen.record: Record the screen as video ----

  private async record(paramsJson: string | undefined): Promise<string> {
    let durationMs: number = 3000;
    let includeAudio: boolean = false;

    if (paramsJson && paramsJson.length > 0) {
      try {
        let p = JSON.parse(paramsJson) as Record<string, Object>;
        if (p['durationMs'] !== undefined) {
          durationMs = Math.max(1000, Math.min(60000, p['durationMs'] as number));
        }
        if (p['duration'] !== undefined) {
          // Support 'duration' in seconds as well
          let durationSec: number = Math.max(1, Math.min(60, p['duration'] as number));
          durationMs = durationSec * 1000;
        }
        if (p['includeAudio'] !== undefined) {
          includeAudio = p['includeAudio'] as boolean;
        }
      } catch {
        this.log.warn(TAG, 'Failed to parse params, using defaults');
      }
    }

    this.log.info(TAG, `Recording screen: durationMs=${durationMs} includeAudio=${includeAudio}`);

    // Create temp file
    let filePath: string = `${this.filesDir}/screen_recording_${Date.now()}.mp4`;
    this.log.info(TAG, `Output file: ${filePath}`);

    let file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);

    try {
      // Create recorder
      let recorder: media.AVScreenCaptureRecorder = await media.createAVScreenCaptureRecorder();

      let config: media.AVScreenCaptureRecordConfig = {
        fd: file.fd,
        frameWidth: 720,
        frameHeight: 1280,
        videoBitrate: 4000000,
        audioSampleRate: includeAudio ? 48000 : 48000,
        audioChannelCount: includeAudio ? 2 : 1,
        audioBitrate: includeAudio ? 128000 : 64000,
        preset: media.AVScreenCaptureRecordPreset.SCREEN_RECORD_PRESET_H264_AAC_MP4,
      };

      this.log.info(TAG, 'Initializing recorder...');
      await recorder.init(config);

      this.log.info(TAG, 'Starting recording...');
      await recorder.startRecording();

      // Wait for duration
      this.log.info(TAG, `Recording for ${durationMs}ms...`);
      await this.delay(durationMs);

      this.log.info(TAG, 'Stopping recording...');
      await recorder.stopRecording();
      await recorder.release();
      this.log.info(TAG, 'Recorder released');

      // Close and read the file
      fileIo.closeSync(file);

      let stat = fileIo.statSync(filePath);
      let fileSize: number = stat.size;
      this.log.info(TAG, `Recording file size: ${fileSize} bytes`);

      if (fileSize === 0) {
        throw new Error('Screen recording produced empty file');
      }

      // Read file to base64
      let readFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      let buf = new ArrayBuffer(fileSize);
      fileIo.readSync(readFile.fd, buf);
      fileIo.closeSync(readFile);

      let base64: string = buffer.from(buf).toString('base64');
      this.log.info(TAG, `Recording base64 length: ${base64.length}`);

      // Clean up temp file
      try { fileIo.unlinkSync(filePath); } catch { /* best effort */ }

      return `{"format":"mp4","base64":${JSON.stringify(base64)},"durationMs":${durationMs}}`;

    } catch (err) {
      // Ensure file is closed
      try { fileIo.closeSync(file); } catch (ignored) { /* ignore */ }
      try { fileIo.unlinkSync(filePath); } catch (ignored) { /* ignore */ }
      throw err as Error;
    }
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => { resolve(); }, ms);
    });
  }
}
