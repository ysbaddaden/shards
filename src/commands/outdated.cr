require "./command"

module Shards
  module Commands
    class Outdated < Command
      @prereleases = false

      @up_to_date = true
      @output = IO::Memory.new

      def run(@prereleases = false)
        check_symlink_privilege

        return unless has_dependencies?

        Log.info { "Resolving dependencies" }

        solver = MolinilloSolver.new(spec, override, prereleases: @prereleases)
        solver.prepare(development: Shards.with_development?)

        packages = handle_resolver_errors(solver) { solver.solve }
        packages.each { |package| analyze(package) }

        if @up_to_date
          Log.info { "Dependencies are up to date!" }
        else
          @output.rewind
          Log.warn { "Outdated dependencies:" }
          puts @output.to_s
        end
      end

      private def analyze(package)
        unless installed_dep = Shards.info.installed[package.name]?
          Log.warn { "#{package.name}: not installed" }
          return
        end

        if installed_dep.resolver != package.resolver
          raise LockConflict.new("#{package.name} source changed")
        end

        resolver = package.resolver
        installed = installed_dep.version
        dependency = dependency_by_name package.name

        if dependency && !dependency.matches?(installed)
          raise LockConflict.new("#{package.name} requirements changed")
        end

        releases =
          if @prereleases
            resolver.available_releases
          else
            Versions.without_prereleases(resolver.available_releases)
          end
        releases = Versions.sort(releases)
        latest_release = releases.first?

        available_version = package.version

        requirement = dependency.try(&.requirement)
        case requirement
        when GitBranchRef, GitHeadRef
          requirement_branch = requirement
        else
          requirement_branch = nil
        end

        latest_ref_version = resolver.latest_version_for_ref(requirement_branch)

        if installed == latest_ref_version
          # If branch HEAD is installed, it is automatically the most recent for
          # that requirement.
          # We still need to check if a tagged release with a higher version
          # is available.
          if latest_release
            return if Versions.compare(installed, latest_release) <= 0
          else
            return
          end
        end

        case requirement
        when GitBranchRef, GitHeadRef
          # On branch requirement that branch's HEAD should be reported as
          # available version
          available_version = latest_ref_version
        when GitTagRef, GitCommitRef
          # TODO: Check if pinned commit is an ancestor of HEAD
        else
          # already the latest version?
          return if latest_release == installed
        end

        @up_to_date = false

        @output << "  * " << package.name
        @output << " (installed: " << resolver.report_version(installed)

        unless installed == available_version
          @output << ", available: " << resolver.report_version(available_version)
        end

        # also report latest version:
        if latest_release && Versions.compare(latest_release, available_version) < 0
          @output << ", latest: " << resolver.report_version(latest_release)
        end

        @output.puts ')'
      end

      # FIXME: duplicates Check#has_dependencies?
      private def has_dependencies?
        spec.dependencies.any? || (Shards.with_development? && spec.development_dependencies.any?)
      end

      private def dependency_by_name(name : String)
        override.try(&.dependencies.find { |o| o.name == name }) ||
          spec.dependencies.find { |o| o.name == name } ||
          spec.development_dependencies.find { |o| o.name == name }
      end
    end
  end
end
