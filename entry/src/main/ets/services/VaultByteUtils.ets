export function constantTimeBytesEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) { return false; }
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) { difference |= left[index] ^ right[index]; }
  return difference === 0;
}

export function isZeroByteArray(data: Uint8Array): boolean {
  for (let index = 0; index < data.length; index += 1) {
    if (data[index] !== 0) { return false; }
  }
  return true;
}
