require "forkmanager"
require "s3sync/exception"
require "s3sync/utils"

#require_relative "exception.rb"
#require_relative "utils.rb"

module S3Sync
	class ForkManager
		attr_accessor :forker
		def initialize(*args)
			args = args[0] || {}
			@utils = S3Sync::Utils.new
			@dryrun = (args.key?(:dryrun) and args[:dryrun].is_a?(Boolean)) ? args[:dryrun] : false
			@logger = @utils.configure_logger(debug: @debug)

			max_procs = 12
			$pm = Parallel::ForkManager.new(max_procs, {"tempdir" => "/tmp"})
			$pm.run_on_start do |pid, ident|
				message = ident["message"]
				if @dryrun == true
					@logger.dryrun(message)
				else
					puts message
				end
			end

			$pm.run_on_finish do |pid,exit_code,ident,exit_signal,core_dump,data_structure|
				if (defined?(data_structure))
					data_structure
					if data_structure["status"] == "success"
					elsif data_structure["status"] == "error"
						message = data_structure.key?("message") ? data_structure["message"] : "Unspecified error"
						@logger.error(message)
					end
				else
					@logger.warn("No message received from child process #{pid}!")
				end
			end
		end
	end
end
