require "fiddle"
require "fileutils"
require "logger"
require "pathname"
require "pp"
require "s3sync/exception"
require "securerandom"

#require_relative "exception.rb"

class Object
  def unfreeze
    Fiddle::Pointer.new(object_id * 2)[1] &= ~(1 << 3)
  end
end

class Logger
	def self.custom_level(tag)
		SEV_LABEL.unfreeze
		SEV_LABEL << tag 
		idx = SEV_LABEL.size - 1

		define_method(tag.downcase.gsub(/\W+/, '_').to_sym) do |progname, &block|
			add(idx, nil, progname, &block)
		end
	end

	custom_level "DRYRUN"
end

module S3Sync
	class Utils
		def initialize(*args)
			args = args[0] || {}
			@debug = false
			@dryrun = false

			if args[:debug]
				@debug = args[:debug] if args[:debug].is_a?(Boolean)
			end

			if args[:dryrun]
				@dryrun = args[:dryrun] if args[:dryrun].is_a?(Boolean)
			end

			@logger = configure_logger(debug: @debug)
			return self
		end

		def configure_logger(debug: false)
			logger = Logger.new(STDOUT)
			logger.level = debug ? Logger::DEBUG : Logger::INFO
			logger.datetime_format = "%Y-%m-%d %H:%M:%S"
			logger.formatter = proc do |severity, datetime, progname, msg|
				sprintf("[%s] %s\n", severity.capitalize, msg)
			end
			return logger
		end

		def generate_random(length=8)
			return SecureRandom.hex(n=length)
		end

		def create_path(path: nil)
			begin
				FileUtils.mkpath(path)
			rescue Errno::EACCES => e
				raise S3Sync::MkdirError.new(path: path, message: "Permission denied")
			rescue Errno::EEXIST => e
				raise S3Sync::MkdirError.new(path: path, message: "File exists")
			rescue Exception => e
				raise S3Sync::MkdirError.new(path: path, message: e)
			end
		end

		def copy_file(src: nil, dest: nil)
			begin
				FileUtils.cp src, dest
			rescue Errno::ENOENT => e
				raise S3Sync::FileCopyError.new(path: path, message: "No such file or directory")
			rescue Errno::EACCES => e
				raise S3Sync::FileCopyError.new(path: path, message: "Permission denied")
			rescue Errno::EISDIR => e
				raise S3Sync::FileCopyError.new(path: path, message: "Is a directory")
			rescue Exception => e
				raise S3Sync::FileCopyError.new(path: path, message: e)
			end
		end

		def rel_to_abs(path)
			return File.join ([""] + Pathname(Dir.pwd).each_filename.to_a + Pathname(path).each_filename.to_a)
		end
	end
end
