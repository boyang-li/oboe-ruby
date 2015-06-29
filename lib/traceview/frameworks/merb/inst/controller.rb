# Derivative Works

module TraceView
  module Inst
    #
    # MerbBase
    #
    # This module contains the instrumentation code for Merb.
    #
    module MerbBase
      #
      # has_handler?
      #
      # Determins if <tt>exception</tt> has a registered
      # handler via <tt>rescue_from</tt>
      #
      def has_handler?(exception)
        # Don't log exceptions if they have a rescue handler set
        has_handler = false
        rescue_handlers.detect { | klass_name, handler |
          # Rescue handlers can be specified as strings or constant names
          klass = self.class.const_get(klass_name) rescue nil
          klass ||= klass_name.constantize rescue nil
          has_handler = exception.is_a?(klass) if klass
        }
        has_handler
      rescue => e
        TraceView.logger.debug "[traceview/debug] Error searching Merb handlers: #{e.message}"
        return false
      end

      #
      # log_merb_error?
      #
      # Determins whether we should log a raised exception to the
      # TraceView dashboard.  This is determined by whether the exception
      # has a rescue handler setup and the value of
      # TraceView::Config[:report_rescued_errors]
      #
      def log_merb_error?(exception)
        # As it's perculating up through the layers...  make sure that
        # we only report it once.
        return false if exception.instance_variable_get(:@traceview_logged)

        has_handler = has_handler?(exception)

        if !has_handler || (has_handler && TraceView::Config[:report_rescued_errors])
          return true
        end
        false
      end

      #
      # render_with_traceview
      #
      # Our render wrapper that just times and conditionally
      # reports raised exceptions
      #
      def render_with_traceview(*args, &blk)
        TraceView::API.log_entry('actionview')
        render_without_traceview(*args, &blk)

      rescue Exception => e
        TraceView::API.log_exception(nil, e) if log_merb_error?(e)
        raise
      ensure
        TraceView::API.log_exit('actionview')
      end
    end
  end
end

if defined?(Merb::Controller)
  Merb::Controller.class_eval do
    include ::TraceView::Inst::MerbBase

    alias :perform_action_without_traceview :_dispatch
    alias :render_without_traceview :render

    def _dispatch(action)
      report_kvs = {
        :Controller  => self.class.name,
        :Action      => action.to_s
      }
      TraceView::API.log(nil, 'info', report_kvs)
      TraceView::API.log_entry('merb_controller')
      perform_action_without_traceview(action)
    rescue Exception => e
      TraceView::API.log_exception(nil, e) if log_merb_error?(e)
      raise
    ensure
      TraceView::API.log_exit('merb_controller')
    end

    def render(options = nil, extra_options = {}, &block)
      TraceView::API.log_entry('merb_view')
      render_without_traceview(options, extra_options, &block)

    rescue Exception => e
      TraceView::API.log_exception(nil, e) if log_merb_error?(e)
      raise
    ensure
      TraceView::API.log_exit('merb_view')
    end
  end

  TraceView.logger.info '[traceview/loading] Instrumenting controller' if TraceView::Config[:verbose]
end
# vim:set expandtab:tabstop=2
