# frozen_string_literal: true

require 'open_food_network/scope_variant_to_hub'

module Spree
  module Core
    module ControllerHelpers
      module Order
        def self.included(base)
          base.class_eval do
            helper_method :current_order
            helper_method :current_currency
            before_filter :set_current_order
          end
        end

        def current_order(create_order_if_necessary = false)
          order = spree_current_order(create_order_if_necessary)

          if order
            scoper = OpenFoodNetwork::ScopeVariantToHub.new(order.distributor)
            order.line_items.each do |li|
              scoper.scope(li.variant)
            end
          end

          order
        end

        # The current incomplete session order used in cart and checkout
        def spree_current_order(create_order_if_necessary = false)
          return @current_order if @current_order

          if session[:order_id]
            current_order = Spree::Order.includes(:adjustments)
              .find_by(id: session[:order_id], currency: current_currency)
            @current_order = current_order unless current_order.try(:completed?)
          end

          if create_order_if_necessary && (@current_order.nil? || @current_order.completed?)
            @current_order = Spree::Order.new(currency: current_currency)
            @current_order.user ||= spree_current_user
            # See https://github.com/spree/spree/issues/3346 for reasons why this line is here
            @current_order.created_by ||= spree_current_user
            @current_order.save!

            # Verify that the user has access to the order (if they are a guest)
            if spree_current_user.nil?
              session[:access_token] = @current_order.token
            end
          end

          return unless @current_order

          @current_order.last_ip_address = ip_address
          session[:order_id] = @current_order.id
          @current_order
        end

        def associate_user
          @order ||= current_order
          if spree_current_user && @order
            if @order.user.blank? || @order.email.blank?
              @order.associate_user!(spree_current_user)
            end
          end

          session[:guest_token] = nil
        end

        # Do not attempt to merge incomplete and current orders.
        #   Instead, destroy the incomplete orders.
        def set_current_order
          return unless (user = spree_current_user)

          last_incomplete_order = user.last_incomplete_spree_order

          if session[:order_id].nil? && last_incomplete_order
            session[:order_id] = last_incomplete_order.id
          elsif current_order(true) &&
                last_incomplete_order &&
                current_order != last_incomplete_order
            last_incomplete_order.destroy
          end
        end

        def current_currency
          Spree::Config[:currency]
        end

        def ip_address
          request.env['HTTP_X_REAL_IP'] || request.env['REMOTE_ADDR']
        end
      end
    end
  end
end
