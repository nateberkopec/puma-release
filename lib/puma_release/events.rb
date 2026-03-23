# frozen_string_literal: true

module PumaRelease
  class Events
    def initialize
      @subscribers = Hash.new { |hash, key| hash[key] = [] }
    end

    def subscribe(name = :all, &block)
      @subscribers[name] << block
    end

    def publish(name, payload = {})
      @subscribers.fetch(:all, []).each { |subscriber| subscriber.call(name, payload) }
      @subscribers.fetch(name, []).each { |subscriber| subscriber.call(name, payload) }
    end
  end
end
