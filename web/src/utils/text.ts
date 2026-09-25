// plural(1, 'case') → "1 case"; plural(3, 'case') → "3 cases". English regular plurals only.
export function plural(count: number, noun: string): string {
  return `${count} ${noun}${count === 1 ? '' : 's'}`
}

// "manual_adjustment" → "Manual adjustment"
export function humanize(value: string): string {
  const text = value.replaceAll('_', ' ')
  return text.charAt(0).toUpperCase() + text.slice(1)
}
