import { describe, expect, it } from 'vitest';
import { EventBuffer } from '../event-buffer.js';

describe('EventBuffer', () => {
  it('assigns monotonically increasing IDs', () => {
    const b = new EventBuffer(10);
    expect(b.push('a', {}).id).toBe(1);
    expect(b.push('b', {}).id).toBe(2);
    expect(b.push('c', {}).id).toBe(3);
  });

  it('drops oldest when full', () => {
    const b = new EventBuffer(3);
    b.push('a', {}); // id=1
    b.push('b', {}); // id=2
    b.push('c', {}); // id=3
    b.push('d', {}); // id=4, drops id=1
    expect(b.oldestId).toBe(2);
    expect(b.newestId).toBe(4);
  });

  it('since(0) returns all events', () => {
    const b = new EventBuffer(10);
    b.push('a', { x: 1 });
    b.push('b', { x: 2 });
    expect(b.since(0)?.length).toBe(2);
  });

  it('since(newestId) returns empty', () => {
    const b = new EventBuffer(10);
    b.push('a', {});
    b.push('b', {});
    expect(b.since(2)).toEqual([]);
  });

  it('since(lastId older than oldest) returns null (gap)', () => {
    const b = new EventBuffer(3);
    b.push('a', {}); b.push('b', {}); b.push('c', {}); b.push('d', {});
    // oldest is id=2, requesting since(0) means we need id=1 which is gone
    expect(b.since(0)).toBeNull();
  });

  it('empty buffer: oldestId null, newestId 0', () => {
    const b = new EventBuffer(10);
    expect(b.oldestId).toBeNull();
    expect(b.newestId).toBe(0);
  });
});
