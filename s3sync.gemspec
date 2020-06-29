# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "s3sync/version"

Gem::Specification.new do |spec|
  spec.name          = "s3sync"
  spec.version       = S3Sync::VERSION
  spec.authors       = ["Gary Danko"]
  spec.email         = ["gary_danko@intuit.com"]
  spec.summary       = "S3 sync utility"
  spec.description   = "Sync from S3 > S3, S3 > Local, or Local > S3"
  spec.homepage      = "https://github.intuit.com/gdanko/S3Sync"
  spec.license       = "GPL-2.0"

  spec.files = [
    "lib/s3sync/diff.rb",
    "lib/s3sync/exception.rb",
    "lib/s3sync/forkmanager.rb",
    "lib/s3sync/sync.rb",
    "lib/s3sync/utils.rb",
    "lib/s3sync.rb",
  ]

  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.0.0"

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_runtime_dependency "aws-sdk-s3", "~> 1.12", ">=1.12.0"
  spec.add_runtime_dependency "parallel-forkmanager", "~> 2.0.1", ">= 2.0.1"
end
