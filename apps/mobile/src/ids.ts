/** UUIDs for locally created records. Falls back to Math.random where `crypto.randomUUID` is missing. */
export function uuid(): string {
  const cryptoObject = (globalThis as { crypto?: { randomUUID?: () => string } }).crypto;
  if (cryptoObject?.randomUUID) return cryptoObject.randomUUID();
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (character) => {
    const value = Math.floor(Math.random() * 16);
    const nibble = character === "x" ? value : (value & 0x3) | 0x8;
    return nibble.toString(16);
  });
}
