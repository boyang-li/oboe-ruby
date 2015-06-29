# Derivative Works

module TraceView
  module Merb
    # module Helpers
    #   @@rum_xhr_tmpl = File.read(File.dirname(__FILE__) + '/rails/helpers/rum/rum_ajax_header.js.erb')
    #   @@rum_hdr_tmpl = File.read(File.dirname(__FILE__) + '/rails/helpers/rum/rum_header.js.erb')
    #   @@rum_ftr_tmpl = File.read(File.dirname(__FILE__) + '/rails/helpers/rum/rum_footer.js.erb')

    #   def traceview_rum_header
    #     begin
    #       return unless TraceView::Config.rum_id
    #       if TraceView.tracing?
    #         if request.xhr?
    #           return raw(ERB.new(@@rum_xhr_tmpl).result)
    #         else
    #           return raw(ERB.new(@@rum_hdr_tmpl).result)
    #         end
    #       end
    #     rescue StandardError => e
    #       TraceView.logger.warn "traceview_rum_header: #{e.message}."
    #       return ""
    #     end
    #   end
    #   alias_method :oboe_rum_header, :traceview_rum_header

    #   def traceview_rum_footer
    #     begin
    #       return unless TraceView::Config.rum_id
    #       if TraceView.tracing?
    #         # Even though the footer template is named xxxx.erb, there are no ERB tags in it so we'll
    #         # skip that step for now
    #         return raw(@@rum_ftr_tmpl)
    #       end
    #     rescue StandardError => e
    #       TraceView.logger.warn "traceview_rum_footer: #{e.message}."
    #       return ""
    #     end
    #   end
    #   alias_method :oboe_rum_footer, :traceview_rum_footer
    # end # Helpers

    def self.load_initializer
      # The initializer file has to exist in the path bellow
      if File.exists?("#{::Merb.root.to_s}/config/initializers/traceview.rb")
        tr_initializer = "#{::Merb.root.to_s}/config/initializers/traceview.rb"
      end
      require tr_initializer if File.exists?(tr_initializer)
    end

    def self.load_instrumentation
      # Load the Merb specific instrumentation
      pattern = File.join(File.dirname(__FILE__), 'merb/inst', '*.rb')
      Dir.glob(pattern) do |f|
        begin
          require f
        rescue => e
          TraceView.logger.error "[traceview/loading] Error loading merb insrumentation file '#{f}' : #{e}"
        end
      end

      TraceView.logger.info "TraceView gem #{TraceView::Version::STRING} successfully loaded."
    end

    # def self.include_helpers
    #   # TBD: This would make the helpers available to controllers which is occasionally desired.
    #   # ActiveSupport.on_load(:action_controller) do
    #   #   include TraceView::Rails::Helpers
    #   # end
    #   if ::Rails::VERSION::MAJOR > 2
    #     ActiveSupport.on_load(:action_view) do
    #       include TraceView::Rails::Helpers
    #     end
    #   else
    #     ActionView::Base.send :include, TraceView::Rails::Helpers
    #   end
    # end

  end # Merb
end # TraceView

if defined?(::Merb)
  # require the rack middleware on merb initialization after TraceView is initialized

  TraceView.logger = ::Merb.logger if ::Merb.logger

  TraceView::Merb.load_initializer
  TraceView::Loading.load_access_key

  TraceView.logger.info "[traceview/loading] Instrumenting rack" if TraceView::Config[:verbose]

  TraceView::Inst.load_instrumentation
  TraceView::Merb.load_instrumentation
  # TraceView::Rails.include_helpers

  # Report __Init after fork when in Heroku
  TraceView::API.report_init unless TraceView.heroku?
end
