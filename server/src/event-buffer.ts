export interface BufferedEvent {
  id: number;
  type: string;
  data: unknown;
}

export class EventBuffer {
  private events: BufferedEvent[] = [];
  private nextId = 1;
  private readonly maxSize: number;

  constructor(maxSize = 1000) {
    this.maxSize = maxSize;
  }

  push(type: string, data: unknown): BufferedEvent {
    const event: BufferedEvent = { id: this.nextId++, type, data };
    this.events.push(event);
    if (this.events.length > this.maxSize) {
      this.events.shift();
    }
    return event;
  }

  /**
   * Returns events with id > lastId.
   * Returns null if lastId is older than our oldest buffered event (gap).
   * Returns [] if lastId === newestId or buffer empty.
   */
  since(lastId: number): BufferedEvent[] | null {
    if (this.events.length === 0) return [];
    const oldest = this.events[0]!.id;
    if (lastId + 1 < oldest) return null;
    return this.events.filter((e) => e.id > lastId);
  }

  get oldestId(): number | null {
    return this.events.length > 0 ? this.events[0]!.id : null;
  }

  get newestId(): number {
    return this.nextId - 1;
  }
}
