# Services are verbs (`Plans::Archive`) with a single public entry point.
class ApplicationService
  def self.call(...)
    new(...).call
  end
end
