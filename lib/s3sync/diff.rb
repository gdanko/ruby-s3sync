require "fileutils"
require "find"
require "pathname"
require "s3sync/exception"
require "s3sync/utils"
require "uri"

#require_relative "exception.rb"
#require_relative "utils.rb"

# Add is_a?(Boolean)
module Boolean; end
class TrueClass; include Boolean; end
class FalseClass; include Boolean; end

module S3Sync
	class Diff
		attr_accessor :common
		attr_accessor :destination
		attr_accessor :destination_bucket
		attr_accessor :destination_list
		attr_accessor :destination_md5_mismatch
		attr_accessor :destination_only
		attr_accessor :destination_path
		attr_accessor :destination_root
		attr_accessor :destination_type
		attr_accessor :source
		attr_accessor :source_bucket
		attr_accessor :source_key
		attr_accessor :source_list
		attr_accessor :source_md5_mismatch
		attr_accessor :source_only
		attr_accessor :source_path
		attr_accessor :source_type
		attr_accessor :sync_list
		def initialize(*args)
			args = args[0] || {}
			self.common = {}
			self.source_list, self.destination_list = {}, {}
			self.source_only, self.destination_only = {}, {}
			self.source_md5_mismatch, self.destination_md5_mismatch = {}, {}
			self.sync_list = {}
			@utils = S3Sync::Utils.new

			if args[:source]
				self.source = args[:source]
			else
				raise S3Sync::MissingConstructorParameter.new(parameter: "source")
			end

			if args[:destination]
				self.destination = args[:destination]
			else
				raise S3Sync::MissingConstructorParameter.new(parameter: "destination")
			end

			if args[:s3]
				@s3 = args[:s3]
			else
				raise S3Sync::MissingConstructorParameter.new(parameter: "s3")
			end

			@delete = (args.key?(:delete) and args[:delete].is_a?(Boolean)) ? args[:delete] : true
			@exclude = (args.key?(:exclude) and not args[:exclude].nil?) ? args[:exclude] : []
			@include = (args.key?(:include) and not args[:include].nil?) ? args[:include] : []
		end

		def determine_types
			# Source
			if self.source =~ /^s3:/
				source = URI(self.source)
				self.source_type = "s3"
				self.source_bucket = source.host
				self.source_path = source.path.gsub(/^\//, "")
			else
				self.source_type = "local"
				self.source_path = self.source
			end

			# Destination
			if self.destination =~ /^s3:/
				destination = URI(self.destination)
				self.destination_type = "s3"
				self.destination_bucket = destination.host
				self.destination_path = destination.path.gsub(/^\//, "")
			else
				self.destination = rel_to_abs(self.destination) if Pathname(self.destination).relative?
				self.destination_type = "local"
				self.destination_path = self.destination
				self.destination_root = File.expand_path("..", self.destination_path)
				@utils.create_path(path: self.destination_path)
			end
			raise S3Sync::LocalToLocalSync.new() if self.source_type == "local" and self.destination_type == "local"
		end

		def generate_sync_list
			to_sync = self.source_only.merge(self.source_md5_mismatch)
			to_sync.each do |name, file_obj|
				if self.source_type == "s3" and self.destination_type == "s3"
					source_bucket = self.source_bucket
					source_key = file_obj["key"]
					source = sprintf("s3://%s/%s", source_bucket, source_key)

					destination_bucket = self.destination_bucket
					pieces = Pathname(file_obj["dirname"]).each_filename.to_a
					pieces[ pieces.index(self.source_path) ] = self.destination_path
					destination_key = sprintf("%s/%s", pieces.join("/"), name)
					destination = sprintf("%s/%s", destination_bucket, destination_key)
					self.sync_list[name] = {
						"action" => "copy",
						"message" => sprintf("copy: %s to %s", source, destination),
						"source_bucket" => source_bucket,
						"source_key" => source_key,
						"source" => source,
						"copy_source" => sprintf("%s/%s", destination_bucket, source_key),
						"destination_bucket" => destination_bucket,
						"destination_key" => destination_key,
						"destination" => destination,
					}

				elsif self.source_type == "s3" and self.destination_type == "local"
					source_bucket = self.source_bucket
					source_key = file_obj["key"]
					source = sprintf("s3://%s/%s", source_bucket, source_key)

					destination = sprintf("%s/%s", self.destination_path, name)
					destination_directory = File.dirname(destination)

					self.sync_list[name] = {
						"action" => "download",
						"message" => sprintf("download: %s to %s", source, destination),
						"source_bucket" => source_bucket,
						"source_key" => source_key,
						"source" => source,
						"destination_directory" => destination_directory,
						"destination" => destination,
					}

				elsif self.source_type == "local" and self.destination_type == "s3"
					source = file_obj["path"]

					destination_bucket = self.destination_bucket
					destination_key = sprintf("%s/%s", file_obj["dirname"], file_obj["filename"])
					destination = sprintf("s3://%s/%s", self.destination_bucket, destination_key)

					self.sync_list[name] = {
						"action" => "upload",
						"message" => sprintf("upload: %s to %s", source, destination),
						"source" => source,
						"destination_bucket" => destination_bucket,
						"destination_key" => destination_key,
						"destination" => destination,
					}
				end
			end

			if @delete == true
				self.destination_only.each do |name, file_obj|
					if self.destination_type == "s3"
						self.sync_list[name] = {
							"action" => "delete",
							"message" => sprintf("delete: s3://%s/%s", self.destination_bucket, file_obj["key"]),
							"bucket" => self.destination_bucket,
							"key" => file_obj["key"],
						}

					elsif self.destination_type == "local"
						self.sync_list[name] = {
							"action" => "delete",
							"message" => sprintf("delete: %s", file_obj["path"]),
							"path" => file_obj["path"],
						}
					end
				end
			end
		end

		def diff
			printf("building file list ... ")
			if self.source_type == "local"
				self.source_list = get_local_files(path: self.source_path)
			elsif self.source_type == "s3"
				self.source_list = get_s3_files(bucket: self.source_bucket, path: self.source_path)
			end

			if self.destination_type == "local"
				self.destination_list = get_local_files(path: self.destination_path)
			elsif self.destination_type == "s3"
				self.destination_list = get_s3_files(bucket: self.destination_bucket, path: self.destination_path)
			end

			self.source_list.each do |name, obj|
				if self.destination_list.key?(name)
					if self.destination_list[name]["md5sum"] == self.source_list[name]["md5sum"]
						self.common[name] = obj
					else
						self.source_md5_mismatch[name] = obj
					end
				else
					self.source_only[name] = obj
				end
			end			

			self.destination_list.each do |name, obj|
				if self.source_list.key?(name)
					if self.source_list[name]["md5sum"] == self.destination_list[name]["md5sum"]
						self.common[name] = obj
					else
						self.destination_md5_mismatch[name] = obj
					end
				else
					self.destination_only[name] = obj
				end
			end
			puts "done"
		end

		def is_excluded(filename)
			return false if @exclude.length <= 0
			out = false
			@exclude.each do |pattern|
				return out if out == true
				if pattern =~ /^\*([^\*]+)$/
					out = filename =~ /#{$1}$/ ? true : false
				elsif pattern =~ /^([^\*]+)\*$/
					out = filename =~ /^#{$1}/ ? true : false
				elsif pattern =~ /^\*([^\*]+)\*$/
					out = filename =~ /#{$1}/ ? true : false
				else
					out = filename == pattern ? true : false
				end
			end
			return out
		end

		def get_local_files(path: nil)
			output = {}
			Find.find(path) do |item|
				p1 = Pathname(item)
				p2 = Pathname(File.expand_path("..", path))
				key = p1.relative_path_from(p2).to_s
				stripped_key = Pathname(key).each_filename.to_a[1..-1].join("/")
				if File.file?(item)
					output[stripped_key] = {
						"path" => item,
						"dirname" => File.dirname(key),
						"filename" => File.basename(key),
						"size" => File.size(item),
						"md5sum" => Digest::MD5.hexdigest(File.read(item)),
						"exclude" => is_excluded(File.basename(key)),
					}
				end
			end
			return output
		end

		def get_s3_files(bucket: nil, path: nil)
			output = {}
			begin
				resp = @s3.list_objects_v2(bucket: bucket, prefix: sprintf("%s/", path))
				resp["contents"].each do |file_obj|
					key = file_obj["key"]
					stripped_key = Pathname(key).each_filename.to_a[1..-1].join("/")
					if key !~ /\/$/ and file_obj["size"] != 0
						etag = file_obj["etag"].gsub(/"/, "")
						output[stripped_key] = {
							"dirname" => File.dirname(key),
							"filename" => File.basename(key),
							"key" => sprintf("%s/%s", File.dirname(key), File.basename(key)),
							"size" => file_obj["size"],
							"md5sum" => etag,
							"exclude" => is_excluded(File.basename(key)),
						}
					end
				end
				return output
			rescue
				# real exception here
				puts "Failed to get the list from s3"
				exit 1
			end
		end
	end
end