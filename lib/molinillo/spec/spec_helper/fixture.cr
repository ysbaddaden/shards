require "json"

class Molinillo::Fixture
  include JSON::Serializable

  property name : String
  property index : String?
  property requested : Hash(String, String)
  property base : Array(Dependency)
  property resolved : Array(Dependency)
  property conflicts : Array(String)
end

class Molinillo::Fixture::Dependency
  include JSON::Serializable

  property name : String
  property version : String
  property dependencies : Array(Dependency)
end
