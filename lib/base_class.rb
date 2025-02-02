class BaseClass
  include Dry::Monads[:result]

  def self.call(...)
    new.call(...)
  end

  private

  def logger(log_file_path = 'tmp/application.log')
    return @logger if @logger

    @logger = Logger.new(log_file_path)
    @logger.level = Logger::DEBUG
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "#{datetime}: #{severity} - #{msg}\n"
    end
    @logger
  end
end
