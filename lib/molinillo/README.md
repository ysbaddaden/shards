# crystal-molinillo

A port of [Molinillo](https://github.com/CocoaPods/Molinillo/) (generic dependency resolution algorithm) to [Crystal](https://crystal-lang.org)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     molinillo:
       github: crystal-lang/crystal-molinillo
   ```

2. Run `shards install`

## Usage

```crystal
require "molinillo"
```

This was built to be used by [Shards](https://github.com/crystal-lang/shards). Check [`MolinilloSolver`](https://github.com/crystal-lang/shards/blob/master/src/molinillo_solver.cr) for an example of integration.

## Development

This code uses a subrepository with test fixtures. Make sure you clone the repository with `--recursive` before running tests:

```
git clone --recursive https://github.com/crystal-lang/crystal-molinillo
```

## Contributing

1. Fork it (<https://github.com/crystal-lang/crystal-molinillo/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Juan Wajnerman](https://github.com/waj) - creator and maintainer
