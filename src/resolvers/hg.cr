require "uri"
require "./resolver"
require "../versions"
require "../logger"
require "../helpers"

module Shards
  abstract struct HgRef < Ref
    def full_info
      to_s
    end
  end

  struct HgBranchRef < HgRef
    def initialize(@branch : String)
    end

    def to_hg_ref
      @branch
    end

    def to_hg_revset
      "branch(\"#{@branch}\") and head()"
    end

    def to_s(io)
      io << "branch " << @branch
    end

    def to_yaml(yaml)
      yaml.scalar "branch"
      yaml.scalar @branch
    end
  end

  struct HgBookmarkRef < HgRef
    def initialize(@bookmark : String)
    end

    def to_hg_ref
      @bookmark
    end

    def to_hg_revset
      "bookmark(\"#{@bookmark}\")"
    end

    def to_s(io)
      io << "bookmark " << @bookmark
    end

    def to_yaml(yaml)
      yaml.scalar "bookmark"
      yaml.scalar @bookmark
    end
  end

  struct HgTagRef < HgRef
    def initialize(@tag : String)
    end

    def to_hg_ref
      @tag
    end

    def to_hg_revset
      "tag(\"#{@tag}\")"
    end

    def to_s(io)
      io << "tag " << @tag
    end

    def to_yaml(yaml)
      yaml.scalar "tag"
      yaml.scalar @tag
    end
  end

  struct HgCommitRef < HgRef
    getter commit : String

    def initialize(@commit : String)
    end

    def =~(other : HgCommitRef)
      commit.starts_with?(other.commit) || other.commit.starts_with?(commit)
    end

    def to_hg_ref
      @commit
    end

    def to_hg_revset
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

  struct HgCurrentRef < HgRef
    def to_hg_revset
      "."
    end

    def to_hg_ref
      "."
    end

    def to_s(io)
      io << "current"
    end

    def to_yaml(yaml)
      raise NotImplementedError.new("HgCurrentRef is for internal use only")
    end
  end

  class HgResolver < Resolver
    @@has_hg_command : Bool?
    @@hg_version : String?

    @origin_url : String?

    def self.key
      "hg"
    end

    def self.normalize_key_source(key : String, source : String) : {String, String}
      case key
      when "hg"
        {"hg", source}
      else
        raise "Unknown resolver #{key}"
      end
    end

    protected def self.has_hg_command?
      if @@has_hg_command.nil?
        @@has_hg_command = (Process.run("hg", ["--version"]).success? rescue false)
      end
      @@has_hg_command
    end

    protected def self.hg_version
      @@hg_version ||= `hg --version`[/\(version\s+([^)]*)\)/, 1]
    end

    def read_spec(version : Version) : String?
      update_local_cache
      ref = hg_ref(version)

      if file_exists?(ref, SPEC_FILENAME)
        capture("hg cat -r #{Process.quote(ref.to_hg_revset)} #{Process.quote(SPEC_FILENAME)}")
      else
        Log.debug { "Missing \"#{SPEC_FILENAME}\" for #{name.inspect} at #{ref}" }
        nil
      end
    end

    private def spec_at_ref(ref : HgRef) : Spec?
      update_local_cache
      begin
        if file_exists?(ref, SPEC_FILENAME)
          spec_yaml = capture("hg cat -r #{Process.quote(ref.to_hg_revset)} #{Process.quote(SPEC_FILENAME)}")
          Spec.from_yaml(spec_yaml)
        end
      rescue Error
        nil
      end
    end

    private def spec?(version)
      spec(version)
    rescue Error
    end

    def available_tags : Array(String)
      tags = capture("hg tags --template #{Process.quote("{tag}\n")}")
        .lines
        .sort!

      tags.reject!(&.empty?)
    end

    def available_releases : Array(Version)
      update_local_cache
      versions_from_tags
    end

    def latest_version_for_ref(ref : HgRef?) : Version
      update_local_cache
      ref ||= HgCurrentRef.new
      begin
        commit = commit_sha1_at(ref)
      rescue Error
        raise Error.new "Could not find #{ref.full_info} for shard #{name.inspect} in the repository #{source}"
      end

      if spec = spec_at_ref(ref)
        Version.new "#{spec.version.value}+hg.commit.#{commit}"
      else
        raise Error.new "No #{SPEC_FILENAME} was found for shard #{name.inspect} at commit #{commit}"
      end
    end

    def matches_ref?(ref : HgRef, version : Version)
      case ref
      when HgCommitRef
        ref =~ hg_ref(version)
      when HgBranchRef, HgBookmarkRef, HgCurrentRef
        # TODO: check if version is the branch
        version.has_metadata?
      else
        # TODO: check branch and tags
        true
      end
    end

    protected def versions_from_tags
      tags = capture("hg tags --template #{Process.quote("{tag}\n")}")
        .lines
        .sort!

      tags.compact_map { |tag| Version.new($1) if tag =~ VERSION_TAG }
    end

    def install_sources(version : Version, install_path : String)
      update_local_cache
      ref = hg_ref(version)

      FileUtils.rm_r(install_path) if File.exists?(install_path)
      Dir.mkdir_p(install_path)
      run "hg clone --quiet -u #{Process.quote(ref.to_hg_ref)} -- #{Process.quote(local_path)} #{Process.quote(install_path)}"
    end

    def commit_sha1_at(ref : HgRef)
      capture("hg log -r #{Process.quote(ref.to_hg_revset)} --template #{Process.quote("{node}\n")}").strip
    end

    def local_path
      @local_path ||= begin
        uri = parse_uri(hg_url)

        path = uri.path
        path = Path[path]
        # E.g. turns "c:\local\path" into "c\local\path". Or just drops the leading slash.
        if (anchor = path.anchor)
          path = Path[path.drive.to_s.rchop(":"), path.relative_to(anchor)]
        end

        if host = uri.host
          File.join(Shards.cache_path, host, path)
        else
          File.join(Shards.cache_path, path)
        end
      end
    end

    def hg_url
      source.strip
    end

    def parse_requirement(params : Hash(String, String)) : Requirement
      params.each do |key, value|
        case key
        when "branch"
          return HgBranchRef.new value
        when "bookmark"
          return HgBookmarkRef.new value
        when "tag"
          return HgTagRef.new value
        when "commit"
          return HgCommitRef.new value
        end
      end

      super
    end

    record HgVersion, value : String, commit : String? = nil

    private def parse_hg_version(version : Version) : HgVersion
      case version.value
      when VERSION_REFERENCE
        HgVersion.new version.value
      when VERSION_AT_HG_COMMIT
        HgVersion.new $1, $2
      else
        raise Error.new("Invalid version for hg resolver: #{version}")
      end
    end

    private def hg_ref(version : Version) : HgRef
      hg_version = parse_hg_version(version)
      if commit = hg_version.commit
        HgCommitRef.new commit
      else
        HgTagRef.new "v#{hg_version.value}"
      end
    end

    def update_local_cache
      if cloned_repository? && origin_changed?
        delete_repository
        @updated_cache = false
      end

      return if Shards.local? || @updated_cache
      Log.info { "Fetching #{hg_url}" }

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
      FileUtils.rm_r(path) if File.exists?(path)
      Dir.mkdir_p(path)

      source = hg_url
      # Remove a "file://" from the beginning, otherwise the path might be invalid
      # on Windows.
      source = source.lchop("file://")

      hg_retry(err: "Failed to clone #{source}") do
        # We checkout the working directory so that "." is meaningful.
        #
        # An alternative would be to use the `@` bookmark, but only as long
        # as nothing new is committed.
        run_in_current_folder "hg clone --quiet -- #{Process.quote(source)} #{Process.quote(path)}"
      end
    end

    private def fetch_repository
      hg_retry(err: "Failed to update #{hg_url}") do
        run "hg pull"
      end
    end

    private def hg_retry(err = "Failed to update repository", &)
      retries = 0
      loop do
        return yield
      rescue ex : Error
        retries += 1
        next if retries < 3
        raise Error.new("#{err}: #{ex}")
      end
    end

    private def delete_repository
      Log.debug { "rm -rf #{Process.quote(local_path)}" }
      Shards::Helpers.rm_rf(local_path)
      @origin_url = nil
    end

    private def cloned_repository?
      Dir.exists?(local_path)
    end

    private def valid_repository?
      File.exists?(File.join(local_path, ".hg", "dirstate"))
    end

    private def origin_url
      @origin_url ||= capture("hg paths default").strip
    end

    # Returns whether origin URLs have differing hosts and/or paths.
    protected def origin_changed?
      return false if origin_url == hg_url
      return true if origin_url.nil? || hg_url.nil?

      origin_parsed = parse_uri(origin_url)
      hg_parsed = parse_uri(hg_url)

      (origin_parsed.host != hg_parsed.host) || (origin_parsed.path != hg_parsed.path)
    end

    # Parses a URI string, with additional support for ssh+git URI schemes.
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

    private def file_exists?(ref : HgRef, path)
      run("hg files -r #{Process.quote(ref.to_hg_revset)} -- #{Process.quote(path)}", raise_on_fail: false)
    end

    private def capture(command, path = local_path)
      run(command, capture: true, path: path).as(String)
    end

    private def run(command, path = local_path, capture = false, raise_on_fail = true)
      if Shards.local? && !Dir.exists?(path)
        dependency_name = File.basename(path)
        raise Error.new("Missing repository cache for #{dependency_name.inspect}. Please run without --local to fetch it.")
      end
      Dir.cd(path) do
        run_in_current_folder(command, capture, raise_on_fail: raise_on_fail)
      end
    end

    private def run_in_current_folder(command, capture = false, raise_on_fail = true)
      unless HgResolver.has_hg_command?
        raise Error.new("Error missing hg command line tool. Please install Mercurial first!")
      end

      Log.debug { command }

      output = capture ? IO::Memory.new : Process::Redirect::Close
      error = IO::Memory.new
      status = Process.run(command, shell: true, output: output, error: error)

      if status.success?
        if capture
          output.to_s
        else
          true
        end
      elsif raise_on_fail
        str = error.to_s
        if str.starts_with?("abort: ") && (idx = str.index('\n'))
          message = str[7...idx]
          raise Error.new("Failed #{command} (#{message}). Maybe a commit, branch, bookmark or file doesn't exist?")
        else
          raise Error.new("Failed #{command}.\n#{str}")
        end
      end
    end

    def report_version(version : Version) : String
      hg_version = parse_hg_version(version)
      if commit = hg_version.commit
        "#{hg_version.value} at #{commit[0...7]}"
      else
        version.value
      end
    end

    register_resolver "hg", HgResolver
  end
end
