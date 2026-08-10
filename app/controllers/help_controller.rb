class HelpController < ApplicationController
  def show
    base = Rails.root.join("docs", "help")
    path = base.join("#{params[:topic]}.md").expand_path

    unless path.to_s.start_with?("#{base}/") && path.exist?
      head :not_found and return
    end

    html = Rails.cache.fetch("help/#{params[:topic]}/#{path.mtime.to_i}") do
      Redcarpet::Markdown.new(
        Redcarpet::Render::HTML.new,
        autolink: true, tables: true, fenced_code_blocks: true
      ).render(path.read)
    end

    render html: html.html_safe, layout: false
  end
end
