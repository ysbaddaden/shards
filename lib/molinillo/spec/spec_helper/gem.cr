module Gem
  class Dependency
    property name : String
    property requirement : Requirement

    def initialize(@name, requirements : Array(String))
      @requirement = Requirement.new(requirements)
    end

    def prerelease?
      requirement.prerelease?
    end

    def to_s(io)
      io << name
    end
  end

  class Requirement
    property requirements : Array(String)

    def initialize(@requirements)
    end

    def satisfied_by?(version : String)
      requirements.all? do |req|
        Shards::Versions.matches?(version, req)
      end
    end

    def prerelease?
      requirements.any? { |r| Shards::Versions.prerelease?(r) }
    end

    def inspect(io)
      io << '"'
      io << requirements.join ", "
      io << '"'
    end
  end
end
