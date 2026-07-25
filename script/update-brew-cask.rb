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

unless content.match?(/^  auto_updates true$/)
  unless content.scan(/^  conflicts_with .+$/).length == 1
    abort "Expected exactly one conflicts_with stanza in #{path}"
  end
  content.sub!(/^  conflicts_with .+$/, "  auto_updates true\n\\0")
end
content.sub!(/^  homepage (.+)\n  auto_updates true\n\n  conflicts_with /,
             "  homepage \\1\n\n  auto_updates true\n  conflicts_with ")

artifact_migrations = {
  '"AeroSpace-v#{version}/bin/aerospace"' =>
    '"#{appdir}/AeroSpace.app/Contents/Helpers/aerospace"',
  '"AeroSpace-v#{version}/shell-completion/zsh/_aerospace"' =>
    '"#{appdir}/AeroSpace.app/Contents/Resources/shell-completion/zsh/_aerospace"',
  '"AeroSpace-v#{version}/shell-completion/bash/aerospace"' =>
    '"#{appdir}/AeroSpace.app/Contents/Resources/shell-completion/bash/aerospace"',
  '"AeroSpace-v#{version}/shell-completion/fish/aerospace.fish"' =>
    '"#{appdir}/AeroSpace.app/Contents/Resources/shell-completion/fish/aerospace.fish"',
}
artifact_migrations.each do |old_path, bundled_path|
  content.sub!(old_path, bundled_path)
  abort "Expected bundled artifact path #{bundled_path} in #{path}" unless content.include?(bundled_path)
end

manpage_paths = Dir[".man/*.1"].sort
abort "No generated manpages found in .man" if manpage_paths.empty?
manpage_lines = manpage_paths.map do |manpage_path|
  manpage_name = File.basename(manpage_path)
  %(  manpage "\#{appdir}/AeroSpace.app/Contents/Resources/manpage/#{manpage_name}")
end
unless content.include?(manpage_lines.first)
  legacy_manpages = /^  Dir\[.+\/manpage\/\*"\]\.each \{ \|man\| manpage man \}$/
  abort "Expected legacy manpage stanza in #{path}" unless content.match?(legacy_manpages)
  content.sub!(legacy_manpages, manpage_lines.join("\n"))
end

File.write(path, content)
