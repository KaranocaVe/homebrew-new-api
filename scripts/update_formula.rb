require "json"
require "rubygems"

FORMULA_PATH = File.expand_path("../Formula/new-api.rb", __dir__)
SUPPORTED_STABLE_TAG = /\Av\d+\.\d+\.\d+\z/
SUPPORTED_RC_TAG = /\Av\d+\.\d+\.\d+-rc\.\d+\z/

def formula_version
  match = File.read(FORMULA_PATH).match(/^  version "([^"]+)"$/)
  abort "Could not read the pinned Formula version" unless match

  match[1]
end

def supported_release?(release)
  tag = release.fetch("tag_name", "")
  return false if release["draft"]
  return true if tag.match?(SUPPORTED_RC_TAG)

  tag.match?(SUPPORTED_STABLE_TAG) && !release["prerelease"]
end

def expected_macos_asset(release)
  tag = release.fetch("tag_name")
  name = "new-api-macos-#{tag}"
  asset = release.fetch("assets", []).find { |candidate| candidate["name"] == name }
  abort "#{tag} has no exact macOS asset named #{name}" unless asset

  expected_url = "https://github.com/QuantumNous/new-api/releases/download/#{tag}/#{name}"
  abort "Unexpected download URL for #{name}" unless asset["browser_download_url"] == expected_url

  digest = asset.fetch("digest", "")
  abort "GitHub did not publish a SHA-256 digest for #{name}" unless digest.match?(/\Asha256:[a-f0-9]{64}\z/)

  [name, asset, digest.delete_prefix("sha256:")]
end

def select_release(releases)
  current = Gem::Version.new(formula_version)
  candidates = releases.select { |release| supported_release?(release) }
  abort "No supported stable or RC releases found" if candidates.empty?

  release = candidates.max_by { |candidate| Gem::Version.new(candidate.fetch("tag_name").delete_prefix("v")) }
  tag = release.fetch("tag_name")
  name, asset, digest = expected_macos_asset(release)
  version = tag.delete_prefix("v")

  if Gem::Version.new(version) <= current
    puts "update_available=false"
    puts "current_version=#{current}"
    return
  end

  puts "update_available=true"
  puts "tag=#{tag}"
  puts "version=#{version}"
  puts "asset_name=#{name}"
  puts "asset_url=#{asset.fetch('browser_download_url')}"
  puts "asset_sha256=#{digest}"
  puts "source_url=https://github.com/QuantumNous/new-api/archive/refs/tags/#{tag}.tar.gz"
end

def update_formula(version, source_sha256)
  abort "Invalid version" unless version.match?(/\A\d+\.\d+\.\d+(?:-rc\.\d+)?\z/)
  abort "Invalid source SHA-256" unless source_sha256.match?(/\A[a-f0-9]{64}\z/)

  current = formula_version
  abort "Refusing to move Formula backwards or repeat its current version" unless Gem::Version.new(version) > Gem::Version.new(current)

  contents = File.read(FORMULA_PATH)
  replacements = {
    /^  url "https:\/\/github\.com\/QuantumNous\/new-api\/archive\/refs\/tags\/v[^"]+\.tar\.gz"$/ => "  url \"https://github.com/QuantumNous/new-api/archive/refs/tags/v#{version}.tar.gz\"",
    /^  version "[^"]+"$/ => "  version \"#{version}\"",
    /^  sha256 "[a-f0-9]{64}"$/ => "  sha256 \"#{source_sha256}\"",
  }

  replacements.each do |pattern, replacement|
    abort "Expected exactly one Formula field for #{pattern}" unless contents.scan(pattern).length == 1

    contents.sub!(pattern, replacement)
  end

  File.write(FORMULA_PATH, contents)
  puts "Updated Formula from #{current} to #{version}"
end

case ARGV.shift
when "select"
  release_json = ARGV.fetch(0) { abort "Usage: update_formula.rb select RELEASES_JSON" }
  select_release(JSON.parse(File.read(release_json)))
when "update"
  version = ARGV.fetch(0) { abort "Usage: update_formula.rb update VERSION SOURCE_SHA256" }
  sha256 = ARGV.fetch(1) { abort "Usage: update_formula.rb update VERSION SOURCE_SHA256" }
  update_formula(version, sha256)
else
  abort "Usage: update_formula.rb {select RELEASES_JSON|update VERSION SOURCE_SHA256}"
end
