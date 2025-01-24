require "file_utils"
require "../spec"
require "../dependency"
require "../errors"
require "../script"

module Shards
  abstract class Resolver
    getter name : String
    getter source : String

    def initialize(@name : String, @source : String)
    end

    def self.build(key : String, name : String, source : String)
      _, source = self.normalize_key_source(key, source)
      self.new(name, source)
    end

    def self.normalize_key_source(key : String, source : String)
      {key, source}
    end

    def ==(other : Resolver)
      return true if super
      return false unless self.class == other.class
      name == other.name && source == other.source
    end

    def yaml_source_entry
      "#{self.class.key}: #{source}"
    end

    def to_s(io : IO)
      io << yaml_source_entry
    end

    def versions_for(req : Requirement) : Array(Version)
      case req
      when Version then [req]
      when Ref
        [latest_version_for_ref(req)]
      when VersionReq
        Versions.resolve(available_releases, req)
      when Any
        releases = available_releases
        if releases.empty?
          [latest_version_for_ref(nil)]
        else
          releases
        end
      else
        raise Error.new("Unexpected requirement type: #{req}")
      end
    end

    abstract def available_tags : Array(String)

    abstract def available_releases : Array(Version)

    def latest_version_for_ref(ref : Ref?) : Version
      raise "Unsupported ref type for this resolver: #{ref}"
    end

    def matches_ref?(ref : Ref, version : Version)
      false
    end

    def spec(version : Version) : Spec
      if spec = load_spec(version)
        spec.version = version
        spec
      else
        Spec.new(name, version, self)
      end
    end

    private def load_spec(version)
      if spec_yaml = read_spec(version)
        Spec.from_yaml(spec_yaml).tap do |spec|
          spec.resolver = self
        end
      end
    rescue error : ParseError
      error.resolver = self
      raise error
    end

    abstract def read_spec(version : Version) : String?
    abstract def install_sources(version : Version, install_path : String)
    abstract def report_version(version : Version) : String

    def update_local_cache
    end

    def parse_requirement(params : Hash(String, String)) : Requirement
      if version = params["version"]?
        VersionReq.new version
      else
        Any
      end
    end

    private record ResolverCacheKey, key : String, name : String, source : String
    private RESOLVER_CLASSES = {} of String => Resolver.class
    private RESOLVER_CACHE   = {} of ResolverCacheKey => Resolver

    def self.register_resolver(key, resolver)
      RESOLVER_CLASSES[key] = resolver
    end

    def self.clear_resolver_cache
      RESOLVER_CACHE.clear
    end

    def self.find_class(key : String) : Resolver.class | Nil
      RESOLVER_CLASSES[key]?
    end

    def self.find_resolver(key : String, name : String, source : String)
      resolver_class =
        if self == Resolver
          RESOLVER_CLASSES[key]? ||
            raise Error.new("Failed can't resolve dependency #{name} (unsupported resolver)")
        else
          self
        end

      key, source = resolver_class.normalize_key_source(key, source)

      RESOLVER_CACHE[ResolverCacheKey.new(key, name, source)] ||= begin
        resolver_class.build(key, name, source)
      end
    end
  end
end

require "./*"
