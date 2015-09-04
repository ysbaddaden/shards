require "../spec"
require "../lock"
require "../manager"
require "./command"

module Shards
  module Commands
    # OPTIMIZE: avoid updating GIT caches until required
    class Install < Command
      getter :path, :manager

      def initialize(@path, groups)
        spec = Spec.from_file(path)
        @manager = Shards::Manager.new(spec, groups)
        @locks = Lock.from_file(lock_file_path) if lock_file?
      end

      def run
        manager.resolve

        if locks = @locks
          install(manager.packages, locks)
        else
          install(manager.packages)
        end

        unless lock_file?
          File.open(lock_file_path, "w") { |file| manager.to_lock(file) }
        end
      end

      private def install(packages : Set, locks : Array(Dependency))
        packages.each do |package|
          version = nil

          if lock = locks.find { |dependency| dependency.name == package.name }
            if version = lock["version"]?
              unless version == package.version
                raise LockConflict.new("#{package.name} requirements changed")
              end
            elsif version = lock["commit"]?
              unless package.matches?(version)
                raise LockConflict.new("#{package.name} requirements changed")
              end
            else
              raise InvalidLock.new # unknown lock resolver
            end
          else
            raise LockConflict.new("unknown #{package.name} dependency")
          end

          install(package, version)
        end
      end

      private def install(packages : Set)
        packages.each { |package| install(package) }
      end

      private def install(package : Package, version = nil)
        version ||= package.version

        if package.installed?(version, loose: true)
          Shards.logger.info "Using #{package.name} (#{version})"
        else
          Shards.logger.info "Installing #{package.name} (#{version})"
          package.install(version)
        end
      end

      private def lock_file?
        File.exists?(lock_file_path)
      end

      private def lock_file_path
        File.join(path, LOCK_FILENAME)
      end
    end

    def self.install(path = Dir.working_directory, groups = DEFAULT_GROUPS)
      Install.new(path, groups).run
    end
  end
end
