#!/usr/bin/env ruby

abort "Usage: update-brew-cask.rb PATH VERSION SHA256" unless ARGV.length == 3

path, version, sha = ARGV
abort "Invalid version: #{version}" unless version.match?(/\A[A-Za-z0-9._-]+\z/)
abort "Invalid SHA-256: #{sha}" unless sha.match?(/\A[0-9a-f]{64}\z/)

content = File.read(path)

unless content.scan(/^  version .+$/).length == 1
  abort "Expected exactly one version stanza in #{path}"
end
unless content.scan(/^  sha256 .+$/).length == 1
  abort "Expected exactly one sha256 stanza in #{path}"
end

content.sub!(/^  version .+$/, %(  version "#{version}"))
content.sub!(/^  sha256 .+$/, %(  sha256 "#{sha}"))
File.write(path, content)
