const BYTES_PER_UNIT: number = 1024;
const UNITS: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];

export function formatSize(bytes: number): string {
  if (bytes < 0 || !Number.isFinite(bytes)) {
    return '';
  }
  let value: number = bytes;
  let unit: number = 0;
  while (value >= BYTES_PER_UNIT && unit < UNITS.length - 1) {
    value = value / BYTES_PER_UNIT;
    unit++;
  }
  if (unit === 0) {
    return `${value} ${UNITS[unit]}`;
  }
  let rounded: number = Number(value.toFixed(1));
  if (rounded >= BYTES_PER_UNIT && unit < UNITS.length - 1) {
    rounded = Number((value / BYTES_PER_UNIT).toFixed(1));
    unit++;
  }
  return `${rounded.toFixed(1)} ${UNITS[unit]}`;
}
