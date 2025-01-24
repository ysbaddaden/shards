require "./spec_helper"

module Molinillo
  describe ResolutionState do
    describe DependencyState do
      it "pops a possibility state" do
        possibility1 = Resolver::Resolution::PossibilitySet(String, String).new(%w(), %w(possibility1))
        possibility = Resolver::Resolution::PossibilitySet(String, String).new(%w(), %w(possibility))
        state = DependencyState(String, String).new(
          "name",
          %w(requirement1 requirement2 requirement3),
          DependencyGraph(Resolver::Resolution::PossibilitySet(String, String) | String | Nil, String).new,
          "requirement",
          [possibility1, possibility],
          0,
          {} of String => Resolver::Resolution::Conflict(String, String),
          [] of Resolver::Resolution::UnwindDetails(String, String)
        )
        possibility_state = state.pop_possibility_state
        {% for attr in %w(name requirements activated requirement conflicts) %}
          possibility_state.{{ attr.id }}.should eq(state.{{ attr.id }})
        {% end %}
        possibility_state.should be_a(PossibilityState(String, String))
        possibility_state.depth.should eq(state.depth + 1)
        possibility_state.possibilities.should eq([possibility])
      end
    end
  end
end
