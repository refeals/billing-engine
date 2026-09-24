# Page-based pagination shared by every list endpoint. Lists answer with the same
# envelope, `{ data: [...], meta: { page, per_page, total_count, total_pages } }`.
module Pagination
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 50

  private

  def paginate(scope, per_page: DEFAULT_PER_PAGE)
    # to_s first: a malformed `page[]=2` arrives as an Array, which has no to_i.
    page = [ params[:page].to_s.to_i, 1 ].max
    total_count = scope.count

    records = scope.limit(per_page).offset((page - 1) * per_page)
    meta = { page: page, per_page: per_page, total_count: total_count, total_pages: (total_count.to_f / per_page).ceil }

    [ records, meta ]
  end
end
