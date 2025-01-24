require "./delegates/*"

module Molinillo
  class Resolver(R, S)
    # A specific resolution from a given {Resolver}
    class Resolution(R, S)
      # A conflict that the resolution process encountered
      # @attr [Object] requirement the requirement that immediately led to the conflict
      # @attr [{String,Nil=>[Object]}] requirements the requirements that caused the conflict
      # @attr [Object, nil] existing the existing spec that was in conflict with
      #   the {#possibility}
      # @attr [Object] possibility_set the set of specs that was unable to be
      #   activated due to a conflict.
      # @attr [Object] locked_requirement the relevant locking requirement.
      # @attr [Array<Array<Object>>] requirement_trees the different requirement
      #   trees that led to every requirement for the conflicting name.
      # @attr [{String=>Object}] activated_by_name the already-activated specs.
      # @attr [Object] underlying_error an error that has occurred during resolution, and
      #    will be raised at the end of it if no resolution is found.
      class Conflict(R, S)
        getter requirement : R
        getter requirements : Hash(String | S, Array(R))
        getter existing : S?
        getter possibility_set : PossibilitySet(R, S)?
        getter locked_requirement : R?
        getter requirement_trees : Array(Array(R))
        getter activated_by_name : Hash(String, S)
        getter underlying_error : Exception?

        def initialize(@requirement, @requirements, @existing, @possibility_set,
                       @locked_requirement, @requirement_trees, @activated_by_name, @underlying_error)
        end

        # @return [Object] a spec that was unable to be activated due to a conflict
        def possibility
          if s = possibility_set
            s.latest_version
          end
        end
      end

      # A collection of possibility states that share the same dependencies
      class PossibilitySet(R, S)
        # @attr [Array] dependencies the dependencies for this set of possibilities
        getter dependencies : Array(R)
        # @attr [Array] possibilities the possibilities
        getter possibilities : Array(S)

        def initialize(@dependencies, @possibilities)
        end

        # String representation of the possibility set, for debugging
        def to_s(io)
          io << "[#{possibilities.join(", ")}]"
        end

        # @return [Object] most up-to-date dependency in the possibility set
        def latest_version
          possibilities.last
        end

        def latest_version?
          possibilities.last?
        end
      end

      # Details of the state to unwind to when a conflict occurs, and the cause of the unwind
      # @attr [Integer] state_index the index of the state to unwind to
      # @attr [Object] state_requirement the requirement of the state we're unwinding to
      # @attr [Array] requirement_tree for the requirement we're relaxing
      # @attr [Array] conflicting_requirements the requirements that combined to cause the conflict
      # @attr [Array] requirement_trees for the conflict
      # @attr [Array] requirements_unwound_to_instead array of unwind requirements that were chosen over this unwind
      class UnwindDetails(R, S)
        getter state_index : Int32
        getter state_requirement : R?
        getter requirement_tree : Array(R)
        getter conflicting_requirements : Array(R)
        getter requirement_trees : Array(Array(R))
        getter requirements_unwound_to_instead : Array(R?)

        include Comparable(UnwindDetails(R, S))

        def initialize(@state_index, @state_requirement, @requirement_tree,
                       @conflicting_requirements, @requirement_trees, @requirements_unwound_to_instead)
        end

        # We compare UnwindDetails when choosing which state to unwind to. If
        # two options have the same state_index we prefer the one most
        # removed from a requirement that caused the conflict. Both options
        # would unwind to the same state, but a `grandparent` option will
        # filter out fewer of its possibilities after doing so - where a state
        # is both a `parent` and a `grandparent` to requirements that have
        # caused a conflict this is the correct behaviour.
        # @param [UnwindDetail] other UnwindDetail to be compared
        # @return [Integer] integer specifying ordering
        def <=>(other)
          if state_index > other.state_index
            1
          elsif state_index == other.state_index
            reversed_requirement_tree_index <=> other.reversed_requirement_tree_index
          else
            -1
          end
        end

        # @return [Integer] index of state requirement in reversed requirement tree
        #    (the conflicting requirement itself will be at position 0)
        def reversed_requirement_tree_index
          @reversed_requirement_tree_index ||=
            if state_requirement
              requirement_tree.reverse.index(state_requirement).not_nil!
            else
              999_999
            end
        end

        # @return [Boolean] where the requirement of the state we're unwinding
        #    to directly caused the conflict. Note: in this case, it is
        #    impossible for the state we're unwinding to to be a parent of
        #    any of the other conflicting requirements (or we would have
        #    circularity)
        def unwinding_to_primary_requirement?
          requirement_tree.last == state_requirement
        end

        @requirements_to_avoid : Array(R)?

        # @return [Array] array of sub-dependencies to avoid when choosing a
        #    new possibility for the state we've unwound to. Only relevant for
        #    non-primary unwinds
        def sub_dependencies_to_avoid
          @requirements_to_avoid ||=
            requirement_trees.map do |tree|
              index = tree.index(state_requirement)
              tree[index + 1] if index
            end.compact
        end

        @all_requirements : Array(R)?

        # @return [Array] array of all the requirements that led to the need for
        #    this unwind
        def all_requirements
          @all_requirements ||= requirement_trees.flatten
        end
      end

      # @return [SpecificationProvider] the provider that knows about
      #   dependencies, requirements, specifications, versions, etc.
      getter specification_provider : SpecificationProvider(R, S)

      # @return [UI] the UI that knows how to communicate feedback about the
      #   resolution process back to the user
      getter resolver_ui : UI

      # @return [DependencyGraph] the base dependency graph to which
      #   dependencies should be 'locked'
      getter base : DependencyGraph(R, R)

      # @return [Array] the dependencies that were explicitly required
      getter original_requested : Array(R)

      # Initializes a new resolution.
      # @param [SpecificationProvider] specification_provider
      #   see {#specification_provider}
      # @param [UI] resolver_ui see {#resolver_ui}
      # @param [Array] requested see {#original_requested}
      # @param [DependencyGraph] base see {#base}
      def initialize(specification_provider, resolver_ui, requested, base)
        @specification_provider = specification_provider
        @resolver_ui = resolver_ui
        @original_requested = requested
        @base = base
        @states = Array(ResolutionState(R, S)).new
        @iteration_counter = 0
        @parents_of = Hash(R, Array(Int32)).new { |h, k| h[k] = [] of Int32 }
      end

      # Resolves the {#original_requested} dependencies into a full dependency
      #   graph
      # @raise [ResolverError] if successful resolution is impossible
      # @return [DependencyGraph] the dependency graph of successfully resolved
      #   dependencies
      def resolve
        start_resolution

        while st = state
          break if !st.requirement && st.requirements.empty?
          indicate_progress
          if st.is_a?(DependencyState) # DependencyState
            debug(depth) { "Creating possibility state for #{requirement} (#{possibilities.size} remaining)" }
            st.pop_possibility_state.tap do |s|
              if s
                states.push(s)
                activated.tag(s)
              end
            end
          end
          process_topmost_state
        end

        resolve_activated_specs
      ensure
        end_resolution
      end

      # @return [Integer] the number of resolver iterations in between calls to
      #   {#resolver_ui}'s {UI#indicate_progress} method
      private property iteration_rate : Int32?

      # @return [Time] the time at which resolution began
      private property started_at : Time?

      # @return [Array<ResolutionState>] the stack of states for the resolution
      private getter states : Array(ResolutionState(R, S))

      # Sets up the resolution process
      # @return [void]
      private def start_resolution
        @started_at = Time.local

        push_initial_state

        debug { "Starting resolution (#{@started_at})\nUser-requested dependencies: #{original_requested}" }
        resolver_ui.before_resolution
      end

      private def resolve_activated_specs
        activated.vertices.each do |_, vertex|
          next unless payload = vertex.payload

          latest_version = check_possibility_set(vertex).possibilities.reverse_each.find do |possibility|
            vertex.requirements.all? { |req| requirement_satisfied_by?(req, activated, possibility) }
          end

          activated.set_payload(vertex.name, latest_version)
        end
        activated
      end

      # Ends the resolution process
      # @return [void]
      private def end_resolution
        resolver_ui.after_resolution
        debug do
          "Finished resolution (#{@iteration_counter} steps) " \
          "(Took #{(ended_at = Time.local) - @started_at.not_nil!} seconds) (#{ended_at})"
        end
        debug { "Unactivated: " + activated.vertices.reject { |_n, v| v.payload }.keys.join(", ") } if state
        debug { "Activated: " + activated.vertices.select { |_n, v| v.payload }.keys.join(", ") } if state
      end

      include Molinillo::Delegates::ResolutionState(R, S)
      include Molinillo::Delegates::SpecificationProvider

      # Processes the topmost available {RequirementState} on the stack
      # @return [void]
      private def process_topmost_state
        if possibilities.last?
          attempt_to_activate
        else
          create_conflict
          unwind_for_conflict
        end
      rescue underlying_error : CircularDependencyError
        create_conflict(underlying_error)
        unwind_for_conflict
      end

      # @return [Object] the current possibility that the resolution is trying
      #   to activate
      private def possibility
        possibilities.last
      end

      # @return [RequirementState] the current state the resolution is
      #   operating upon
      private def state
        states.last?
      end

      private def state!
        states.last
      end

      # Creates and pushes the initial state for the resolution, based upon the
      # {#requested} dependencies
      # @return [void]
      private def push_initial_state
        graph = DependencyGraph(PossibilitySet(R, S) | S | Nil, R).new.tap do |dg|
          original_requested.each do |requested|
            vertex = dg.add_vertex(name_for(requested), nil, true)
            vertex.explicit_requirements << requested
          end
          dg.tag(:initial_state)
        end

        push_state_for_requirements(original_requested, true, graph)
      end

      # Unwinds the states stack because a conflict has been encountered
      # @return [void]
      private def unwind_for_conflict
        details_for_unwind = build_details_for_unwind
        unwind_options = unused_unwind_options
        debug(depth) { "Unwinding for conflict: #{requirement} to #{details_for_unwind.state_index / 2}" }
        conflicts.tap do |c|
          sliced_states = states.delete_at((details_for_unwind.state_index + 1)..-1)
          raise_error_unless_state(c)
          activated.rewind_to(sliced_states.first || :initial_state) if sliced_states
          state!.conflicts = c
          state!.unused_unwind_options = unwind_options
          filter_possibilities_after_unwind(details_for_unwind)
          index = states.size - 1
          @parents_of.each { |_, a| a.reject! { |i| i >= index } }
          state!.unused_unwind_options.reject! { |uw| uw.state_index >= index }
        end
      end

      # Raises a VersionConflict error, or any underlying error, if there is no
      # current state
      # @return [void]
      private def raise_error_unless_state(conflicts)
        return if state

        error = conflicts.values.map(&.underlying_error).compact.first?
        raise error || VersionConflict(R, S).new(conflicts, specification_provider)
      end

      # @return [UnwindDetails] Details of the nearest index to which we could unwind
      private def build_details_for_unwind
        # Get the possible unwinds for the current conflict
        current_conflict = conflicts[name]
        binding_requirements = binding_requirements_for_conflict(current_conflict)
        unwind_details = unwind_options_for_requirements(binding_requirements)

        last_detail_for_current_unwind = unwind_details.sort.last
        current_detail = last_detail_for_current_unwind

        # Look for past conflicts that could be unwound to affect the
        # requirement tree for the current conflict
        relevant_unused_unwinds = unused_unwind_options.select do |alternative|
          intersecting_requirements =
            last_detail_for_current_unwind.all_requirements &
              alternative.requirements_unwound_to_instead
          next if intersecting_requirements.empty?
          # Find the highest index unwind whilst looping through
          current_detail = alternative if alternative > current_detail
          alternative
        end

        # Add the current unwind options to the `unused_unwind_options` array.
        # The "used" option will be filtered out during `unwind_for_conflict`.
        state!.unused_unwind_options += unwind_details.reject { |detail| detail.state_index == -1 }

        # Update the requirements_unwound_to_instead on any relevant unused unwinds
        relevant_unused_unwinds.each { |d| d.requirements_unwound_to_instead << current_detail.state_requirement }
        unwind_details.each { |d| d.requirements_unwound_to_instead << current_detail.state_requirement }

        current_detail
      end

      # @param [Array<Object>] binding_requirements array of requirements that combine to create a conflict
      # @return [Array<UnwindDetails>] array of UnwindDetails that have a chance
      #    of resolving the passed requirements
      private def unwind_options_for_requirements(binding_requirements)
        unwind_details = [] of UnwindDetails(R, S)

        trees = [] of Array(R)
        binding_requirements.reverse_each do |r|
          partial_tree = [r]
          trees << partial_tree
          unwind_details << UnwindDetails(R, S).new(-1, nil, partial_tree, binding_requirements, trees, [] of R?)

          # If this requirement has alternative possibilities, check if any would
          # satisfy the other requirements that created this conflict
          requirement_state = find_state_for(r)
          if conflict_fixing_possibilities?(requirement_state, binding_requirements)
            unwind_details << UnwindDetails(R, S).new(
              states.index(requirement_state).not_nil!,
              r,
              partial_tree,
              binding_requirements,
              trees,
              [] of R?
            )
          end

          # Next, look at the parent of this requirement, and check if the requirement
          # could have been avoided if an alternative PossibilitySet had been chosen
          parent_r = parent_of(r)
          next if parent_r.nil?
          partial_tree.unshift(parent_r)
          requirement_state = find_state_for(parent_r).not_nil!
          if requirement_state.possibilities.any? { |set| !set.dependencies.includes?(r) }
            unwind_details << UnwindDetails(R, S).new(
              states.index(requirement_state).not_nil!,
              parent_r,
              partial_tree,
              binding_requirements,
              trees,
              [] of R?
            )
          end

          # Finally, look at the grandparent and up of this requirement, looking
          # for any possibilities that wouldn't create their parent requirement
          grandparent_r = parent_of(parent_r)
          until grandparent_r.nil?
            partial_tree.unshift(grandparent_r)
            requirement_state = find_state_for(grandparent_r).not_nil!
            if requirement_state.possibilities.any? { |set| !set.dependencies.includes?(parent_r) }
              unwind_details << UnwindDetails(R, S).new(
                states.index(requirement_state).not_nil!,
                grandparent_r,
                partial_tree,
                binding_requirements,
                trees,
                [] of R?
              )
            end
            parent_r = grandparent_r
            grandparent_r = parent_of(parent_r)
          end
        end

        unwind_details
      end

      # @param [DependencyState] state
      # @param [Array] binding_requirements array of requirements
      # @return [Boolean] whether or not the given state has any possibilities
      #    that could satisfy the given requirements
      private def conflict_fixing_possibilities?(state, binding_requirements)
        return false unless state

        state.possibilities.any? do |possibility_set|
          possibility_set.possibilities.any? do |poss|
            possibility_satisfies_requirements?(poss, binding_requirements)
          end
        end
      end

      # Filter's a state's possibilities to remove any that would not fix the
      # conflict we've just rewound from
      # @param [UnwindDetails] unwind_details details of the conflict just
      #   unwound from
      # @return [void]
      private def filter_possibilities_after_unwind(unwind_details)
        return unless state && !state!.possibilities.empty?

        if unwind_details.unwinding_to_primary_requirement?
          filter_possibilities_for_primary_unwind(unwind_details)
        else
          filter_possibilities_for_parent_unwind(unwind_details)
        end
      end

      # Filter's a state's possibilities to remove any that would not satisfy
      # the requirements in the conflict we've just rewound from
      # @param [UnwindDetails] unwind_details details of the conflict just unwound from
      # @return [void]
      private def filter_possibilities_for_primary_unwind(unwind_details)
        unwinds_to_state = unused_unwind_options.select { |uw| uw.state_index == unwind_details.state_index }
        unwinds_to_state << unwind_details
        unwind_requirement_sets = unwinds_to_state.map(&.conflicting_requirements)

        state!.possibilities.reject! do |possibility_set|
          possibility_set.possibilities.none? do |poss|
            unwind_requirement_sets.any? do |requirements|
              possibility_satisfies_requirements?(poss, requirements)
            end
          end
        end
      end

      # @param [Object] possibility a single possibility
      # @param [Array] requirements an array of requirements
      # @return [Boolean] whether the possibility satisfies all of the
      #    given requirements
      private def possibility_satisfies_requirements?(possibility, requirements)
        name = name_for(possibility)

        activated.tag(:swap)
        activated.set_payload(name, possibility) if activated.vertex_named(name)
        satisfied = requirements.all? { |r| requirement_satisfied_by?(r, activated, possibility) }
        activated.rewind_to(:swap)

        satisfied
      end

      # Filter's a state's possibilities to remove any that would (eventually)
      # create a requirement in the conflict we've just rewound from
      # @param [UnwindDetails] unwind_details details of the conflict just unwound from
      # @return [void]
      private def filter_possibilities_for_parent_unwind(unwind_details)
        unwinds_to_state = unused_unwind_options.select { |uw| uw.state_index == unwind_details.state_index }
        unwinds_to_state << unwind_details

        primary_unwinds = unwinds_to_state.select(&.unwinding_to_primary_requirement?).uniq
        parent_unwinds = unwinds_to_state.uniq - primary_unwinds

        allowed_possibility_sets = primary_unwinds.flat_map do |unwind|
          states[unwind.state_index].possibilities.select do |possibility_set|
            possibility_set.possibilities.any? do |poss|
              possibility_satisfies_requirements?(poss, unwind.conflicting_requirements)
            end
          end
        end

        requirements_to_avoid = parent_unwinds.flat_map(&.sub_dependencies_to_avoid)

        state!.possibilities.reject! do |possibility_set|
          !allowed_possibility_sets.includes?(possibility_set) &&
            (requirements_to_avoid - possibility_set.dependencies).empty?
        end
      end

      # @param [Conflict] conflict
      # @return [Array] minimal array of requirements that would cause the passed
      #    conflict to occur.
      private def binding_requirements_for_conflict(conflict)
        return [conflict.requirement] if conflict.possibility.nil?

        possible_binding_requirements = conflict.requirements.values.flatten.uniq

        # When there’s a `CircularDependency` error the conflicting requirement
        # (the one causing the circular) won’t be `conflict.requirement`
        # (which won’t be for the right state, because we won’t have created it,
        # because it’s circular).
        # We need to make sure we have that requirement in the conflict’s list,
        # otherwise we won’t be able to unwind properly, so we just return all
        # the requirements for the conflict.
        return possible_binding_requirements if conflict.underlying_error

        possibilities = search_for(conflict.requirement)

        # If all the requirements together don't filter out all possibilities,
        # then the only two requirements we need to consider are the initial one
        # (where the dependency's version was first chosen) and the last
        if binding_requirement_in_set?(nil, possible_binding_requirements, possibilities)
          return [conflict.requirement, requirement_for_existing_name(name_for(conflict.requirement))].compact
        end

        # Loop through the possible binding requirements, removing each one
        # that doesn't bind. Use a `reverse_each` as we want the earliest set of
        # binding requirements, and don't use `reject!` as we wish to refine the
        # array *on each iteration*.
        binding_requirements = possible_binding_requirements.dup
        possible_binding_requirements.reverse_each do |req|
          next if req == conflict.requirement
          unless binding_requirement_in_set?(req, binding_requirements, possibilities)
            binding_requirements -= [req]
          end
        end

        binding_requirements
      end

      # @param [Object] requirement we wish to check
      # @param [Array] possible_binding_requirements array of requirements
      # @param [Array] possibilities array of possibilities the requirements will be used to filter
      # @return [Boolean] whether or not the given requirement is required to filter
      #    out all elements of the array of possibilities.
      private def binding_requirement_in_set?(requirement, possible_binding_requirements, possibilities)
        possibilities.any? do |poss|
          possibility_satisfies_requirements?(poss, possible_binding_requirements - [requirement])
        end
      end

      # @param [Object] requirement
      # @return [Object] the requirement that led to `requirement` being added
      #   to the list of requirements.
      private def parent_of(requirement)
        return unless requirement
        return unless index = @parents_of[requirement].last?
        return unless parent_state = @states[index]
        parent_state.requirement
      end

      # @param [String] name
      # @return [Object] the requirement that led to a version of a possibility
      #   with the given name being activated.
      private def requirement_for_existing_name(name)
        return nil unless vertex = activated.vertex_named(name)
        return nil unless vertex.payload
        states.find { |s| s.name == name }.not_nil!.requirement
      end

      # @param [Object] requirement
      # @return [ResolutionState] the state whose `requirement` is the given
      #   `requirement`.
      private def find_state_for(requirement)
        return nil unless requirement
        states.find { |i| requirement == i.requirement }
      end

      # @param [Object] underlying_error
      # @return [Conflict] a {Conflict} that reflects the failure to activate
      #   the {#possibility} in conjunction with the current {#state}
      private def create_conflict(underlying_error = nil)
        vertex = activated.vertex_named!(name)
        locked_requirement = locked_requirement_named(name)

        requirements = Hash(String | S, Array(R)).new
        unless vertex.explicit_requirements.empty?
          requirements[name_for_explicit_dependency_source] = vertex.explicit_requirements
        end
        requirements[name_for_locking_dependency_source] = [locked_requirement] if locked_requirement
        vertex.incoming_edges.each do |edge|
          (requirements[check_possibility_set(edge.origin).latest_version] ||= [] of R).unshift(edge.requirement)
        end

        activated_by_name = {} of String => S
        activated.each { |v| activated_by_name[v.name] = check_possibility_set(v).latest_version if v.payload }
        conflicts[name.not_nil!] = Conflict(R, S).new(
          requirement.not_nil!,
          requirements,
          if vertex.payload
            check_possibility_set(vertex).latest_version
          end,
          possibilities.last?,
          locked_requirement,
          requirement_trees,
          activated_by_name,
          underlying_error
        )
      end

      # @return [Array<Array<Object>>] The different requirement
      #   trees that led to every requirement for the current spec.
      private def requirement_trees
        vertex = activated.vertex_named!(name)
        vertex.requirements.map { |r| requirement_tree_for(r) }
      end

      # @param [Object] requirement
      # @return [Array<Object>] the list of requirements that led to
      #   `requirement` being required.
      private def requirement_tree_for(requirement)
        tree = [] of R
        while requirement
          tree.unshift(requirement)
          requirement = parent_of(requirement)
        end
        tree
      end

      @progress_rate : Float64?

      # Indicates progress roughly once every second
      # @return [void]
      def indicate_progress
        @iteration_counter += 1
        # @progress_rate ||= resolver_ui.progress_rate
        # if iteration_rate.nil?
        #   if Time.now - @started_at.not_nil! >= @progress_rate.not_nil!
        #     self.iteration_rate = @iteration_counter
        #   end
        # end

        # if iteration_rate && (@iteration_counter % iteration_rate) == 0
        #   resolver_ui.indicate_progress
        # end
      end

      # Calls the {#resolver_ui}'s {UI#debug} method
      # @param [Integer] depth the depth of the {#states} stack
      # @param [Proc] block a block that yields a {#to_s}
      # @return [void]
      private def debug(depth = 0)
        resolver_ui.debug(depth) { yield }
      end

      # Attempts to activate the current {#possibility}
      # @return [void]
      private def attempt_to_activate
        debug(depth) { "Attempting to activate " + possibility.to_s }
        existing_vertex = activated.vertex_named!(name)
        if existing_vertex.payload
          debug(depth) { "Found existing spec (#{existing_vertex.payload})" }
          attempt_to_filter_existing_spec(existing_vertex)
        else
          latest = possibility.latest_version
          possibility.possibilities.select! do |possibility|
            requirement_satisfied_by?(requirement.not_nil!, activated.not_nil!, possibility)
          end
          if !possibility.latest_version?
            # ensure there's a possibility for better error messages
            possibility.possibilities << latest if latest
            create_conflict
            unwind_for_conflict
          else
            activate_new_spec
          end
        end
      end

      # Attempts to update the existing vertex's `PossibilitySet` with a filtered version
      # @return [void]
      private def attempt_to_filter_existing_spec(vertex)
        filtered_set = filtered_possibility_set(vertex)
        if !filtered_set.possibilities.empty?
          activated.set_payload(name.not_nil!, filtered_set)
          new_requirements = requirements.dup
          push_state_for_requirements(new_requirements, false)
        else
          create_conflict
          debug(depth) { "Unsatisfied by existing spec (#{vertex.payload})" }
          unwind_for_conflict
        end
      end

      # Generates a filtered version of the existing vertex's `PossibilitySet` using the
      # current state's `requirement`
      # @param [Object] vertex existing vertex
      # @return [PossibilitySet] filtered possibility set
      private def filtered_possibility_set(vertex)
        payload = check_possibility_set(vertex)
        PossibilitySet(R, S).new(payload.dependencies, payload.possibilities & possibility.possibilities)
      end

      # @param [String] requirement_name the spec name to search for
      # @return [Object] the locked spec named `requirement_name`, if one
      #   is found on {#base}
      private def locked_requirement_named(requirement_name)
        vertex = base.vertex_named(requirement_name)
        vertex && vertex.payload
      end

      # Add the current {#possibility} to the dependency graph of the current
      # {#state}
      # @return [void]
      private def activate_new_spec
        conflicts.delete(name)
        debug(depth) { "Activated #{name} at #{possibility}" }
        activated.set_payload(name.not_nil!, possibility)
        require_nested_dependencies_for(possibility)
      end

      # Requires the dependencies that the recently activated spec has
      # @param [Object] possibility_set the PossibilitySet that has just been
      #   activated
      # @return [void]
      private def require_nested_dependencies_for(possibility_set)
        nested_dependencies = dependencies_for(possibility_set.latest_version)
        debug(depth) { "Requiring nested dependencies (#{nested_dependencies.join(", ")})" }
        nested_dependencies.each do |d|
          activated.add_child_vertex(name_for(d), nil, [name_for(possibility_set.latest_version)], d)
          parent_index = states.size - 1
          parents = @parents_of[d]
          parents << parent_index if parents.empty?
        end

        push_state_for_requirements(requirements + nested_dependencies, !nested_dependencies.empty?)
      end

      # Pushes a new {DependencyState} that encapsulates both existing and new
      # requirements
      # @param [Array] new_requirements
      # @param [Boolean] requires_sort
      # @param [Object] new_activated
      # @return [void]
      private def push_state_for_requirements(new_requirements, requires_sort = true, new_activated = activated)
        new_requirements = sort_dependencies(new_requirements.uniq, new_activated, conflicts) if requires_sort
        new_requirement = nil
        loop do
          new_requirement = new_requirements.shift?
          break if new_requirement.nil? || states.none? { |s| s.requirement == new_requirement }
        end
        new_name = new_requirement ? name_for(new_requirement) : ""
        possibilities = possibilities_for_requirement(new_requirement)
        handle_missing_or_push_dependency_state DependencyState(R, S).new(
          new_name, new_requirements, new_activated,
          new_requirement, possibilities, depth, conflicts.dup, unused_unwind_options.dup
        )
      end

      # Checks a proposed requirement with any existing locked requirement
      # before generating an array of possibilities for it.
      # @param [Object] requirement the proposed requirement
      # @param [Object] activated
      # @return [Array] possibilities
      private def possibilities_for_requirement(requirement, activated = self.activated)
        return [] of PossibilitySet(R, S) unless requirement
        if locked_requirement_named(name_for(requirement))
          return locked_requirement_possibility_set(requirement, activated)
        end

        group_possibilities(search_for(requirement))
      end

      # @param [Object] requirement the proposed requirement
      # @param [Object] activated
      # @return [Array] possibility set containing only the locked requirement, if any
      private def locked_requirement_possibility_set(requirement, activated = self.activated)
        all_possibilities = search_for(requirement)
        locked_requirement = locked_requirement_named(name_for(requirement)).not_nil!

        # Longwinded way to build a possibilities array with either the locked
        # requirement or nothing in it. Required, since the API for
        # locked_requirement isn't guaranteed.
        locked_possibilities = all_possibilities.select do |possibility|
          requirement_satisfied_by?(locked_requirement, activated, possibility)
        end

        group_possibilities(locked_possibilities)
      end

      # Build an array of PossibilitySets, with each element representing a group of
      # dependency versions that all have the same sub-dependency version constraints
      # and are contiguous.
      # @param [Array] possibilities an array of possibilities
      # @return [Array<PossibilitySet>] an array of possibility sets
      private def group_possibilities(possibilities)
        possibility_sets = [] of PossibilitySet(R, S)
        current_possibility_set = nil

        possibilities.reverse_each do |possibility|
          dependencies = dependencies_for(possibility)
          if current_possibility_set && current_possibility_set.dependencies == dependencies
            current_possibility_set.possibilities.unshift(possibility)
          else
            possibility_sets.unshift(PossibilitySet(R, S).new(dependencies, [possibility]))
            current_possibility_set = possibility_sets.first
          end
        end

        possibility_sets
      end

      # Pushes a new {DependencyState}.
      # If the {#specification_provider} says to
      # {SpecificationProvider#allow_missing?} that particular requirement, and
      # there are no possibilities for that requirement, then `state` is not
      # pushed, and the vertex in {#activated} is removed, and we continue
      # resolving the remaining requirements.
      # @param [DependencyState] state
      # @return [void]
      private def handle_missing_or_push_dependency_state(state)
        if (req = state.requirement) && state.possibilities.empty? && allow_missing?(req)
          state.activated.detach_vertex_named(state.name.not_nil!)
          push_state_for_requirements(state.requirements.dup, false, state.activated)
        else
          states.push(state).tap { activated.tag(state) }
        end
      end

      private def check_possibility_set(vertex)
        payload = vertex.payload
        raise "BUG: unexpected payload: #{payload}" unless payload.is_a?(PossibilitySet)
        payload
      end
    end
  end
end
