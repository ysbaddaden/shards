require "uri"
require "./resolver"
require "../versions"
require "../logger"
require "../helpers"

module Shards
  abstract struct FossilRef < Ref
    def full_info
      to_s
    end
  end

  struct FossilBranchRef < FossilRef
    def initialize(@branch : String)
    end

    def to_fossil_ref
      @branch
    end

    def to_s(io)
      io << "branch " << @branch
    end

    def to_yaml(yaml)
      yaml.scalar "branch"
      yaml.scalar @branch
    end
  end

  struct FossilTagRef < FossilRef
    def initialize(@tag : String)
    end

    def to_fossil_ref
      @tag
    end

    def to_s(io)
      io << "tag " << @tag
    end

    def to_yaml(yaml)
      yaml.scalar "tag"
      yaml.scalar @tag
    end
  end

  struct FossilCommitRef < FossilRef
    getter commit : String

    def initialize(@commit : String)
    end

    def =~(other : FossilCommitRef)
      commit.starts_with?(other.commit) || other.commit.starts_with?(commit)
    end

    def to_fossil_ref
      @commit
    end

    def to_s(io)
      io << "commit " << @commit[0...7]
    end

    def full_info
      "commit #{@commit}"
    end

    def to_yaml(yaml)
      yaml.scalar "commit"
      yaml.scalar @commit
    end
  end

  struct FossilTrunkRef < FossilRef
    def to_fossil_ref
      "trunk"
    end

    def to_s(io)
      io << "trunk"
    end

    def to_yaml(yaml)
      raise NotImplementedError.new("FossilTrunkRef is for internal use only")
    end
  end

  class FossilResolver < Resolver
    @@has_fossil_command : Bool?
    @@fossil_version_maj : Int8?
    @@fossil_version_min : Int8?
    @@fossil_version_rev : Int8?
    @@fossil_version : String?

    @origin_url : String?
    @local_fossil_file : String?

    def self.key
      "fossil"
    end

    def self.normalize_key_source(key : String, source : String) : {String, String}
      case key
      when "fossil"
        {"fossil", source}
      else
        raise "Unknown resolver #{key}"
      end
    end

    protected def self.has_fossil_command?
      if @@has_fossil_command.nil?
        @@has_fossil_command = (Process.run("fossil version", shell: true).success? rescue false)
      end
      @@has_fossil_command
    end

    protected def self.fossil_version
      unless @@fossil_version
        @@fossil_version = `fossil version`[/version\s+([^\s]*)/, 1]
        pieces = @@fossil_version.not_nil!.split('.')
        @@fossil_version_maj = pieces[0].to_i8
        @@fossil_version_min = pieces[1].to_i8
        @@fossil_version_rev = (pieces[2]?.try &.to_i8 || 0i8)
      end

      @@fossil_version
    end

    protected def self.fossil_version_maj
      self.fossil_version unless @@fossil_version_maj
      @@fossil_version_maj.not_nil!
    end

    protected def self.fossil_version_min
      self.fossil_version unless @@fossil_version_min
      @@fossil_version_min.not_nil!
    end

    protected def self.fossil_version_rev
      self.fossil_version unless @@fossil_version_rev
      @@fossil_version_rev.not_nil!
    end

    def read_spec(version : Version) : String?
      update_local_cache
      ref = fossil_ref(version)

      if file_exists?(ref, SPEC_FILENAME)
        capture("fossil cat -R #{Process.quote(local_fossil_file)} #{Process.quote(SPEC_FILENAME)} -r #{Process.quote(ref.to_fossil_ref)}")
      else
        Log.debug { "Missing \"#{SPEC_FILENAME}\" for #{name.inspect} at #{ref}" }
        nil
      end
    end

    private def spec_at_ref(ref : FossilRef, commit) : Spec
      update_local_cache

      unless capture("fossil ls -R #{Process.quote(local_fossil_file)} -r #{Process.quote(ref.to_fossil_ref)} #{Process.quote(SPEC_FILENAME)}").strip == SPEC_FILENAME
        raise Error.new "No #{SPEC_FILENAME} was found for shard #{name.inspect} at commit #{commit}"
      end

      spec_yaml = capture("fossil cat -R #{Process.quote(local_fossil_file)} #{Process.quote(SPEC_FILENAME)} -r #{Process.quote(ref.to_fossil_ref)}")
      begin
        Spec.from_yaml(spec_yaml)
      rescue error : Error
        raise Error.new "Invalid #{SPEC_FILENAME} for shard #{name.inspect} at commit #{commit}: #{error.message}"
      end
    end

    private def spec?(version)
      spec(version)
    rescue Error
    end

    def available_releases : Array(Version)
      update_local_cache
      versions_from_tags
    end

    def latest_version_for_ref(ref : FossilRef?) : Version
      update_local_cache
      ref ||= FossilTrunkRef.new
      begin
        commit = commit_sha1_at(ref)
      rescue Error
        raise Error.new "Could not find #{ref.full_info} for shard #{name.inspect} in the repository #{source}"
      end

      if spec = spec_at_ref(ref, commit)
        Version.new "#{spec.version.value}+fossil.commit.#{commit}"
      else
        raise Error.new "No #{SPEC_FILENAME} was found for shard #{name.inspect} at commit #{commit}"
      end
    end

    def matches_ref?(ref : FossilRef, version : Version)
      case ref
      when FossilCommitRef
        ref =~ fossil_ref(version)
      when FossilBranchRef, FossilTrunkRef
        # TODO: check if version is the branch
        version.has_metadata?
      else
        # TODO: check branch and tags
        true
      end
    end

    def available_tags : Array(String)
      capture("fossil tag list -R #{Process.quote(local_fossil_file)}")
        .lines.reject!(&.empty?)
    end

    protected def versions_from_tags
      available_tags.compact_map { |tag| Version.new($1) if tag =~ VERSION_TAG }
    end

    def install_sources(version : Version, install_path : String)
      update_local_cache
      ref = fossil_ref(version)

      FileUtils.rm_r(install_path) if File.exists?(install_path)
      Dir.mkdir_p(install_path)
      Log.debug { "Local path: #{local_path}" }
      Log.debug { "Install path: #{install_path}" }

      # The --workdir argument was introduced in version 2.12, so we have to
      # fake it
      if FossilResolver.fossil_version_maj <= 2 &&
         FossilResolver.fossil_version_min < 12
        Log.debug { "Opening Fossil repo #{local_fossil_file} in directory #{install_path}" }
        run("fossil open #{local_fossil_file} #{Process.quote(ref.to_fossil_ref)} --nested", install_path)
      else
        run "fossil open #{local_fossil_file} #{Process.quote(ref.to_fossil_ref)}  --nested --workdir #{install_path}"
      end
    end

    def commit_sha1_at(ref : FossilRef)
      # Fossil versions before 2.14 do not support the --format/-F for the
      # timeline command.
      if FossilResolver.fossil_version_maj <= 2 &&
         FossilResolver.fossil_version_min < 14
        # Capture the short artifact name from the timeline using a regex.
        # -W 0  = unlimited line width
        # -n 1  = limit results to one entry
        # -t ci = Display only checkins on the timeline
        shortShas = capture("fossil timeline #{Process.quote(ref.to_fossil_ref)} -t ci -W 0 -n 1 -R #{Process.quote(local_fossil_file)}")

        # We only want the lines with short artifact names
        retLines = shortShas.strip.split('\n').flat_map do |line|
          /^.+ \[(.+)\].*/.match(line).try &.[1]
        end

        # Remove empty results
        retLines.reject! &.nil?
        return "" if retLines.empty?

        # Call the whatis command so we can properly expand the short artifact
        # name to the full artifact hash.
        whatis = capture("fossil whatis #{retLines[0]} -R #{Process.quote(local_fossil_file)}")
        /artifact:\s+(.+)/.match(whatis).try &.[1] || ""
      else
        # Fossil v2.14 and newer support -F %H, so use that.
        capture("fossil timeline #{Process.quote(ref.to_fossil_ref)} -t ci -F %H -n 1 -R #{Process.quote(local_fossil_file)}").split('\n')[0]
      end
    end

    def local_path
      @local_path ||= begin
        uri = parse_uri(fossil_url)

        path = uri.path
        path = Path[path]
        # E.g. turns "c:\local\path.git" into "c\local\path.git". Or just drops the leading slash.
        if (anchor = path.anchor)
          path = Path[path.drive.to_s.rchop(":"), path.relative_to(anchor)]
        end

        if host = uri.host
          File.join(Shards.cache_path, host)
        else
          File.join(Shards.cache_path, path)
        end
      end
    end

    def local_fossil_file
      @local_fossil_file ||= Path[local_path].join("#{name}.fossil").normalize.to_s
    end

    def fossil_url
      source.strip
    end

    def parse_requirement(params : Hash(String, String)) : Requirement
      params.each do |key, value|
        case key
        when "branch"
          return FossilBranchRef.new value
        when "tag"
          return FossilTagRef.new value
        when "commit"
          return FossilCommitRef.new value
        else
        end
      end

      super
    end

    record FossilVersion, value : String, commit : String? = nil

    private def parse_fossil_version(version : Version) : FossilVersion
      case version.value
      when VERSION_REFERENCE
        FossilVersion.new version.value
      when VERSION_AT_FOSSIL_COMMIT
        FossilVersion.new $1, $2
      else
        raise Error.new("Invalid version for fossil resolver: #{version}")
      end
    end

    private def fossil_ref(version : Version) : FossilRef
      fossil_version = parse_fossil_version(version)
      if commit = fossil_version.commit
        FossilCommitRef.new commit
      else
        FossilTagRef.new "v#{fossil_version.value}"
      end
    end

    def update_local_cache
      if cloned_repository? && origin_changed?
        delete_repository
        @updated_cache = false
      end

      return if Shards.local? || @updated_cache
      Log.info { "Fetching #{fossil_url}" }

      if cloned_repository?
        # repositories cloned with shards v0.8.0 won't fetch any new remote
        # refs; we must delete them and clone again!
        if valid_repository?
          fetch_repository
        else
          delete_repository
          mirror_repository
        end
      else
        mirror_repository
      end

      @updated_cache = true
    end

    private def mirror_repository
      path = local_path
      fossil_file = Path[path].join("#{name}.fossil").to_s
      Dir.mkdir_p(path)
      FileUtils.rm(fossil_file) if File.exists?(fossil_file)

      source = fossil_url
      # Remove a "file://" from the beginning, otherwise the path might be invalid
      # on Windows.
      source = source.lchop("file://")

      fossil_retry(err: "Failed to clone #{source}") do
        run_in_current_folder "fossil clone #{Process.quote(source)} #{Process.quote(fossil_file)}"
      end
    end

    private def fetch_repository
      fossil_retry(err: "Failed to update #{fossil_url}") do
        run "fossil pull -R #{Process.quote(local_fossil_file)}"
      end
    end

    private def fossil_retry(err = "Failed to fetch repository", &)
      retries = 0
      loop do
        yield
        break
      rescue inner_err : Error
        retries += 1
        next if retries < 3
        Log.debug { inner_err }
        raise Error.new("#{err}: #{inner_err}")
      end
    end

    private def delete_repository
      Log.debug { "rm -rf #{Process.quote(local_path)}'" }
      Shards::Helpers.rm_rf(local_path)
      Log.debug { "rm -rf #{Process.quote(local_fossil_file)}'" }
      Shards::Helpers.rm_rf(local_fossil_file)
      @origin_url = nil
    end

    private def cloned_repository?
      # Check for both the local_path and the local_fossil_file, otherwise this
      # method can give false positives if it's looking for repositories from
      # the same base site.
      Dir.exists?(local_path) && File.exists?(local_fossil_file)
    end

    private def valid_repository?
      File.exists?(local_fossil_file)
    end

    protected def origin_url
      @origin_url ||= capture("fossil remote-url -R #{Process.quote(local_fossil_file)}").strip
    end

    # Returns whether origin URLs have differing hosts and/or paths.
    protected def origin_changed?
      return false if origin_url == fossil_url
      return true if origin_url.nil? || fossil_url.nil?

      origin_parsed = parse_uri(origin_url)
      fossil_parsed = parse_uri(fossil_url)

      (origin_parsed.host != fossil_parsed.host) || (origin_parsed.path != fossil_parsed.path)
    end

    # Parses a URI string
    private def parse_uri(raw_uri)
      # Need to check for file URIs early, otherwise generic parsing will fail on a colon.
      if (path = raw_uri.lchop?("file://"))
        return URI.new(scheme: "file", path: path)
      end

      # Try normal URI parsing first
      uri = URI.parse(raw_uri)
      return uri if uri.absolute? && !uri.opaque?

      # Otherwise, assume and attempt to parse the scp-style ssh URIs
      host, _, path = raw_uri.partition(':')

      if host.includes?('@')
        user, _, host = host.partition('@')
      end

      # Normalize leading slash, matching URI parsing
      unless path.starts_with?('/')
        path = '/' + path
      end

      URI.new(scheme: "ssh", host: host, path: path, user: user)
    end

    private def file_exists?(ref : FossilRef, path)
      files = capture("fossil ls -R #{Process.quote(local_fossil_file)} -r #{Process.quote(ref.to_fossil_ref)} #{Process.quote(path)}")
      !files.strip.empty?
    end

    private def capture(command, path = local_path)
      run(command, capture: true, path: path).not_nil!
    end

    private def run(command, path = local_path, capture = false)
      if Shards.local? && !Dir.exists?(path)
        dependency_name = File.basename(path, ".fossil")
        raise Error.new("Missing repository cache for #{dependency_name.inspect}. Please run without --local to fetch it.")
      end
      Dir.cd(path) do
        run_in_current_folder(command, capture)
      end
    end

    private def run_in_current_folder(command, capture = false)
      unless FossilResolver.has_fossil_command?
        raise Error.new("Error missing fossil command line tool. Please install Fossil first!")
      end

      Log.debug { command }

      STDERR.flush
      output = capture ? IO::Memory.new : Process::Redirect::Close
      error = IO::Memory.new
      status = Process.run(command, shell: true, output: output, error: error)

      if status.success?
        output.to_s if capture
      else
        message = error.to_s
        raise Error.new("Failed #{command} (#{message}). Maybe a commit, branch or file doesn't exist?")
      end
    end

    def report_version(version : Version) : String
      fossil_version = parse_fossil_version(version)
      if commit = fossil_version.commit
        "#{fossil_version.value} at #{commit[0...7]}"
      else
        version.value
      end
    end

    register_resolver "fossil", FossilResolver
  end
end
