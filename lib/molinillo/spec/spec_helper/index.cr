require "./specification"

module Molinillo
  FIXTURE_INDEX_DIR = FIXTURE_DIR / "index"

  class TestIndex
    getter specs : Hash(String, Array(TestSpecification))
    include SpecificationProvider(Gem::Dependency | TestSpecification, TestSpecification)

    def self.from_fixture(fixture_name)
      new(TestIndex.specs_from_fixture(fixture_name))
    end

    @@specs_from_fixture = {} of String => Hash(String, Array(TestSpecification))

    def self.specs_from_fixture(fixture_name)
      @@specs_from_fixture[fixture_name] ||= begin
        lines = File.read_lines(FIXTURE_INDEX_DIR / (fixture_name + ".json"))
        lines = lines.map { |line| line.partition("//")[0] }
        Hash(String, Array(TestSpecification)).from_json(lines.join '\n').tap do |all_specs|
          all_specs.each do |name, specs|
            specs.sort! { |a, b| Shards::Versions.compare(b.version, a.version) }
          end
        end
      end
    end

    def initialize(@specs)
    end

    def requirement_satisfied_by?(requirement, activated, spec)
      if Shards::Versions.prerelease?(spec.version) && !requirement.prerelease?
        vertex = activated.vertex_named!(spec.name)
        return false if vertex.requirements.none?(&.prerelease?)
      end

      case requirement
      when TestSpecification
        requirement.version == spec.version
      when Gem::Dependency
        requirement.requirement.satisfied_by?(spec.version)
      end
    end

    def search_for(dependency : R)
      case dependency
      when Gem::Dependency
        specs.fetch(dependency.name) { Array(TestSpecification).new }.select do |spec|
          dependency.requirement.satisfied_by?(spec.version)
        end
      else
        raise "BUG: Unexpected dependency type: #{dependency}"
      end
    end

    def name_for(dependency)
      dependency.name
    end

    def dependencies_for(specification : S)
      specification.dependencies
    end
  end
end
