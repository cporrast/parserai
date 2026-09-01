module ApplicationHelper
  STATUS_STYLES = {
    "queued" => "bg-slate-100 text-slate-600 ring-slate-200",
    "fetching" => "bg-sky-50 text-sky-700 ring-sky-200",
    "fetched" => "bg-cyan-50 text-cyan-700 ring-cyan-200",
    "processing" => "bg-violet-50 text-violet-700 ring-violet-200",
    "pending" => "bg-amber-50 text-amber-700 ring-amber-200",
    "completed" => "bg-emerald-50 text-emerald-700 ring-emerald-200",
    "failed" => "bg-rose-50 text-rose-700 ring-rose-200",
    "canceled" => "bg-slate-100 text-slate-500 ring-slate-200",
    "draft" => "bg-indigo-50 text-indigo-700 ring-indigo-200"
  }.freeze

  def status_badge(status)
    classes = STATUS_STYLES.fetch(status.to_s, STATUS_STYLES["queued"])
    tag.span status.to_s.humanize,
      class: "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ring-1 ring-inset #{classes}"
  end

  def pretty_json(value)
    JSON.pretty_generate(value || {})
  rescue JSON::GeneratorError
    value.to_s
  end

  def safe_external_url(value)
    uri = URI.parse(value.to_s)
    %w[http https].include?(uri.scheme) && uri.host.present? ? uri.to_s : nil
  rescue URI::InvalidURIError
    nil
  end

  def task_sort_link(label, column)
    active = @sort == column
    next_direction = active && @direction == "asc" ? "desc" : (column == "updated" ? "desc" : "asc")
    query = request.query_parameters.merge(sort: column, direction: next_direction)
    indicator = active ? (@direction == "asc" ? "↑" : "↓") : "↕"

    link_to tasks_path(query), class: "group inline-flex items-center gap-1.5 hover:text-slate-950" do
      safe_join([ label, tag.span(indicator, class: "text-[10px] #{active ? "text-indigo-600" : "text-slate-300 group-hover:text-slate-500"}") ])
    end
  end

  def icon(name, classes: "size-5")
    paths = {
      plus: '<path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />',
      arrow: '<path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />',
      folder: '<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.06-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18v-5.25a2.25 2.25 0 0 0-2.25-2.25H8.25" />',
      globe: '<path stroke-linecap="round" stroke-linejoin="round" d="M12 21a9 9 0 1 0 0-18m0 18c2.49 0 4.5-4.03 4.5-9S14.49 3 12 3m0 18c-2.49 0-4.5-4.03-4.5-9S9.51 3 12 3M3.6 9h16.8M3.6 15h16.8" />',
      chat: '<path stroke-linecap="round" stroke-linejoin="round" d="M7.5 8.25h9m-9 3h6m-8.25 8.28c.8-.74 1.55-1.5 2.15-2.31A9.72 9.72 0 0 0 12 18.38c5.38 0 9.75-3.91 9.75-8.75S17.38.88 12 .88 2.25 4.79 2.25 9.63c0 2.4 1.08 4.57 2.84 6.15a12.1 12.1 0 0 1-.84 3.75c-.12.28.25.5.5.32l.5-.32Z" />',
      download: '<path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-6L12 15m0 0 4.5-4.5M12 15V3" />',
      database: '<path stroke-linecap="round" stroke-linejoin="round" d="M4.5 6.75C4.5 8.41 7.86 9.75 12 9.75s7.5-1.34 7.5-3-3.36-3-7.5-3-7.5 1.34-7.5 3Zm0 0v10.5c0 1.66 3.36 3 7.5 3s7.5-1.34 7.5-3V6.75M4.5 12c0 1.66 3.36 3 7.5 3s7.5-1.34 7.5-3" />'
    }
    tag.svg(paths.fetch(name).html_safe, class: classes, fill: "none", viewBox: "0 0 24 24", stroke_width: "1.7", stroke: "currentColor", aria_hidden: true)
  end
end
