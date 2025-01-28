require "uri"
require "./version_control"
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

  class HgResolver < VersionControlResolver
    @@extension = ""

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

    protected def self.command?
      if @@command.nil?
        @@command = (Process.run("hg", ["--version"]).success? rescue false)
      end
      @@command
    end

    protected def self.version
      @@version ||= `hg --version`[/\(version\s+([^)]*)\)/, 1]
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
      capture("hg tags --template #{Process.quote("{tag}\n")}")
        .lines
        .sort!
        .compact_map { |tag| Version.new($1) if tag =~ VERSION_TAG }
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
        uri = parse_uri(vcs_url)

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

    private def parse_version(version : Version) : HgVersion
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
      version = parse_version(version)
      if commit = version.commit
        HgCommitRef.new commit
      else
        HgTagRef.new "v#{version.value}"
      end
    end

    private def mirror_repository
      path = local_path
      FileUtils.rm_r(path) if File.exists?(path)
      Dir.mkdir_p(path)

      source = vcs_url
      # Remove a "file://" from the beginning, otherwise the path might be invalid
      # on Windows.
      source = source.lchop("file://")

      vcs_retry(err: "Failed to clone #{source}") do
        # We checkout the working directory so that "." is meaningful.
        #
        # An alternative would be to use the `@` bookmark, but only as long
        # as nothing new is committed.
        run_in_folder "hg clone --quiet -- #{Process.quote(source)} #{Process.quote(path)}"
      end
    end

    private def fetch_repository
      vcs_retry(err: "Failed to update #{vcs_url}") do
        run "hg pull"
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

    private def file_exists?(ref : HgRef, path)
      run("hg files -r #{Process.quote(ref.to_hg_revset)} -- #{Process.quote(path)}", raise_on_fail: false)
    end

    private def error_if_command_is_missing
      unless HgResolver.command?
        raise Error.new("Error missing hg command line tool. Please install Mercurial first!")
      end
    end

    private def error_for_run_failure(command, str : String)
      if str.starts_with?("abort: ") && (idx = str.index('\n'))
        message = str[7...idx]
        raise Error.new("Failed #{command} (#{message}). Maybe a commit, branch, bookmark or file doesn't exist?")
      else
        raise Error.new("Failed #{command}.\n#{str}")
      end
    end

    register_resolver "hg", HgResolver
  end
end
