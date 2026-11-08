/** Dependency-free ZIP (STORE) writer for original photo bytes. */
export type ZipEntry = { name: string; bytes: Uint8Array };
const encoder = new TextEncoder();
const table = new Uint32Array(256);
for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; table[n] = c >>> 0; }
function crc32(bytes: Uint8Array) { let c = 0xffffffff; for (const b of bytes) c = table[(c ^ b) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }
function u16(view: DataView, offset: number, value: number) { view.setUint16(offset, value, true); }
function u32(view: DataView, offset: number, value: number) { view.setUint32(offset, value, true); }
export function createZip(entries: ZipEntry[]): Blob {
  const parts: BlobPart[] = []; const directory: Uint8Array[] = []; let offset = 0;
  for (const entry of entries) {
    const name = encoder.encode(entry.name); const size = entry.bytes.byteLength;
    if (size > 0xffffffff || offset > 0xffffffff) throw new Error("Album too large for a single ZIP. Download in smaller batches.");
    const crc = crc32(entry.bytes);
    const local = new Uint8Array(30 + name.length); const l = new DataView(local.buffer);
    u32(l, 0, 0x04034b50); u16(l, 4, 20); u16(l, 6, 0x800); u16(l, 8, 0); u32(l, 14, crc); u32(l, 18, size); u32(l, 22, size); u16(l, 26, name.length); local.set(name, 30);
    parts.push(local, entry.bytes.slice().buffer); // copy into a Blob-compatible ArrayBuffer
    const central = new Uint8Array(46 + name.length); const d = new DataView(central.buffer);
    u32(d, 0, 0x02014b50); u16(d, 4, 20); u16(d, 6, 20); u16(d, 8, 0x800); u32(d, 16, crc); u32(d, 20, size); u32(d, 24, size); u16(d, 28, name.length); u32(d, 42, offset); central.set(name, 46); directory.push(central);
    offset += local.length + size;
  }
  const directorySize = directory.reduce((sum, item) => sum + item.length, 0);
  if (offset + directorySize > 0xffffffff || entries.length > 65535) throw new Error("Album too large for one ZIP.");
  parts.push(...directory);
  const end = new Uint8Array(22); const e = new DataView(end.buffer); u32(e, 0, 0x06054b50); u16(e, 8, entries.length); u16(e, 10, entries.length); u32(e, 12, directorySize); u32(e, 16, offset); parts.push(end);
  return new Blob(parts, { type: "application/zip" });
}
