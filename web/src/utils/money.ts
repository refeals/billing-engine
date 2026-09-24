// Digits with optional thousands separators ("1,049"), then up to two decimals. A comma
// anywhere else ("12,5") is rejected rather than guessed, since it could mean 12.50.
const AMOUNT_PATTERN = /^(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?$/

// Parses what an operator types ("49", "49.9", "$1,049.90") into integer cents by reading
// the digits, never through floating point, so "0.29" is 29 cents and not 28.999….
export function parseMoneyToCents(input: string, { allowNegative = false } = {}): number | null {
  let text = input.trim()
  let sign = 1

  if (allowNegative && text.startsWith('-')) {
    sign = -1
    text = text.slice(1).trim()
  }

  const match = AMOUNT_PATTERN.exec(text.replace(/^\$/, ''))
  if (!match) return null

  const [, whole = '0', fraction = ''] = match
  return sign * (Number(whole.replaceAll(',', '')) * 100 + Number(fraction.padEnd(2, '0')))
}
