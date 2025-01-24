require "../lock"
require "../spec"
require "../override"
require "levenshtein"

module Shards
  abstract class Command
    getter path : String
    getter spec_path : String
    getter lockfile_path : String
    getter override_path : String?

    @spec : Spec?
    @locks : Lock?
    @override : Override?

    def initialize(path)
      if File.directory?(path)
        @path = path
        @spec_path = File.join(path, SPEC_FILENAME)
      else
        @path = File.dirname(path)
        @spec_path = path
      end
      @lockfile_path = File.join(@path, LOCK_FILENAME)

      # If global override is defined via SHARDS_OVERRIDE env var we use that.
      # Otherwise we check if the is a shard.override.yml file next to the shard.yml
      @override_path = Shards.global_override_filename
      unless @override_path
        local_override = File.join(@path, OVERRIDE_FILENAME)
        @override_path = File.exists?(local_override) ? local_override : nil
      end
    end

    def self.run(path, *args, **kwargs)
      new(path).run(*args, **kwargs)
    end

    def spec
      @spec ||= if File.exists?(spec_path)
                  Spec.from_file(spec_path)
                else
                  raise Error.new("Missing #{spec_filename}. Please run 'shards init'")
                end
    end

    def spec_filename
      File.basename(spec_path)
    end

    def locks
      @locks ||= if lockfile?
                   Shards::Lock.from_file(lockfile_path)
                 else
                   raise Error.new("Missing #{LOCK_FILENAME}. Please run 'shards install'")
                 end
    end

    def lockfile?
      File.exists?(lockfile_path)
    end

    def override
      @override ||= override_path.try { |p| Shards::Override.from_file(p) }
    end

    def write_lockfile(packages)
      Log.info { "Writing #{LOCK_FILENAME}" }

      override_path = @override_path
      override_path = File.basename(override_path) if override_path && File.dirname(override_path) == @path

      Shards::Lock.write(packages, override_path, LOCK_FILENAME)
    end

    private def log_available_tags(conflicts)
      String.build do |str|
        shard_source_dependencys = conflicts.flat_map { |k, v| v.requirements.flat_map { |source, deps| deps.map { |dep| {k, source, dep} } } }
        if shard_source_dependencys.size > 1
          str << "Unable to satisfy the following requirements:\n\n"
          shard_source_dependencys.each do |shard, source, dependency|
            str << "- `#{shard} (#{dependency.requirement})` required by `#{source}`\n"
          end
        else
          str << "Unable to satisfy the following requirement:\n\n"
          shard_source_dependencys.each do |shard, source, dependency|
            resolver = dependency.resolver
            tags = resolver.available_tags.reverse!.first(5)
            releases = resolver.available_releases.map(&.to_s).reverse
            req = dependency.requirement

            str << "- `#{shard} (#{req})` required by `#{source}`: "
            if releases.empty?
              str << "It doesn't have any release. "
              if tags.empty?
                str << "And it doesn't have any tags either."
              else
                str << "These are the latest tags: #{tags.join(", ")}."
              end
            elsif req.is_a?(Version) || (req.is_a?(VersionReq) && req.patterns.size == 1 && req.patterns[0] !~ /^(<|>|=)/)
              req = req.to_s
              found = Levenshtein.find(req, releases, 6) || "none"
              info = "These are the latest tags: #{tags.join(", ")}."
              str << "The closest available release to #{req} is: #{found}. #{info}"
            else
              str << "The last available releases are #{releases.first(5).join(", ")}."
            end
            str << "\n"
          end
        end
      end
    end

    def handle_resolver_errors(solver, &)
      yield
    rescue e : Molinillo::VersionConflict(Shards::Dependency, Shards::Spec)
      Log.error { log_available_tags(e.conflicts) }
      raise Shards::Error.new("Failed to resolve dependencies")
    rescue e : Molinillo::ResolverError
      Log.error { e.message }
      raise Shards::Error.new("Failed to resolve dependencies")
    end

    def check_crystal_version(packages)
      crystal_version = Shards::Version.new Shards.crystal_version

      packages.each do |package|
        crystal_req = MolinilloSolver.crystal_version_req(package.spec)

        if !Shards::Versions.matches?(crystal_version, crystal_req)
          Log.warn { "Shard \"#{package.name}\" may be incompatible with Crystal #{Shards.crystal_version}" }
        end
      end
    end

    def check_symlink_privilege
      {% if flag?(:win32) %}
        return if Shards::Helpers.developer_mode?
        return if Shards::Helpers.privilege_enabled?("SeCreateSymbolicLinkPrivilege")

        raise Shards::Error.new(<<-EOS)
        Shards needs symlinks to work. Please enable Developer Mode, or run Shards with elevated rights:
            https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development
        EOS
      {% end %}
    end

    def touch_install_path
      Dir.mkdir_p(Shards.install_path)
      File.touch(Shards.install_path)
    end
  end
end
