// Width of a breakdown bar, in percent. An empty system draws empty bars instead of NaN.
export function shareOf(count: number, total: number): number {
  if (total <= 0) return 0

  return Math.round((count / total) * 1000) / 10
}
