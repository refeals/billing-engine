// Envelope shared by every list endpoint of the API.
export interface PageMeta {
  page: number
  per_page: number
  total_count: number
  total_pages: number
}

export interface Paginated<T, Meta extends PageMeta = PageMeta> {
  data: T[]
  meta: Meta
}
