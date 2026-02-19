/**
 * Handles notification commands from the gateway.
 * Displays system notifications on the HarmonyOS device.
 * Clicking a notification brings the user back to the app's chat page.
 */
import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, Want } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { LogService } from '../../common/LogService';

const TAG = 'NotifCap';

/** Info about a received notification, for displaying in chat */
export interface NotificationInfo {
  title: string;
  body: string;
  sender: string;    // who triggered the notification (channel/user)
  notifId: number;
}

export class NotificationCapability {
  private nextNotifId: number = 1000;
  private log: LogService = LogService.getInstance();
  private permissionChecked: boolean = false;
  private permissionGranted: boolean = false;
  private cachedWantAgent: object | undefined = undefined;
  private bundleName: string = '';
  private abilityName: string = 'EntryAbility';
  private smallIconPixel: image.PixelMap | undefined = undefined;

  /** Callback: invoked after a notification is published, so chat can show it */
  onNotificationPublished: ((info: NotificationInfo) => void) | undefined = undefined;

  /** Set bundle name for WantAgent (call once from NodeRuntime with context info) */
  setBundleName(name: string): void {
    this.bundleName = name;
    this.log.info(TAG, `bundleName set to: ${name}`);
  }

  /** Set the small icon PixelMap for status bar display */
  setSmallIcon(pixelMap: image.PixelMap): void {
    this.smallIconPixel = pixelMap;
    this.log.info(TAG, 'Small icon set successfully');
  }

  async execute(paramsJson: string | undefined): Promise<string> {
    this.log.info(TAG, `execute: params=${paramsJson ?? 'none'}`);

    // Ensure notification permission is granted
    if (!this.permissionGranted) {
      await this.ensurePermission();
    }
    if (!this.permissionGranted) {
      this.log.system(TAG, 'Notification permission not granted');
      return '{"ok":false,"error":"NOTIFICATION_PERMISSION_DENIED","message":"Notification permission not granted"}';
    }

    let title = 'OpenClaw';
    let body = '';
    let sender = '';
    if (paramsJson && paramsJson.length > 0) {
      try {
        let p = JSON.parse(paramsJson) as Record<string, string>;
        if (p['title']) {
          title = p['title'];
        }
        if (p['body']) {
          body = p['body'];
        } else if (p['content']) {
          body = p['content'];
        } else if (p['message']) {
          body = p['message'];
        }
        // Extract sender info from params
        if (p['from']) {
          sender = p['from'];
        } else if (p['sender']) {
          sender = p['sender'];
        } else if (p['channel']) {
          sender = p['channel'];
        } else if (p['source']) {
          sender = p['source'];
        }
      } catch {
        this.log.warn(TAG, 'Failed to parse notification params');
      }
    }

    let notifId = this.nextNotifId++;
    this.log.info(TAG, `Publishing notification #${notifId}: title="${title}" body="${body.substring(0, 50)}${body.length > 50 ? '...' : ''}" sender="${sender}"`);

    // Build WantAgent so clicking the notification opens the app
    let agent: object | undefined = undefined;
    try {
      agent = await this.getOrCreateWantAgent();
    } catch (err) {
      this.log.warn(TAG, `Failed to create WantAgent: ${(err as Error).message ?? ''}`);
    }

    let request: notificationManager.NotificationRequest = {
      id: notifId,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: body,
        },
      },
      isFloatingIcon: true,
    };

    // Attach WantAgent if available
    if (agent !== undefined) {
      request.wantAgent = agent;
    }

    // Attach small icon if available
    if (this.smallIconPixel !== undefined) {
      request.smallIcon = this.smallIconPixel;
    }

    await notificationManager.publish(request);
    this.log.info(TAG, `Notification #${notifId} published successfully (wantAgent=${agent !== undefined} icon=${this.smallIconPixel !== undefined})`);

    // Dispatch to chat display callback
    if (this.onNotificationPublished) {
      let info: NotificationInfo = {
        title: title,
        body: body,
        sender: sender,
        notifId: notifId,
      };
      try {
        this.onNotificationPublished(info);
      } catch {
        // ignore
      }
    }

    return `{"ok":true,"notificationId":${notifId}}`;
  }

  /**
   * Pre-request notification permission so it's ready when gateway invokes.
   * Called from NodeRuntime.connect() — fire-and-forget.
   */
  requestPermissionEarly(): void {
    this.ensurePermission().then(() => {
      this.log.info(TAG, `requestPermissionEarly done: granted=${this.permissionGranted}`);
    }).catch(() => {
      this.log.warn(TAG, 'requestPermissionEarly failed (ignored)');
    });
  }

  /** Get or create a cached WantAgent that opens EntryAbility */
  private async getOrCreateWantAgent(): Promise<object | undefined> {
    if (this.cachedWantAgent !== undefined) {
      return this.cachedWantAgent;
    }

    if (this.bundleName.length === 0) {
      this.log.warn(TAG, 'bundleName not set, cannot create WantAgent');
      return undefined;
    }

    let want: Want = {
      bundleName: this.bundleName,
      abilityName: this.abilityName,
    };

    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };

    this.log.info(TAG, `Creating WantAgent: bundle=${this.bundleName} ability=${this.abilityName}`);
    this.cachedWantAgent = await wantAgent.getWantAgent(wantAgentInfo);
    this.log.info(TAG, 'WantAgent created successfully');
    return this.cachedWantAgent;
  }

  private async ensurePermission(): Promise<void> {
    try {
      // Check if already enabled
      let enabled = await notificationManager.isNotificationEnabled();
      this.log.info(TAG, `Notification enabled: ${enabled}`);
      if (enabled) {
        this.permissionGranted = true;
        this.permissionChecked = true;
        return;
      }

      // Request permission from user (shows system dialog)
      if (!this.permissionChecked) {
        this.log.info(TAG, 'Requesting notification permission...');
        try {
          await notificationManager.requestEnableNotification();
          this.permissionGranted = true;
          this.log.info(TAG, 'Notification permission granted by user');
        } catch (err) {
          let code = (err as Record<string, number>)['code'] ?? 0;
          if (code === 1600004) {
            // 1600004 = already granted, just wasn't showing in isNotificationEnabled
            this.permissionGranted = true;
            this.log.info(TAG, 'Notification permission already granted (code 1600004)');
          } else {
            this.log.system(TAG, `Notification permission denied: code=${code} msg=${(err as Error).message ?? ''}`);
            this.permissionGranted = false;
          }
        }
        this.permissionChecked = true;
      }
    } catch (err) {
      this.log.error(TAG, `Failed to check notification permission: ${(err as Error).message ?? ''}`);
      // Try anyway — some devices allow without explicit check
      this.permissionGranted = true;
      this.permissionChecked = true;
    }
  }
}
