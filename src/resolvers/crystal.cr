module Shards
  class CrystalResolver < Resolver
    INSTANCE = new("crystal", "")

    def self.key
      "crystal"
    end

    def available_releases : Array(Version)
      [Version.new Shards.crystal_version]
    end

    def available_tags : Array(String)
      [Shards.crystal_version]
    end

    def read_spec(version : Version) : String?
      nil
    end

    def install_sources(version : Version, install_path : String)
      raise NotImplementedError.new("CrystalResolver#install_sources")
    end

    def report_version(version : Version) : String
      version.value
    end
  end
end
