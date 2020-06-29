require "aws-sdk-s3"
require "s3sync/diff"
require "s3sync/exception"
require "s3sync/forkmanager"
require "s3sync/utils"

#require_relative "diff.rb"
#require_relative "exception.rb"
#require_relative "forkmanager.rb"
#require_relative "utils.rb"

# Add is_a?(Boolean)
module Boolean; end
class TrueClass; include Boolean; end
class FalseClass; include Boolean; end

module S3Sync
	class Syncer
		attr_accessor :s3diff
		def initialize(*args)
			args = args[0] || {}

			# Required options
			if args[:source]
				@source = args[:source].gsub(/\/$/, "")
			else
				raise S3Sync::MissingConstructorParameter.new(parameter: "source")
			end

			if args[:destination]
				@destination = args[:destination].gsub(/\/$/, "")
			else
				raise S3Sync::MissingConstructorParameter.new(parameter: "destination")
			end

			raise S3Sync::MissingConstructorParameter.new(parameter: "profile") unless args[:profile]
			raise S3Sync::MissingConstructorParameter.new(parameter: "region") unless args[:region]

			@debug = (args.key?(:debug) and args[:debug].is_a?(Boolean)) ? args[:debug] : false
			@dryrun = (args.key?(:dryrun) and args[:dryrun].is_a?(Boolean)) ? args[:dryrun] : false

			@acl = args.key?(:acl) ? args[:acl] : "private"
			@delete = (args.key?(:delete) and args[:delete].is_a?(Boolean)) ? args[:delete] : false
			@verify = (args.key?(:verify) and args[:verify].is_a?(Boolean)) ? args[:verify] : false
			@exclude = (args.key?(:exclude) and not args[:exclude].nil?) ? args[:exclude].split(/\s*,\s*/) : []
			@include = (args.key?(:include) and not args[:include].nil?) ? args[:include].split(/\s*,\s*/) : []

			@utils = S3Sync::Utils.new
			@s3 = Aws::S3::Client.new(region: args[:region], profile: args[:profile])

			@logger = @utils.configure_logger(debug: @debug)

			# Better way to create the forkmanager??
			@forkmanager = S3Sync::ForkManager.new(dryrun: @dryrun)
			self.init
		end

		def sync
			sync_files
		end

		def init()
			self.s3diff = S3Sync::Diff.new(
				source: @source,
				destination: @destination,
				s3: @s3,
				include: @include,
				exclude: @exclude,
				delete: @delete
			)
			self.s3diff.determine_types
			self.s3diff.diff
			self.s3diff.generate_sync_list
		end

		def reverse
			old_source = @source
			old_destination = @destination
			@source = old_destination
			@destination = old_source
			self.init
		end

		private
		def sync_files()
			if self.s3diff.sync_list.keys.length > 0
				self.s3diff.sync_list.each do |name, file_obj|
					action = file_obj["action"]
					pid = $pm.start({"message" => file_obj["message"]}) and next

					case action
					when "copy"
						out = s3_to_s3(file_obj: file_obj)
					when "download"
						out = s3_to_local(file_obj: file_obj)
					when "upload"
						out = local_to_s3(file_obj: file_obj)
					when "delete"
						out = delete_file(file_obj: file_obj)
					end
					$pm.finish(0, out)
				end
				$pm.wait_all_children
			end	
		end

		def s3_to_s3(file_obj: nil)
			out = {"status" => "success"}
			return out if @dryrun == true

			begin
				resp = @s3.copy_object(
					bucket: file_obj["source_bucket"],
					copy_source: file_obj["copy_source"],
					key: file_obj["destination_key"],
				)
				return out
			rescue Exception => e
				out["status"] = "error"
				out["message"] = "No such file or directory"
				return out
			end
		end

		def s3_to_local(file_obj: nil)
			out = {"status" => "success"}
			return out if @dryrun == true

			begin
				@utils.create_path(path: file_obj["destination_directory"])
			rescue Exception => e
				message = sprintf("failed to create the directory %s: %s", file_obj["destination_directory"], e)
				out["status"] = "error"
				out["message"] = message
				return out
			end

			begin
				File.open(file_obj["destination"], "wb") do |fh|
					@s3.get_object(bucket: file_obj["source_bucket"], key: file_obj["source_key"]) do |chunk|
						fh.write(chunk)
					end
					return out
				end
			rescue Exception => e
				out["status"] = "error"
				out["message"] = e
				return out
			end
		end

		def local_to_s3(file_obj: nil)
			out = {"status" => "success"}
			return out if @dryrun == true

			begin
	 			resp = @s3.put_object(
	 				acl: @acl,
	 				body: File.read(file_obj["source"]),
	 				bucket: file_obj["destination_bucket"],
	 				key: file_obj["destination_key"],
	 			)
	 			return out
	 		rescue Exception => e
	 			out["status"] = "error"
	 			out["message"] = e
	 			return out
	 		end
		end

		def delete_file(file_obj: nil)
			out = {"status" => "success"}
			return out if @dryrun == true

			if file_obj.key?("path")
				begin
					File.delete(file_obj["path"])
					return out
				rescue Exception => e
					out["status"] = "error"
					out["message"] = sprintf("failed to delete the file %s: %s", file_obj["path"], e)
					return out
				end

			elsif file_obj.key?("bucket") and file_obj.key?("key")
				begin
					resp = @s3.delete_object(
						bucket: file_obj["bucket"],
						key: file_obj["key"],
					)
					return out
				rescue Exception => e
					out["status"] = "error"
					out["message"] = sprintf("failed to delete the file s3://%s/%s: %s", @destination_bucket, key, e)
					return out
				end
			end
		end
	end
end
