import { randomBytes } from 'node:crypto';
import { settings, persistPairedDevices, type StoredDevice } from './config.js';

const PIN_WINDOW_MS = 5 * 60 * 1000; // 5 minutes
const RATE_LIMIT_MAX_FAILURES = 5;
const RATE_LIMIT_COOLDOWN_MS = 60 * 1000; // 60 seconds

interface PairingWindow {
  pin: string;
  expiresAt: number;
}

interface RateLimitEntry {
  failures: number;
  cooldownUntil: number | null;
}

class PairingManager {
  private window: PairingWindow | null = null;
  private rateLimitMap = new Map<string, RateLimitEntry>();

  /**
   * Open a new pairing window. Generates a 6-digit PIN, valid for 5 minutes.
   * Returns the PIN and its expiry timestamp.
   */
  openWindow(): PairWindowResponse {
    const pin = String(Math.floor(Math.random() * 1_000_000)).padStart(6, '0');
    const expiresAt = Date.now() + PIN_WINDOW_MS;
    this.window = { pin, expiresAt };
    return { pin, expiresAt };
  }

  /**
   * Returns 'open' when a valid pairing window exists, 'closed' otherwise.
   */
  getState(): 'open' | 'closed' {
    if (!this.window) return 'closed';
    if (Date.now() > this.window.expiresAt) {
      this.window = null;
      return 'closed';
    }
    return 'open';
  }

  /**
   * Try to redeem a PIN. On success, creates a deviceToken and persists it.
   */
  async tryRedeemPin(
    pin: string,
    deviceId: string,
    deviceName: string,
    clientIp: string,
  ): Promise<
    | { ok: true; deviceToken: string; serverId: string }
    | { ok: false; error: 'bad_pin' | 'pairing_closed' | 'rate_limited' }
  > {
    // Rate limit check
    const rl = this.getRateLimitEntry(clientIp);
    if (rl.cooldownUntil !== null && Date.now() < rl.cooldownUntil) {
      return { ok: false, error: 'rate_limited' };
    }

    // Window check
    if (this.getState() === 'closed') {
      return { ok: false, error: 'pairing_closed' };
    }

    // PIN check
    if (pin !== this.window!.pin) {
      rl.failures += 1;
      if (rl.failures >= RATE_LIMIT_MAX_FAILURES) {
        rl.cooldownUntil = Date.now() + RATE_LIMIT_COOLDOWN_MS;
        rl.failures = 0;
      }
      return { ok: false, error: 'bad_pin' };
    }

    // Success — close the window and issue a token
    this.window = null;
    this.resetRateLimit(clientIp);

    return this.issueDeviceToken(deviceId, deviceName);
  }

  /**
   * Issue a device token without PIN (QR claim path, already authenticated via adminToken).
   */
  async issueDeviceToken(
    deviceId: string,
    deviceName: string,
  ): Promise<{ ok: true; deviceToken: string; serverId: string }> {
    const deviceToken = 'dt-' + randomBytes(24).toString('hex');
    const now = Date.now();

    // Replace existing device with same deviceId, or push new
    const existingIdx = settings.pairedDevices.findIndex((d) => d.deviceId === deviceId);
    const entry: StoredDevice = {
      deviceId,
      name: deviceName,
      deviceToken,
      pairedAt: now,
      lastSeen: null,
    };

    if (existingIdx >= 0) {
      settings.pairedDevices[existingIdx] = entry;
    } else {
      settings.pairedDevices.push(entry);
    }

    await persistPairedDevices();
    return { ok: true, deviceToken, serverId: settings.serverId };
  }

  /**
   * Revoke a device by deviceId. Returns true if found and removed.
   */
  async revokeDevice(deviceId: string): Promise<boolean> {
    const before = settings.pairedDevices.length;
    settings.pairedDevices = settings.pairedDevices.filter((d) => d.deviceId !== deviceId);
    if (settings.pairedDevices.length === before) return false;
    await persistPairedDevices();
    return true;
  }

  private getRateLimitEntry(ip: string): RateLimitEntry {
    let entry = this.rateLimitMap.get(ip);
    if (!entry) {
      entry = { failures: 0, cooldownUntil: null };
      this.rateLimitMap.set(ip, entry);
    }
    // Reset cooldown if it's expired
    if (entry.cooldownUntil !== null && Date.now() >= entry.cooldownUntil) {
      entry.cooldownUntil = null;
      entry.failures = 0;
    }
    return entry;
  }

  private resetRateLimit(ip: string): void {
    this.rateLimitMap.delete(ip);
  }

  /** For testing: directly set the window */
  _setWindow(window: PairingWindow | null): void {
    this.window = window;
  }

  /** For testing: get current window */
  _getWindow(): PairingWindow | null {
    return this.window;
  }

  /** For testing: get rate limit map */
  _getRateLimitMap(): Map<string, RateLimitEntry> {
    return this.rateLimitMap;
  }
}

// Re-export types for response shapes
export interface PairWindowResponse {
  pin: string;
  expiresAt: number;
}

export const pairingManager = new PairingManager();
