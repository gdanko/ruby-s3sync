module S3Sync
	class MissingConstructorParameter < StandardError
		def initialize(parameter: nil)
			@parameter = parameter
			@error = sprintf("The required \"%s\" parameter is missing from the constructor.", @parameter)
			super(@error)
		end
	end

	class LocalToLocalSync < StandardError
		def initialize()
			@error = "You are trying to sync local to local with this module. Try rsync."
			super(@error)
		end
	end

	class FileReadError < StandardError
		def initialize(path: nil, message: nil)
			@message = message
			@path = path
			@error = sprintf("An error occurred while reading the specified baseline configuration file \"%s\": %s", @path, @message)
			super(@error)
		end
	end

	class FileWriteError < StandardError
		def initialize(path: nil, message: nil)
			@message = message
			@path = path
			@error = sprintf("An error occurred while writing the file \"%s\": %s", @path, @message)
			super(@error)
		end
	end

	class FileCopyError < StandardError
		def initialize(src: nil, dest: nil, message: nil)
			@src = src
			@dest = dest
			@message = message
			@error = sprintf("An error occurred while copying the file \"%s\" to \"%s\": %s", @src, @dest, @message)
			super(@error)
		end
	end

	class MkdirError < StandardError
		def initialize(path: nil, message: nil)
			@path = path
			@message = message
			@error = sprintf("An error occurred while creating the directory \"%s\": %s", @path, @message)
			super(@error)
		end
	end
end