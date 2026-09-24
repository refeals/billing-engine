module RuboCop
  module Cop
    module Billing
      # Flags reads of the real clock. Billing code must ask BillingClock.now, otherwise it
      # ignores simulated time and the demo's fast-forwarded flows silently break.
      #
      # @example
      #   # bad
      #   Time.current
      #   Date.today
      #
      #   # good
      #   BillingClock.now
      #   BillingClock.now.to_date
      class DirectTimeAccess < Base
        MSG = "Use `BillingClock.now` instead of `%<call>s`; real time bypasses the simulated clock."

        RESTRICT_ON_SEND = %i[now current today].freeze

        # @!method real_time_call?(node)
        def_node_matcher :real_time_call?, <<~PATTERN
          {
            (send (const {nil? cbase} :Time) {:now :current})
            (send (send (const {nil? cbase} :Time) :zone) :now)
            (send (const {nil? cbase} :Date) {:today :current})
            (send (const {nil? cbase} :DateTime) {:now :current})
          }
        PATTERN

        def on_send(node)
          return unless real_time_call?(node)

          add_offense(node, message: format(MSG, call: node.source))
        end
      end
    end
  end
end
