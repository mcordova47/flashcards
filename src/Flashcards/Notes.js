// As the server counts it: UTF-8 bytes, not UTF-16 units.
export const byteLength = s => new TextEncoder().encode(s).length
