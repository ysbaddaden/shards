require "./spec_helper"

module Molinillo
  FIXTURE_CASE_DIR = FIXTURE_DIR / "case"

  class TestCase
    getter fixture : Fixture
    getter name : String
    @index : SpecificationProvider(Gem::Dependency | TestSpecification, TestSpecification)?
    @requested : Array(Gem::Dependency | TestSpecification)?
    @result : DependencyGraph(TestSpecification?, TestSpecification?)?
    @conflicts : Set(String)?
    @@all : Array(TestCase)?

    def self.from_fixture(fixture_path)
      fixture = File.open(fixture_path) { |f| Fixture.from_json(f) }
      new(fixture)
    end

    def initialize(@fixture)
      @name = fixture.name
    end

    def index
      @index ||= TestIndex.from_fixture(@fixture.index || "awesome")
    end

    def requested
      @requested ||= @fixture.requested.map do |(name, reqs)|
        Gem::Dependency.new(name.delete("\x01"), reqs.split(',').map(&.chomp)).as(Gem::Dependency | TestSpecification)
      end
    end

    def add_dependencies_to_graph(graph : DependencyGraph(P, P), parent, hash, all_parents = Set(DependencyGraph::Vertex(P, P)).new) forall P
      name = hash.name
      version = hash.version # Gem::Version.new(hash['version'])
      dependency = index.specs[name].find { |s| Shards::Versions.compare(s.version, version) == 0 }.not_nil!
      vertex = if parent
                 graph.add_vertex(name, dependency).tap do |v|
                   graph.add_edge(parent, v, dependency)
                 end
               else
                 graph.add_vertex(name, dependency, true)
               end
      return unless all_parents.add?(vertex)
      hash.dependencies.each do |dep|
        add_dependencies_to_graph(graph, vertex, dep, all_parents)
      end
    end

    def result
      @result ||= @fixture.resolved.reduce(DependencyGraph(TestSpecification?, TestSpecification?).new) do |graph, r|
        graph.tap do |g|
          add_dependencies_to_graph(g, nil, r)
        end
      end
    end

    def base
      @fixture.base.reduce(DependencyGraph(Gem::Dependency | TestSpecification, Gem::Dependency | TestSpecification).new) do |graph, r|
        graph.tap do |g|
          add_dependencies_to_graph(g, nil, r)
        end
      end
    end

    def conflicts
      @conflicts ||= @fixture.conflicts.to_set
    end

    def self.all
      @@all ||= Dir.glob(FIXTURE_CASE_DIR.to_s + "**/*.json").map { |fixture| TestCase.from_fixture(fixture) }
    end

    def resolve(index_class)
      index = index_class.new(self.index.specs)
      resolver = Resolver(Gem::Dependency | TestSpecification, TestSpecification).new(index, TestUI.new)
      resolver.resolve(requested, base)
    end

    def run(index_class)
      it name do
        # skip 'does not yet reliably pass' if test_case.ignore?(index_class)
        if fixture.conflicts.any?
          error = expect_raises(ResolverError) { resolve(index_class) }
          names = case error
                  when CircularDependencyError
                    error.vertices.map &.name
                  when VersionConflict
                    error.conflicts.keys
                  else
                    fail "Unexpected error type: #{error}"
                  end.to_set
          names.should eq(self.conflicts)
        else
          result = resolve(index_class)

          result.should eq(self.result)
        end
      end
    end
  end

  describe Resolver do
    describe "dependency resolution" do
      describe "with the TestIndex index" do
        TestCase.all.each &.run(TestIndex)
      end
    end
  end
end

# it "list all cases" do
#   pp Molinillo::TestCase.all
# end
