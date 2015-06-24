class ProcessingError < RuntimeError
end

module Helpers
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    private
    def fail(message)
      raise ProcessingError.new(message)
    end
  end

  private

  def fail(message)
    raise ProcessingError.new(message)
  end

  def say(message)
    puts message  unless $options.quiet
  end
end
