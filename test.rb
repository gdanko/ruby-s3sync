#!/usr/bin/env ruby

require_relative "lib/s3sync/sync.rb"
#require "pathname"
#require "pp"



syncer = S3Sync::Syncer.new(
	# Local > S3
	#source: "/Users/gdanko/.s3gem/s3-us-west-2.amazonaws.com/automation-patterns-repo/gem-repo/",
	#destination: "s3://automation-patterns-repo/gem-repo",

	# S3 > S3
	source: "s3://automation-patterns-repo/gem-repo",
	destination: "s3://automation-patterns-repo/pypi",

	# S3 > Local
	#source: "s3://automation-patterns-repo/gem-repo/",
	#destination: "/Users/gdanko/.s3gem/s3-us-west-2.amazonaws.com/automation-patterns-repo/gem-repo/",

	region: "us-west-2",
	profile: "default",
	delete: true,
	#dryrun: true,
	debug: true,
	#exclude: "specs.4.8,idps*",
	#@include: nil,
	acl: "public-read",
)

syncer.sync
#syncer.reverse
