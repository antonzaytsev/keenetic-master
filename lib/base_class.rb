require 'logger'
require 'fileutils'

class BaseClass
  include Dry::Monads[:result]

  class << self
    def call(...)
      new.call(...)
    end
  end

  private

  def logger(output = default_log_file)
    @logger ||= create_logger(output)
  end

  def create_logger(output)
    ensure_log_directory if output.is_a?(String)

    logger = Logger.new(output)
    logger.level = log_level
    logger.formatter = log_formatter
    logger
  end

  def default_log_file
    'tmp/logs/application.log'
  end

  def ensure_log_directory
    log_dir = File.dirname(default_log_file)
    FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)
  end

  def log_level
    case ENV.fetch('LOG_LEVEL', 'INFO').upcase
    when 'DEBUG' then Logger::DEBUG
    when 'INFO' then Logger::INFO
    when 'WARN' then Logger::WARN
    when 'ERROR' then Logger::ERROR
    when 'FATAL' then Logger::FATAL
    else Logger::INFO
    end
  end

  def log_formatter
    proc do |severity, datetime, progname, msg|
      timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S')
      "[#{timestamp}] #{severity.ljust(5)} #{progname} - #{msg}\n"
    end
  end

  def handle_error(error, context = nil)
    error_message = context ? "#{context}: #{error.message}" : error.message
    logger.error(error_message)
    logger.debug(error.backtrace.join("\n")) if error.respond_to?(:backtrace)

    Failure(message: error_message, error: error, backtrace: error.backtrace)
  end
end
