module Olelo
  module BlockHelper
    def blocks
      @blocks ||= Hash.with_indifferent_access('')
    end

    def define_block(name, content = nil, &block)
      if block_given? || content
        blocks[name] = block_given? ? yield : content
        ''
      else
        blocks[name]
      end
    end

    def footer(content = nil, &block); define_block(:footer, content, &block); end
    def title(content = nil, &block);  define_block(:title,  content, &block); end
  end

  module FlashHelper
    include Util

    def flash
      env['olelo.flash']
    end

    def flash_messages(action = nil)
      if !action || action?(action)
        li = [:error, :warn, :info].map {|level| flash[level].to_a.map {|msg| %{<li class="flash #{level}">#{escape_html msg}</li>} } }.flatten
        "<ul>#{li.join}</ul>".html_safe if !li.empty?
      end
    end
  end

  module PageHelper
    include Util

    def include_page(path)
      page = Page.find(path) rescue nil
      page ? page.content : %{<a href="#{escape_html absolute_path('new'/path)}">#{escape_html :create_page.t(:page => path)}</a>}
    end

    def pagination(path, page_count, page_nr, options = {})
      return if page_count <= 1
      li = []
      li << if page_nr > 1
              %{<a href="#{escape_html absolute_path(path, options.merge(:page => page_nr - 1))}">&#9666;</a>}
            else
              %{<span class="disabled">&#9666;</span>}
            end
      min = page_nr - 3
      max = page_nr + 3
      if min > 1
        min -= max - page_count if max > page_count
      else
        max -= min if min < 1
      end
      max = max + 2 < page_count ? max : page_count
      min = min > 3 ? min : 1
      if min != 1
        li << %{<a href="#{escape_html absolute_path(path, options.merge(:page => 1))}">1</a>} << %{<span class="ellipsis"/>}
      end
      (min..max).each do |i|
        li << if i == page_nr
                %{<span class="current">#{i}</span>}
              else
                %{<a href="#{escape_html absolute_path(path, options.merge(:page => i))}">#{i}</a>}
              end
      end
      if max != page_count
        li << %{<span class="ellipsis"/>} << %{<a href="#{escape_html absolute_path(path, options.merge(:page => page_count))}">#{page_count}</a>}
      end
      li << if page_nr < page_count
              %{<a href="#{escape_html absolute_path(path, options.merge(:page => page_nr + 1))}">&#9656;</a>}
            else
              %{<span class="disabled">&#9656;</span>}
            end
      ('<ul class="pagination">' + li.map {|x| "<li>#{x}</li>"}.join + '</ul>').html_safe
    end

    def date(t)
      %{<span class="date epoch-#{t.to_i}">#{t.strftime('%d %h %Y %H:%M')}</span>}.html_safe
    end

    def format_diff(diff)
      summary   = PatchSummary.new(:links => true)
      formatter = PatchFormatter.new(:links => true, :header => true)
      PatchParser.parse(diff.patch, summary, formatter)
      (summary.html + formatter.html).html_safe
    end

    def breadcrumbs(page)
      path = page.try(:path) || ''
      li = [%{<li class="first breadcrumb#{path.empty? ? ' last' : ''}">
              <a accesskey="z" href="#{escape_html absolute_path('', :version => page)}">#{escape_html :root.t}</a></li>}.unindent]
      path.split('/').inject('') do |parent,elem|
        current = parent/elem
        li << %{<li class="breadcrumb#{current == path ? ' last' : ''}">
                <a href="#{escape_html absolute_path('/' + current, :version => page)}">#{escape_html elem}</a></li>}.unindent
        current
      end
      li.join('<li class="breadcrumb">/</li>').html_safe
    end

    def absolute_path(path, options = {})
      path = Config.base_path / (path.try(:path) || path).to_s

      # Append version string
      version = options.delete(:version)
      # Use version of page
      version = version.tree_version if Page === version
      path = 'version'/version/path if version && (options.delete(:force_version) || !version.head?)

      # Append query parameters
      path += '?' + build_query(options) if !options.empty?

      '/' + path
    end

    def page_path(page, options = {})
      options[:version] ||= page
      absolute_path(page, options)
    end

    def action_path(path, action)
      absolute_path(action.to_s / (path.try(:path) || path).to_s)
    end

    def edit_content(page)
      if params[:content]
        params[:content]
      elsif !(String === page.content) || !valid_xml_chars?(page.content)
	:error_binary.t(:page => page.title, :type => "#{page.mime.comment} (#{page.mime})")
      else
        params[:pos] ? page.content[params[:pos].to_i, params[:len].to_i].to_s : page.content
      end
    end
  end

  module HttpHelper
    include Util

    # Cache control for page
    def cache_control(options)
      return if !Config.production?

      if options[:no_cache]
        response.headers.delete('ETag')
        response.headers.delete('Last-Modified')
        response.headers.delete('Cache-Control')
        return
      end

      last_modified = options.delete(:last_modified)
      modified_since = env['HTTP_IF_MODIFIED_SINCE']
      last_modified = last_modified.try(:to_time) || last_modified
      last_modified = last_modified.try(:httpdate) || last_modified

      if options[:version]
        options[:etag] = options[:version].cache_id
        options[:last_modified] = options[:version].date
      end

      if User.logged_in?
        # Always private mode if user is logged in
        options[:private] = true

        # Special etag for authenticated user
        options[:etag] = "#{User.current.name}-#{options[:etag]}" if options[:etag]
      end

      if options[:etag]
        value = '"%s"' % options.delete(:etag)
        response['ETag'] = value.to_s
        response['Last-Modified'] = last_modified if last_modified
        if etags = env['HTTP_IF_NONE_MATCH']
          etags = etags.split(/\s*,\s*/)
          # Etag is matching and modification date matches (HTTP Spec §14.26)
          halt :not_modified if (etags.include?(value) || etags.include?('*')) && (!last_modified || last_modified == modified_since)
        end
      elsif last_modified
        # If-Modified-Since is only processed if no etag supplied.
        # If the etag match failed the If-Modified-Since has to be ignored (HTTP Spec §14.26)
        response['Last-Modified'] = last_modified
        halt :not_modified if last_modified == modified_since
      end

      options[:public] = !options[:private]
      options[:max_age] ||= 0
      options[:must_revalidate] ||= true if !options.include?(:must_revalidate)

      response['Cache-Control'] = options.map do |k, v|
        if v == true
          k.to_s.tr('_', '-')
        elsif v
          v = 31536000 if v.to_s == 'static'
          "#{k.to_s.tr('_', '-')}=#{v}"
        end
      end.compact.join(', ')
    end
  end

  module ApplicationHelper
    include BlockHelper
    include FlashHelper
    include PageHelper
    include HttpHelper
    include Templates

    def tabs(*actions)
      tabs = actions.map do |action|
        %{<li id="tabhead-#{action}"#{action?(action) ? ' class="selected"' : ''}><a href="#tab-#{action}">#{escape_html action.t}</a></li>}
      end
      %{<ul class="tabs">#{tabs.join}</ul>}.html_safe
    end

    def action?(action)
      if params[:action]
        params[:action].split('-').include?(action.to_s)
      else
        unescape(request.path_info).starts_with?("/#{action}")
      end
    end

    def include_javascript
      @@javascript ||=
        begin
          path = absolute_path("static/script.js?#{File.mtime(File.join(Config.app_path, 'static', 'script.js')).to_i}")
          %{<script src="#{escape_html path}" type="text/javascript" async="async"/>}.html_safe
        end
    end

    def theme_links
      @@theme_links ||=
        begin
          default = File.basename(File.readlink(File.join(Config.themes_path, 'default')))
          Dir.glob(File.join(Config.themes_path, '*', 'style.css')).map do |file|
            name = File.basename(File.dirname(file))
            path = Config.base_path + "static/themes/#{name}/style.css?#{File.mtime(file).to_i}"
            %{<link rel="#{name == default ? '' : 'alternate '}stylesheet"
              href="#{escape_html path}" type="text/css" title="#{escape_html name}"/>}.unindent if name != 'default'
          end.compact.join("\n").html_safe
        end
    end

    def session
      env['rack.session'] ||= {}
    end

    def base_path
      if page && page.root?
        url = request.url_without_path
        url << 'version'/page.tree_version << '/' if !page.head?
        %{<base href="#{escape_html url}"/>}.html_safe
      end
    end

    alias render_partial render

    def render(name, options = {})
      layout = options.delete(:layout) != false && !params[:no_layout]
      output = render_partial(name, options)
      output = render_partial(:layout, options) { output } if layout
      invoke_hook :render, name, output, layout
      output
    end
  end
end
