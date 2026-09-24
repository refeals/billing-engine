const moneyFormatter = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' })

// Dates are rendered in UTC, the same zone the API stores and computes billing periods in,
// so a period that ends at midnight never shows up as the previous day.
const dateFormatter = new Intl.DateTimeFormat('en-US', {
  year: 'numeric',
  month: 'short',
  day: 'numeric',
  timeZone: 'UTC',
})

const dateTimeFormatter = new Intl.DateTimeFormat('en-US', {
  year: 'numeric',
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  timeZone: 'UTC',
  timeZoneName: 'short',
})

export function formatMoney(cents: number): string {
  return moneyFormatter.format(cents / 100)
}

export function formatDate(iso: string): string {
  return dateFormatter.format(new Date(iso))
}

export function formatDateTime(iso: string): string {
  return dateTimeFormatter.format(new Date(iso))
}
