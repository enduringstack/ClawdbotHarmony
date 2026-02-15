import { UIAbility, AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('[ClawdBot] EntryAbility onCreate');
    // Initialize AppStorage keys for share data (must exist before @StorageLink binds)
    AppStorage.setOrCreate<number>('share_timestamp', 0);
    AppStorage.setOrCreate<string>('share_text', '');
    AppStorage.setOrCreate<string>('share_uri', '');
    AppStorage.setOrCreate<string>('share_type', '');
    this.handleShareWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('[ClawdBot] EntryAbility onNewWant');
    this.handleShareWant(want);
  }

  private handleShareWant(want: Want): void {
    if (want.action !== 'ohos.want.action.sendData') {
      return;
    }
    console.info(`[ClawdBot] Share intent received: uri=${want.uri ?? ''} type=${want.type ?? ''}`);

    let shareText = '';
    let shareUri = want.uri ?? '';
    let shareType = 'text'; // default

    // Determine share type from MIME type
    let mimeType = (want.type ?? '').toLowerCase();
    if (mimeType.startsWith('image/') || mimeType.startsWith('image')) {
      shareType = 'image';
    } else if (mimeType.length > 0 && !mimeType.startsWith('text/') && !mimeType.startsWith('text')) {
      shareType = 'file';
    }

    // Extract text from want.parameters
    if (want.parameters) {
      let params = want.parameters;
      // Try common parameter keys for shared text
      let keys: string[] = ['shareText', 'ability.params.stream', 'text', 'content', 'shareContent'];
      for (let key of keys) {
        if (params[key] !== undefined && params[key] !== null) {
          let val = params[key];
          if (typeof val === 'string') {
            shareText = val as string;
            break;
          } else {
            shareText = String(val);
            break;
          }
        }
      }
      // Log all parameter keys for debugging
      let paramKeys = Object.keys(params);
      console.info(`[ClawdBot] Share params keys: [${paramKeys.join(',')}]`);
      if (paramKeys.length > 0 && shareText.length === 0) {
        // Try first string-valued param as fallback
        for (let key of paramKeys) {
          let val = params[key];
          if (typeof val === 'string' && (val as string).length > 0) {
            shareText = val as string;
            console.info(`[ClawdBot] Share text from param key "${key}": ${shareText.substring(0, 100)}`);
            break;
          }
        }
      }
    }

    // If we have a URI but no text, and it's a text type, we'll read the file in ChatPage
    if (shareText.length === 0 && shareUri.length > 0 && shareType === 'text') {
      shareType = 'file'; // treat as file to be read
    }

    console.info(`[ClawdBot] Share data: type=${shareType} textLen=${shareText.length} uri=${shareUri}`);

    // Store in AppStorage for ChatPage to consume
    AppStorage.setOrCreate<string>('share_text', shareText);
    AppStorage.setOrCreate<string>('share_uri', shareUri);
    AppStorage.setOrCreate<string>('share_type', shareType);
    AppStorage.setOrCreate<number>('share_timestamp', Date.now());
  }

  onDestroy(): void {
    console.info('[ClawdBot] EntryAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    console.info('[ClawdBot] onWindowStageCreate');

    windowStage.getMainWindow().then((win: window.Window) => {
      // 1. Disable full-screen layout so system status bar area is reserved automatically.
      //    This prevents content from overlapping with the status bar.
      try {
        win.setWindowLayoutFullScreen(false);
        console.info('[ClawdBot] Window layout set to non-fullscreen');
      } catch (e) {
        console.warn('[ClawdBot] setWindowLayoutFullScreen failed: ' + (e as Error).message);
      }

      // 2. Set keyboard avoid mode to RESIZE (value 1) so the layout shrinks
      //    instead of the entire window shifting up (which causes status bar overlap).
      try {
        // KeyboardAvoidMode: OFFSET=0, RESIZE=1
        win.getUIContext().setKeyboardAvoidMode(1);
        console.info('[ClawdBot] Keyboard avoid mode set to RESIZE');
      } catch (e) {
        console.warn('[ClawdBot] setKeyboardAvoidMode failed: ' + (e as Error).message);
      }
    }).catch((e: Error) => {
      console.warn('[ClawdBot] getMainWindow failed: ' + e.message);
    });

    // Check login state and route accordingly
    this.getInitialPage().then((page: string) => {
      console.info('[ClawdBot] Loading page: ' + page);
      windowStage.loadContent(page, (err) => {
        if (err) {
          console.error('[ClawdBot] loadContent failed: ' + JSON.stringify(err));
          return;
        }
        console.info('[ClawdBot] loadContent succeeded: ' + page);
      });
    }).catch(() => {
      // Fallback to main page on error
      windowStage.loadContent('pages/Index', (err) => {
        if (err) {
          console.error('[ClawdBot] loadContent fallback failed: ' + JSON.stringify(err));
        }
      });
    });
  }

  private async getInitialPage(): Promise<string> {
    console.info('[ClawdBot] Loading Index directly');
    return 'pages/Index';
  }

  onWindowStageDestroy(): void {
    console.info('[ClawdBot] onWindowStageDestroy');
  }

  onForeground(): void {
    console.info('[ClawdBot] onForeground');
  }

  onBackground(): void {
    console.info('[ClawdBot] onBackground');
  }
}
