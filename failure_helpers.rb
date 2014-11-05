class ProcessingError < RuntimeError
end

module FailureHelpers
  private

  def self.fail(message)
    raise ProcessingError.new(message)
  end

  def fail(message)
    raise ProcessingError.new(message)
  end
end
