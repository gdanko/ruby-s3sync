#!/usr/bin/env ruby

require_relative "lib/s3sync/sync.rb"
require "pp"

syncer = S3Sync::Syncer.new(
	#source: "/Users/gdanko/.s3gem/s3-us-west-2.amazonaws.com/automation-patterns-repo/gem-repo",
	#destination: "s3://automation-patterns-repo/gem-repo",
	source: "s3://automation-patterns-repo/gem-repo",
	destination: "s3://automation-patterns-repo/pypi",
	region: "us-west-2",
	profile: "default",
	acl: "public-read",
	delete: true
)

#pp syncer.s3diff.source_list