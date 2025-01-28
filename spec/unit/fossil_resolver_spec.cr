require "./spec_helper"

private def resolver(name)
  Shards::FossilResolver.new(name, fossil_url(name))
end

module Shards
  class FossilResolver
    # Allow overriding `source` for the specs
    def source=(@source)
      @origin_url = nil # This needs to be cleared so that #origin_url re-runs `fossil remote-url`
    end

    # Direct set tool version for testing
    def self.set_version(verstr : String)
      @@version = verstr
    end
  end

  describe FossilResolver, tags: %w[fossil] do
    before_each do
      create_fossil_repository "empty"
      create_fossil_commit "empty", "initial release"

      create_fossil_repository "unreleased"
      create_fossil_version_commit "unreleased", "0.1.0"
      checkout_new_fossil_branch "unreleased", "branch"
      create_fossil_commit "unreleased", "testing"
      checkout_fossil_rev "unreleased", "trunk"

      create_fossil_repository "unreleased-bm"
      create_fossil_version_commit "unreleased-bm", "0.1.0"
      create_fossil_commit "unreleased-bm", "testing"
      checkout_fossil_rev "unreleased-bm", "trunk"

      create_fossil_repository "library", "0.0.1", "0.1.0", "0.1.1", "0.1.2", "0.2.0"

      # Create a version tag not prefixed by 'v' which should be ignored
      create_fossil_tag "library", "99.9.9"
    end

    it "normalizes sources" do
      # don't normalise other domains
      FossilResolver.normalize_key_source("fossil", "HTTPs://myfossilserver.com/Repo").should eq({"fossil", "HTTPs://myfossilserver.com/Repo"})

      # don't change protocol from ssh
      FossilResolver.normalize_key_source("fossil", "ssh://fossil@myfossilserver.com/Repo").should eq({"fossil", "ssh://fossil@myfossilserver.com/Repo"})
    end

    it "available releases" do
      # Since we're working with the local filesystem, we need to use the .fossil files
      resolver("empty.fossil").available_releases.should be_empty
      resolver("library.fossil").available_releases.should eq(versions ["0.0.1", "0.1.0", "0.1.1", "0.1.2", "0.2.0"])
    end

    it "latest version for ref" do
      expect_raises(Shards::Error, "No shard.yml was found for shard \"empty.fossil\" at commit #{fossil_commits(:empty)[0]}") do
        resolver("empty.fossil").latest_version_for_ref(fossil_branch "tip")
      end
      expect_raises(Shards::Error, "No shard.yml was found for shard \"empty.fossil\" at commit #{fossil_commits(:empty)[0]}") do
        resolver("empty.fossil").latest_version_for_ref(nil)
      end
      resolver("unreleased.fossil").latest_version_for_ref(fossil_branch "trunk").should eq(version "0.1.0+fossil.commit.#{fossil_commits(:unreleased)[0]}")
      resolver("unreleased.fossil").latest_version_for_ref(fossil_branch "branch").should eq(version "0.1.0+fossil.commit.#{fossil_commits(:unreleased, "branch")[0]}")
      resolver("unreleased.fossil").latest_version_for_ref(nil).should eq(version "0.1.0+fossil.commit.#{fossil_commits(:unreleased)[0]}")
      resolver("unreleased-bm.fossil").latest_version_for_ref(fossil_branch "trunk").should eq(version "0.1.0+fossil.commit.#{fossil_commits("unreleased-bm")[0]}")
      resolver("unreleased-bm.fossil").latest_version_for_ref(nil).should eq(version "0.1.0+fossil.commit.#{fossil_commits("unreleased-bm")[0]}")
      resolver("library.fossil").latest_version_for_ref(fossil_branch "trunk").should eq(version "0.2.0+fossil.commit.#{fossil_commits(:library)[0]}")
      resolver("library.fossil").latest_version_for_ref(nil).should eq(version "0.2.0+fossil.commit.#{fossil_commits(:library)[0]}")
      expect_raises(Shards::Error, "Could not find branch foo for shard \"library.fossil\" in the repository #{fossil_url(:library)}") do
        resolver("library.fossil").latest_version_for_ref(fossil_branch "foo")
      end
    end

    it "versions for" do
      expect_raises(Shards::Error, "No shard.yml was found for shard \"empty.fossil\" at commit #{fossil_commits(:empty)[0]}") do
        resolver("empty.fossil").versions_for(Any)
      end
      resolver("library.fossil").versions_for(Any).should eq(versions ["0.0.1", "0.1.0", "0.1.1", "0.1.2", "0.2.0"])
      resolver("library.fossil").versions_for(VersionReq.new "~> 0.1.0").should eq(versions ["0.1.0", "0.1.1", "0.1.2"])
      resolver("library.fossil").versions_for(fossil_branch "trunk").should eq(versions ["0.2.0+fossil.commit.#{fossil_commits(:library)[0]}"])
      resolver("unreleased.fossil").versions_for(fossil_branch "trunk").should eq(versions ["0.1.0+fossil.commit.#{fossil_commits(:unreleased)[0]}"])
      resolver("unreleased.fossil").versions_for(Any).should eq(versions ["0.1.0+fossil.commit.#{fossil_commits(:unreleased)[0]}"])
      resolver("unreleased-bm.fossil").versions_for(fossil_branch "trunk").should eq(versions ["0.1.0+fossil.commit.#{fossil_commits("unreleased-bm")[0]}"])
      resolver("unreleased-bm.fossil").versions_for(Any).should eq(versions ["0.1.0+fossil.commit.#{fossil_commits("unreleased-bm")[0]}"])
    end

    it "read spec for release" do
      spec = resolver("library.fossil").spec(version "0.1.1")
      spec.original_version.should eq(version "0.1.1")
      spec.version.should eq(version "0.1.1")
    end

    it "read spec for commit" do
      version = version("0.2.0+fossil.commit.#{fossil_commits(:library)[0]}")
      spec = resolver("library.fossil").spec(version)
      spec.original_version.should eq(version "0.2.0")
      spec.version.should eq(version)
    end

    it "install" do
      library = resolver("library.fossil")

      library.install_sources(version("0.1.2"), install_path("library"))
      File.exists?(install_path("library", "src/library.cr")).should be_true
      File.exists?(install_path("library", "shard.yml")).should be_true
      Spec.from_file(install_path("library", "shard.yml")).version.should eq(version "0.1.2")

      library.install_sources(version("0.2.0"), install_path("library"))
      Spec.from_file(install_path("library", "shard.yml")).version.should eq(version "0.2.0")
    end

    it "install commit" do
      library = resolver("library.fossil")
      version = version "0.2.0+fossil.commit.#{fossil_commits(:library)[0]}"
      library.install_sources(version, install_path("library"))
      Spec.from_file(install_path("library", "shard.yml")).version.should eq(version "0.2.0")
    end

    it "origin changed" do
      library = FossilResolver.new("library", fossil_url("library.fossil"))
      library.install_sources(version("0.1.2"), install_path("library"))

      # Change the origin in the cache repo to https://foss.heptapod.net/foo/bar
      Dir.cd(library.local_path) do
        run "fossil remote-url -R #{library.name}.fossil https://foss.heptapod.net/foo/bar"
      end

      # All of these alternatives should not trigger origin as changed
      same_origins = [
        "https://foss.heptapod.net/foo/bar",
        "https://foss.heptapod.net:1234/foo/bar",
        "http://foss.heptapod.net/foo/bar",
        "ssh://foss.heptapod.net/foo/bar",
        "bob@foss.heptapod.net:foo/bar",
        "foss.heptapod.net:foo/bar",
      ]

      same_origins.each do |origin|
        library.source = origin
        library.origin_changed?.should be_false
      end

      # These alternatives should all trigger origin as changed
      changed_origins = [
        "https://foss.heptapod.net/foo/bar2",
        "https://foss.heptapod.net/foos/bar",
        "https://hghubz.com/foo/bar",
        "file:///foss.heptapod.net/foo/bar",
        "hg@foss.heptapod.net:foo/bar2",
        "hg@foss.heptapod2.net.com:foo/bar",
        "",
      ]

      changed_origins.each do |origin|
        library.source = origin
        library.origin_changed?.should be_true
      end
    end

    it "renders report version" do
      resolver("library.fossil").report_version(version "1.2.3").should eq("1.2.3")
      resolver("library.fossil").report_version(version "1.2.3+fossil.commit.654875c9dbfa8d72fba70d65fd548d51ffb85aff").should eq("1.2.3 at 654875c")
    end

    it "#matches_ref" do
      resolver = FossilResolver.new("", "")
      resolver.matches_ref?(FossilCommitRef.new("1234567890abcdef"), Shards::Version.new("0.1.0.+fossil.commit.1234567")).should be_true
      resolver.matches_ref?(FossilCommitRef.new("1234567890abcdef"), Shards::Version.new("0.1.0.+fossil.commit.1234567890abcdef")).should be_true
      resolver.matches_ref?(FossilCommitRef.new("1234567"), Shards::Version.new("0.1.0.+fossil.commit.1234567890abcdef")).should be_true
    end

    it "#supports_format_arg" do
      installed_version = FossilResolver.version.not_nil!
      resolver = FossilResolver.new("", "")
      FossilResolver.set_version "1.37"
      resolver.supports_format_arg?.should eq false
      FossilResolver.set_version "2.12"
      resolver.supports_format_arg?.should eq false
      FossilResolver.set_version "2.13"
      resolver.supports_format_arg?.should eq false
      FossilResolver.set_version "2.14"
      resolver.supports_format_arg?.should eq true
      FossilResolver.set_version "2.15"
      resolver.supports_format_arg?.should eq true
      FossilResolver.set_version "3.0"
      resolver.supports_format_arg?.should eq true
      FossilResolver.set_version installed_version
    end

    it "#supports_workdir_arg" do
      installed_version = FossilResolver.version.not_nil!
      resolver = FossilResolver.new("", "")
      FossilResolver.set_version "1.37"
      resolver.supports_workdir_arg?.should eq false
      FossilResolver.set_version "2.11"
      resolver.supports_workdir_arg?.should eq false
      FossilResolver.set_version "2.12"
      resolver.supports_workdir_arg?.should eq true
      FossilResolver.set_version "2.13"
      resolver.supports_workdir_arg?.should eq true
      FossilResolver.set_version "3.0"
      resolver.supports_workdir_arg?.should eq true
      FossilResolver.set_version installed_version
    end
  end
end
